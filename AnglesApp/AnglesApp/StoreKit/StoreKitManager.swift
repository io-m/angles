import Foundation
import Observation
import StoreKit

enum AnglesSubscriptionStatus: Equatable {
    case inactive
    case subscribed

    var settingsLabel: String {
        switch self {
        case .inactive:
            return "Inactive"
        case .subscribed:
            return "Subscribed"
        }
    }
}

@MainActor
@Observable
final class StoreKitManager {
    static let annualProductID = "app.angles.ios.annual"
    static let monthlyProductID = "app.angles.ios.monthly"
    static let productIDs = [annualProductID, monthlyProductID]
    static let unlockDefaultsKey = "hasUnlockedFullApp"
    static let signedOutSessionKey = "hasSignedOutSession"
    private static let legacySignedOutKey = "subscriptionSignedOut"

    private(set) var products: [Product] = []
    private(set) var entitlementsReady = false
    private(set) var hasUnlockedFullApp: Bool {
        didSet {
            UserDefaults.standard.set(hasUnlockedFullApp, forKey: Self.unlockDefaultsKey)
        }
    }
    private(set) var isLoadingProducts = false
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    private(set) var isConfirmingAccess = false
    private(set) var priorMembershipProductID: String?
    private(set) var errorMessage: String?
    private(set) var activeProductID: String?
    private(set) var activeExpiresAt: Date? {
        didSet {
            if activeExpiresAt != oldValue {
                scheduleExpiryRefresh()
            }
        }
    }
    private var isProbingSubscription = false
    private var hasSignedOutSession = false
    @ObservationIgnored private var activeEnvironment: String?

    private var transactionListener: Task<Void, Never>?
    private var unfinishedListener: Task<Void, Never>?
    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    init() {
        Self.migrateLegacySignOutFlag()
        let signedOut = UserDefaults.standard.bool(forKey: Self.signedOutSessionKey)
        hasSignedOutSession = signedOut
        if signedOut {
            hasUnlockedFullApp = false
        } else {
            hasUnlockedFullApp = UserDefaults.standard.bool(forKey: Self.unlockDefaultsKey)
        }
        transactionListener = listenForTransactions()
        unfinishedListener = listenForUnfinishedTransactions()
    }

    /// Settings never treats the launch cache as an entitlement. The cache can only become
    /// visible after `prepare()` has replaced it with Apple's current answer.
    var subscriptionStatus: AnglesSubscriptionStatus {
        entitlementsReady && !isSignedOut && hasUnlockedFullApp ? .subscribed : .inactive
    }

    var hasEndedMembership: Bool {
        priorMembershipProductID != nil
    }

    var annualProduct: Product? {
        product(for: Self.annualProductID)
    }

    /// Settings subtitle: Yearly / Monthly when entitled, otherwise Inactive.
    /// Plan names match the paywall. Falls back to Subscribed when Apple confirms
    /// an entitlement but the SKU is not one we recognize.
    var settingsPlanLabel: String {
        guard subscriptionStatus == .subscribed else {
            return "Inactive"
        }
        return activePlanTitle ?? AnglesSubscriptionStatus.subscribed.settingsLabel
    }

    var activePlanTitle: String? {
        switch activeProductID {
        case Self.annualProductID:
            return "Yearly"
        case Self.monthlyProductID:
            return "Monthly"
        default:
            return nil
        }
    }

    var activeProduct: Product? {
        guard let activeProductID else { return nil }
        return product(for: activeProductID)
    }

    var monthlyProduct: Product? {
        product(for: Self.monthlyProductID)
    }

    var isBusy: Bool {
        isCheckoutOperationInFlight || isConfirmingAccess
    }

    var isCheckoutOperationInFlight: Bool {
        isPurchasing || isRestoring
    }

    var checkoutLockLines: [String] {
        if isPurchasing {
            return [
                "Talking to Apple.",
                "Confirming your selection.",
                "Finishing up.",
            ]
        }
        return [
            "Checking with Apple.",
            "Looking for your membership.",
            "Confirming your status.",
            "This can take a moment.",
        ]
    }

    func product(for productID: String) -> Product? {
        products.first { $0.id == productID }
    }

    /// Launch. Call after `loadProducts()` and the Keychain session restore, so the refresh can
    /// read subscription status and a live account session is never read as signed out.
    func prepare(hasAccountSession: Bool) async {
        if hasAccountSession, isSignedOut {
            signIn()
        }
        await refreshEntitlements()
        entitlementsReady = true
        // Detached: the launch gate must not wait on a history read to pick a destination.
        Task { await probeSubscriptionOffer() }
    }

    /// Whether the gate may treat this device as paid right now.
    var isEntitledForGate: Bool {
        entitlementsReady && !isSignedOut && hasUnlockedFullApp
    }

    var debugSnapshot: String {
        let expires = activeExpiresAt.map { ISO8601DateFormatter().string(from: $0) } ?? "nil"
        return "ready=\(entitlementsReady) unlocked=\(hasUnlockedFullApp) signedOut=\(isSignedOut) "
            + "product=\(activeProductID ?? "nil") expires=\(expires) env=\(activeEnvironment ?? "nil") "
            + "prior=\(priorMembershipProductID ?? "nil") purchasing=\(isPurchasing) restoring=\(isRestoring) "
            + "confirming=\(isConfirmingAccess)"
    }

    func loadProducts() async {
        guard !isLoadingProducts else {
            return
        }

        isLoadingProducts = true
        defer { isLoadingProducts = false }

        Self.debugLog("requested product IDs: \(Self.productIDs.joined(separator: ", "))")

        do {
            let fetched = try await Product.products(for: Set(Self.productIDs))
            products = fetched.sorted { lhs, rhs in
                productOrder(lhs.id) < productOrder(rhs.id)
            }
            let returnedIDs = fetched.map(\.id)
            Self.debugLog("returned product IDs: \(returnedIDs.isEmpty ? "(none)" : returnedIDs.joined(separator: ", "))")

            if Set(returnedIDs) != Set(Self.productIDs) {
                errorMessage = Self.productLoadError
            } else {
                errorMessage = nil
            }
        } catch {
            products = []
            Self.debugLog("product load failed: \(error.localizedDescription)")
            errorMessage = Self.productLoadError
        }
    }

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        guard Self.productIDs.contains(product.id), !isBusy else {
            return false
        }

        errorMessage = nil
        holdCheckoutUntilHome()
        isPurchasing = true
        signIn()
        defer {
            isPurchasing = false
            if !hasUnlockedFullApp {
                releaseCheckoutLock()
            }
        }

        await refreshEntitlements()
        if hasUnlockedFullApp {
            return true
        }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                try await applyVerifiedTransaction(verification, isFreshPurchase: true)
                if !hasUnlockedFullApp {
                    errorMessage = Self.purchaseConfirmationError
                }
                return hasUnlockedFullApp
            case .pending:
                errorMessage = "Your purchase is pending approval."
                return false
            case .userCancelled:
                await refreshEntitlements()
                return hasUnlockedFullApp
            @unknown default:
                errorMessage = "The purchase could not be completed."
                return false
            }
        } catch is StoreKitVerificationError {
            errorMessage = "This purchase could not be verified. Try again."
            return false
        } catch {
            errorMessage = "The purchase could not be completed. Try again."
            return false
        }
    }

    @discardableResult
    func purchase(productID: String) async -> Bool {
        guard Self.productIDs.contains(productID), !isBusy else {
            return false
        }

        if product(for: productID) == nil {
            await loadProducts()
        }
        guard let product = product(for: productID) else {
            errorMessage = Self.missingProductError
            return false
        }
        return await purchase(product)
    }

    @discardableResult
    func restorePurchases() async -> Bool {
        guard !isBusy else {
            return false
        }

        isRestoring = true
        errorMessage = nil
        holdCheckoutUntilHome()
        signIn()
        defer {
            isRestoring = false
            if !hasUnlockedFullApp {
                releaseCheckoutLock()
            }
        }

        await refreshEntitlements()
        if hasUnlockedFullApp {
            errorMessage = nil
            return true
        }

        var syncError: Error?
        do {
            try await AppStore.sync()
        } catch {
            syncError = error
            Self.debugLog("AppStore.sync failed: \(error.localizedDescription)")
        }

        await refreshEntitlements()
        if hasUnlockedFullApp {
            errorMessage = nil
            return true
        }
        if let syncError, Self.isNetworkFailure(syncError) {
            errorMessage = Self.restoreNetworkError
            return false
        }

        switch await membershipHistoryProbe() {
        case .active:
            await refreshEntitlements(lockWhenEmpty: false)
            if hasUnlockedFullApp {
                errorMessage = nil
                return true
            }
        case .ended(let productID):
            presentEndedMembership(
                productID: productID,
                message: "No active subscription was found. Choose a plan to renew."
            )
            return false
        case .none:
            break
        }

        priorMembershipProductID = nil
        errorMessage = "No active Angles subscription was found."
        return false
    }

    /// Fast local probe. Reads Apple's status and `currentEntitlements` only — never
    /// `AppStore.sync()`, so it cannot raise a password sheet.
    func probeSubscriptionOffer() async {
        guard !isSignedOut, !isProbingSubscription, !hasUnlockedFullApp else {
            return
        }

        isProbingSubscription = true
        defer { isProbingSubscription = false }

        let history = await membershipHistoryProbe()
        guard !isSignedOut else {
            priorMembershipProductID = nil
            hasUnlockedFullApp = false
            Self.debugLog("history probe kept local signed-out session locked")
            return
        }

        switch history {
        case .active:
            priorMembershipProductID = nil
            await refreshEntitlements(lockWhenEmpty: false)
        case .ended(let productID):
            presentEndedMembership(productID: productID)
        case .none:
            priorMembershipProductID = nil
        }
    }

    /// The root releases the visual hold after it has structurally prepared Home. Purchase and
    /// restore own their operation flags and clear them only when their async work actually ends.
    func releaseCheckoutLock() {
        isConfirmingAccess = false
    }

    func refreshEntitlements() async {
        await refreshEntitlements(lockWhenEmpty: true)
    }

    /// Local session only. Does not cancel the Apple subscription.
    func signOut() {
        errorMessage = nil
        priorMembershipProductID = nil
        activeProductID = nil
        activeExpiresAt = nil
        activeEnvironment = nil
        releaseCheckoutLock()
        isSignedOut = true
        hasUnlockedFullApp = false
        Self.debugLog("local session signed out")
    }

    func clearError() {
        errorMessage = nil
    }

    /// Observable mirror of the persisted flag so the gate re-reads it in the same frame.
    private var isSignedOut: Bool {
        get { hasSignedOutSession }
        set {
            hasSignedOutSession = newValue
            UserDefaults.standard.set(newValue, forKey: Self.signedOutSessionKey)
        }
    }

    /// A real account sign-in resumes StoreKit and asks Apple before the session is published.
    /// A still-live subscription goes straight Home; that is paid access, not a skipped paywall.
    func resumeAfterAccountSignIn() async {
        signIn()
        await refreshEntitlements()
        entitlementsReady = true
        if !hasUnlockedFullApp {
            Task { await probeSubscriptionOffer() }
        }
    }

    private func signIn() {
        isSignedOut = false
        Self.debugLog("local session signed in by explicit StoreKit action")
    }

    private func presentEndedMembership(productID: String, message: String? = nil) {
        priorMembershipProductID = productID
        errorMessage = message
    }

    private func holdCheckoutUntilHome() {
        isConfirmingAccess = true
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled else {
                    return
                }
                await self?.handleIncomingTransaction(result)
            }
        }
    }

    private func listenForUnfinishedTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.unfinished {
                guard !Task.isCancelled else {
                    return
                }
                await self?.handleIncomingTransaction(result)
            }
        }
    }

    private func handleIncomingTransaction(_ result: VerificationResult<Transaction>) async {
        do {
            try await applyVerifiedTransaction(result)
        } catch {
            Self.debugLog("verification failed for incoming transaction")
        }
    }

    private func applyVerifiedTransaction(
        _ result: VerificationResult<Transaction>,
        isFreshPurchase: Bool = false
    ) async throws {
        let transaction = try verified(result)
        Self.logTransaction(isFreshPurchase ? "purchased" : "incoming", transaction)

        let unlockedFromThisTransaction: Bool
        if isFreshPurchase {
            unlockedFromThisTransaction = unlockIfEntitled(transaction, isFreshPurchase: true)
        } else {
            unlockedFromThisTransaction = false
        }
        await transaction.finish()
        // A just-verified Angles purchase is entitled even when `currentEntitlements`
        // has not listed it yet. Do not overwrite that unlock with an empty refresh, and do
        // not let an unfinished transaction pulse unlock on then off mid-checkout. Outside a
        // purchase the refresh is authoritative: an expiry or revocation must lock.
        await refreshEntitlements(lockWhenEmpty: !isPurchasing && !unlockedFromThisTransaction)
    }

    @discardableResult
    private func unlockIfEntitled(_ transaction: Transaction, isFreshPurchase: Bool) -> Bool {
        guard !isSignedOut else {
            return false
        }
        guard isAppStoreBacked(transaction) else {
            Self.debugLog("ignored Xcode StoreKit Testing transaction \(transaction.productID)")
            return false
        }
        guard Self.productIDs.contains(transaction.productID) else {
            return false
        }
        guard transaction.revocationDate == nil else {
            return false
        }
        if isFreshPurchase || isActiveAnglesEntitlement(transaction, now: Date()) {
            priorMembershipProductID = nil
            // Settings names the plan even while `currentEntitlements` has not listed it yet.
            activeProductID = transaction.productID
            activeExpiresAt = transaction.expirationDate
            activeEnvironment = String(describing: transaction.environment)
            hasUnlockedFullApp = true
            Self.debugLog("unlocked from verified transaction \(transaction.productID)")
            return true
        }
        return false
    }

    private func refreshEntitlements(lockWhenEmpty: Bool) async {
        if isSignedOut {
            clearActiveEntitlement()
            return
        }

        let detail = await activeSubscriptionDetail(statuses: await groupStatuses())
        guard !isSignedOut else {
            clearActiveEntitlement()
            Self.debugLog("entitlement refresh kept local signed-out session locked")
            return
        }
        if let detail {
            activeProductID = detail.productID
            activeExpiresAt = detail.expiresAt
            activeEnvironment = detail.environment
            priorMembershipProductID = nil
            hasUnlockedFullApp = true
            errorMessage = nil
        } else if lockWhenEmpty {
            clearActiveEntitlement()
        }
        Self.debugLog(
            "entitlements active=\(detail != nil) unlocked=\(hasUnlockedFullApp) lockWhenEmpty=\(lockWhenEmpty) \(debugSnapshot)"
        )
    }

    private func clearActiveEntitlement() {
        hasUnlockedFullApp = false
        activeProductID = nil
        activeExpiresAt = nil
        activeEnvironment = nil
    }

    /// Refreshes once shortly after the live period ends, so a lapse while Home is open lands on
    /// the paywall without waiting for the next foreground. A renewal moves the date and re-arms.
    private func scheduleExpiryRefresh() {
        expiryTask?.cancel()
        expiryTask = nil
        guard let expiresAt = activeExpiresAt else {
            return
        }
        expiryTask = Task { [weak self] in
            let wait = max(expiresAt.timeIntervalSinceNow, 0) + Self.expiryRefreshSlack
            do {
                try await Task.sleep(for: .milliseconds(Int(wait * 1000)))
            } catch {
                return
            }
            while let self, self.isBusy {
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    return
                }
            }
            guard let self, !Task.isCancelled else {
                return
            }
            Self.debugLog("expiry watchdog refresh")
            await self.refreshEntitlements()
            if !self.hasUnlockedFullApp {
                await self.probeSubscriptionOffer()
            }
        }
    }

    private struct ActiveSubscription {
        let productID: String
        let expiresAt: Date?
        let environment: String
    }

    /// One status read per subscription group. Either product returns every status in the group,
    /// so reading both only doubled the time a stalled sandbox read could hold login or launch.
    private func groupStatuses() async -> [Product.SubscriptionInfo.Status] {
        var seenGroups = Set<String>()
        var statuses: [Product.SubscriptionInfo.Status] = []
        for product in products {
            guard Self.productIDs.contains(product.id),
                  let subscription = product.subscription,
                  seenGroups.insert(subscription.subscriptionGroupID).inserted else {
                continue
            }
            statuses += await subscriptionStatuses(for: subscription, productID: product.id)
        }
        return statuses
    }

    /// Apple's live answer only: subscribed / grace / billing-retry status first, then an
    /// unexpired verified `currentEntitlements` transaction. `Transaction.latest` is deliberately
    /// absent: a leftover receipt for an expired subscription must never unlock Home.
    private func activeSubscriptionDetail(
        statuses: [Product.SubscriptionInfo.Status]
    ) async -> ActiveSubscription? {
        for status in statuses {
            Self.debugLog("subscription status: \(String(describing: status.state))")
            switch status.state {
            case .subscribed, .inGracePeriod, .inBillingRetryPeriod:
                guard let transaction = try? verified(status.transaction),
                      Self.productIDs.contains(transaction.productID),
                      isAppStoreBacked(transaction) else {
                    Self.debugLog("ignored non-App Store status")
                    continue
                }
                Self.logTransaction("status", transaction)
                return ActiveSubscription(
                    productID: transaction.productID,
                    expiresAt: transaction.expirationDate,
                    environment: String(describing: transaction.environment)
                )
            default:
                continue
            }
        }

        let now = Date()
        var candidates: [ActiveSubscription] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                Self.debugLog("verification failed for current entitlement")
                continue
            }
            Self.logTransaction("current entitlement", transaction)
            guard isActiveAnglesEntitlement(transaction, now: now) else {
                continue
            }
            candidates.append(
                ActiveSubscription(
                    productID: transaction.productID,
                    expiresAt: transaction.expirationDate,
                    environment: String(describing: transaction.environment)
                )
            )
        }
        // Same subscription group, so at most one is live. Prefer Annual on a tie.
        candidates.sort {
            let lhsDate = $0.expiresAt ?? .distantPast
            let rhsDate = $1.expiresAt ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return productOrder($0.productID) < productOrder($1.productID)
        }
        return candidates.first
    }

    /// Sandbox status reads can stall. Bound every one so launch routing cannot wait forever.
    private func subscriptionStatuses(
        for subscription: Product.SubscriptionInfo,
        productID: String
    ) async -> [Product.SubscriptionInfo.Status] {
        let read = Task { try await subscription.status }
        let watchdog = Task {
            try? await Task.sleep(for: Self.statusTimeout)
            read.cancel()
        }
        defer { watchdog.cancel() }

        do {
            return try await read.value
        } catch {
            Self.debugLog("subscription status failed \(productID): \(error.localizedDescription)")
            return []
        }
    }

    /// Ended-membership UI hint only. `Transaction.latest` never reaches the unlock path: an
    /// unexpired latest receipt is neither active nor ended here, and only live status or
    /// `currentEntitlements` can report `.active`. The live group check comes first so an
    /// expired Annual cannot beat a live Monthly.
    private func membershipHistoryProbe() async -> MembershipHistoryProbe {
        let statuses = await groupStatuses()
        if await activeSubscriptionDetail(statuses: statuses) != nil {
            return .active
        }

        let now = Date()
        var candidates: [EndedMembershipCandidate] = []
        for productID in Self.productIDs {
            guard let result = await Transaction.latest(for: productID),
                  case .verified(let transaction) = result,
                  Self.productIDs.contains(transaction.productID) else {
                continue
            }
            Self.logTransaction("latest", transaction)
            guard isAppStoreBacked(transaction) else {
                continue
            }
            if isActiveAnglesEntitlement(transaction, now: now) {
                continue
            }
            candidates.append(endedCandidate(for: transaction))
        }

        for status in statuses {
            guard let transaction = try? verified(status.transaction),
                  Self.productIDs.contains(transaction.productID),
                  isAppStoreBacked(transaction) else {
                continue
            }
            switch status.state {
            case .expired, .revoked:
                candidates.append(endedCandidate(for: transaction))
            default:
                continue
            }
        }
        guard let productID = candidates.max(by: { $0.endedAt < $1.endedAt })?.productID else {
            return .none
        }
        Self.debugLog("ended membership hint \(productID)")
        return .ended(productID)
    }

    private func endedCandidate(for transaction: Transaction) -> EndedMembershipCandidate {
        EndedMembershipCandidate(
            productID: transaction.productID,
            endedAt: transaction.revocationDate ?? transaction.expirationDate ?? transaction.purchaseDate
        )
    }

    /// `Transaction.currentEntitlements` already includes grace and billing-retry while Apple
    /// still considers the user entitled. Expired, revoked, upgraded-away, or Xcode Testing
    /// receipts are skipped.
    private func isActiveAnglesEntitlement(_ transaction: Transaction, now: Date) -> Bool {
        guard isAppStoreBacked(transaction) else {
            return false
        }
        guard Self.productIDs.contains(transaction.productID) else {
            return false
        }
        guard transaction.revocationDate == nil, !transaction.isUpgraded else {
            return false
        }
        if let expirationDate = transaction.expirationDate, expirationDate <= now {
            return false
        }
        return true
    }

    private static func logTransaction(_ source: String, _ transaction: Transaction) {
        debugLog(
            "\(source) transaction \(transaction.productID) env=\(String(describing: transaction.environment)) purchase=\(transaction.purchaseDate) expiration=\(String(describing: transaction.expirationDate)) revoked=\(String(describing: transaction.revocationDate)) upgraded=\(transaction.isUpgraded)"
        )
    }

    /// Local StoreKit Testing receipts (`.xcode`) survive after `Angles.storekit` is removed.
    /// Apple's sandbox sheet does not show them; they must not unlock Home or say Subscribed.
    private func isAppStoreBacked(_ transaction: Transaction) -> Bool {
        transaction.environment != .xcode
    }

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified:
            throw StoreKitVerificationError.failed
        }
    }

    private func productOrder(_ id: String) -> Int {
        id == Self.annualProductID ? 0 : 1
    }

    private static func migrateLegacySignOutFlag() {
        if UserDefaults.standard.bool(forKey: legacySignedOutKey) {
            UserDefaults.standard.set(true, forKey: signedOutSessionKey)
        }
        UserDefaults.standard.removeObject(forKey: legacySignedOutKey)
    }

    private static func isNetworkFailure(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet,
                 .networkConnectionLost,
                 .timedOut,
                 .cannotFindHost,
                 .cannotConnectToHost,
                 .dnsLookupFailed,
                 .internationalRoamingOff,
                 .dataNotAllowed:
                return true
            default:
                break
            }
        }
        if let storeKitError = error as? StoreKitError, case .networkError = storeKitError {
            return true
        }
        return (error as NSError).domain == NSURLErrorDomain
    }

    private static func debugLog(_ message: String) {
        #if DEBUG
        print("[Angles StoreKit] \(message)")
        #endif
    }

    private static let productLoadError = "Couldn’t load subscriptions from the App Store. Check your connection and try again."
    private static let missingProductError = "Couldn’t load this subscription. Check your connection and tap Retry."
    private static let purchaseConfirmationError = "Apple didn’t confirm an active Angles subscription. Try again or restore purchases."
    private static let restoreNetworkError = "Need a connection to check your subscription."
    private static let statusTimeout: Duration = .seconds(6)
    private static let expiryRefreshSlack: TimeInterval = 2
}

private struct EndedMembershipCandidate {
    let productID: String
    let endedAt: Date
}

private enum MembershipHistoryProbe {
    case active
    case ended(String)
    case none
}

private enum StoreKitVerificationError: Error {
    case failed
}
