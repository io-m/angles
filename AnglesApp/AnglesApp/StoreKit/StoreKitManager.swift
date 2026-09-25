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
    private(set) var serverSyncPending = false
    private var isProbingSubscription = false
    private var hasSignedOutSession = false
    @ObservationIgnored private var accountToken: UUID?
    @ObservationIgnored private var accountGeneration: UInt64 = 0
    @ObservationIgnored private var activeEnvironment: String?
    @ObservationIgnored private var pendingSignedTransactions: [String] = []
    @ObservationIgnored private let profileService = ProfileService()

    private var transactionListener: Task<Void, Never>?
    private var unfinishedListener: Task<Void, Never>?
    @ObservationIgnored private var unfinishedProcessingTask: Task<Void, Never>?
    @ObservationIgnored private var offerProbeTask: Task<Void, Never>?
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

    static func activeUntilLine(for expiresAt: Date?) -> String {
        guard let expiresAt else {
            return "Active subscription"
        }
        return "Active until \(expiresAt.formatted(date: .abbreviated, time: .omitted))"
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

    func configureAccount(userID: String?) {
        guard let userID else {
            guard accountToken != nil else { return }
            invalidateAccountWork()
            accountToken = nil
            return
        }
        guard let token = UUID(uuidString: userID) else {
            invalidateAccountWork()
            accountToken = nil
            errorMessage = "Your account could not be linked to App Store purchases. Sign in again."
            return
        }
        let changed = accountToken != token
        guard changed else {
            return
        }
        invalidateAccountWork()
        accountToken = token
        unfinishedProcessingTask = Task { [weak self] in
            await self?.processUnfinishedTransactionsOnce()
        }
    }

    /// Launch. Call after `loadProducts()` and the Keychain session restore, so the refresh can
    /// read subscription status and a live account session is never read as signed out.
    func prepare(hasAccountSession: Bool) async {
        if hasAccountSession, isSignedOut {
            signIn()
        }
        let context = currentAccountContext
        if context != nil {
            unfinishedProcessingTask?.cancel()
            unfinishedProcessingTask = Task { [weak self] in
                await self?.processUnfinishedTransactionsOnce()
            }
        }
        await refreshEntitlements(lockWhenEmpty: true, context: context)
        guard context == currentAccountContext else {
            return
        }
        entitlementsReady = true
        // Detached: the launch gate must not wait on a history read to pick a destination.
        offerProbeTask?.cancel()
        offerProbeTask = Task { [weak self] in
            await self?.probeSubscriptionOffer()
        }
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
        guard let context = currentAccountContext else {
            errorMessage = "Sign in again before subscribing."
            return false
        }

        errorMessage = nil
        holdCheckoutUntilHome()
        isPurchasing = true
        signIn()
        defer {
            if isCurrent(context) {
                isPurchasing = false
                if !hasUnlockedFullApp {
                    releaseCheckoutLock()
                }
            }
        }

        await refreshEntitlements(lockWhenEmpty: true, context: context)
        guard isCurrent(context) else { return false }
        if hasUnlockedFullApp {
            return true
        }

        do {
            let result = try await product.purchase(options: [.appAccountToken(context.token)])
            guard isCurrent(context) else { return false }
            switch result {
            case .success(let verification):
                try await applyVerifiedTransaction(
                    verification,
                    isFreshPurchase: true,
                    context: context
                )
                guard isCurrent(context) else { return false }
                if !hasUnlockedFullApp {
                    errorMessage = Self.purchaseConfirmationError
                }
                return hasUnlockedFullApp
            case .pending:
                errorMessage = "Your purchase is pending approval."
                return false
            case .userCancelled:
                await refreshEntitlements(lockWhenEmpty: true, context: context)
                guard isCurrent(context) else { return false }
                return hasUnlockedFullApp
            @unknown default:
                errorMessage = "The purchase could not be completed."
                return false
            }
        } catch is StoreKitVerificationError {
            guard isCurrent(context) else { return false }
            errorMessage = "This purchase could not be verified. Try again."
            return false
        } catch {
            guard isCurrent(context) else { return false }
            errorMessage = "The purchase could not be completed. Try again."
            return false
        }
    }

    @discardableResult
    func purchase(productID: String) async -> Bool {
        guard Self.productIDs.contains(productID), !isBusy else {
            return false
        }
        guard let context = currentAccountContext else {
            errorMessage = "Sign in again before subscribing."
            return false
        }

        if product(for: productID) == nil {
            await loadProducts()
            guard isCurrent(context) else { return false }
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
        guard let context = currentAccountContext else {
            errorMessage = "Sign in again before restoring purchases."
            return false
        }

        isRestoring = true
        errorMessage = nil
        holdCheckoutUntilHome()
        signIn()
        defer {
            if isCurrent(context) {
                isRestoring = false
                if !hasUnlockedFullApp {
                    releaseCheckoutLock()
                }
            }
        }

        await refreshEntitlements(lockWhenEmpty: true, context: context)
        guard isCurrent(context) else { return false }
        if hasUnlockedFullApp {
            errorMessage = nil
            return true
        }

        var syncError: Error?
        do {
            try await AppStore.sync()
            guard isCurrent(context) else { return false }
        } catch {
            guard isCurrent(context) else { return false }
            syncError = error
            Self.debugLog("AppStore.sync failed: \(error.localizedDescription)")
        }

        await refreshEntitlements(lockWhenEmpty: true, context: context)
        guard isCurrent(context) else { return false }
        if hasUnlockedFullApp {
            errorMessage = nil
            return true
        }
        if let syncError, Self.isNetworkFailure(syncError) {
            errorMessage = Self.restoreNetworkError
            return false
        }

        let history = await membershipHistoryProbe(context: context)
        guard isCurrent(context) else { return false }
        switch history {
        case .active:
            await refreshEntitlements(lockWhenEmpty: false, context: context)
            guard isCurrent(context) else { return false }
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
        guard let context = currentAccountContext,
              !isProbingSubscription,
              !hasUnlockedFullApp else {
            return
        }

        isProbingSubscription = true
        defer {
            if isCurrent(context) {
                isProbingSubscription = false
            }
        }

        let history = await membershipHistoryProbe(context: context)
        guard isCurrent(context) else {
            return
        }

        switch history {
        case .active:
            priorMembershipProductID = nil
            await refreshEntitlements(lockWhenEmpty: false, context: context)
            guard isCurrent(context) else { return }
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
        await refreshEntitlements(lockWhenEmpty: true, context: currentAccountContext)
    }

    /// Local session only. Does not cancel the Apple subscription.
    func signOut() {
        invalidateAccountWork()
        errorMessage = nil
        priorMembershipProductID = nil
        accountToken = nil
        isSignedOut = true
        Self.debugLog("local session signed out")
    }

    func clearError() {
        errorMessage = nil
    }

    func retryServerSync() async {
        guard let context = currentAccountContext else {
            errorMessage = "Sign in again to sync your subscription."
            return
        }
        let pending = pendingSignedTransactions
        for signedTransaction in pending {
            _ = await syncWithServer(signedTransaction, context: context)
            guard isCurrent(context) else {
                return
            }
        }
        await refreshEntitlements(lockWhenEmpty: true, context: context)
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
        guard let context = currentAccountContext else {
            return
        }
        unfinishedProcessingTask?.cancel()
        unfinishedProcessingTask = Task { [weak self] in
            await self?.processUnfinishedTransactionsOnce()
        }
        await refreshEntitlements(lockWhenEmpty: true, context: context)
        guard isCurrent(context) else {
            return
        }
        entitlementsReady = true
        if !hasUnlockedFullApp {
            offerProbeTask?.cancel()
            offerProbeTask = Task { [weak self] in
                await self?.probeSubscriptionOffer()
            }
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
        guard let context = currentAccountContext else {
            Self.debugLog("deferred transaction until an Angles account is configured")
            return
        }
        do {
            try await applyVerifiedTransaction(result, context: context)
        } catch {
            Self.debugLog("verification failed for incoming transaction")
        }
    }

    private func applyVerifiedTransaction(
        _ result: VerificationResult<Transaction>,
        isFreshPurchase: Bool = false,
        context: AccountContext
    ) async throws {
        let transaction = try verified(result)
        Self.logTransaction(isFreshPurchase ? "purchased" : "incoming", transaction)
        guard isCurrent(context) else { return }
        guard isForConfiguredAccount(transaction, context: context) else {
            errorMessage = "This purchase is linked to another Angles account."
            return
        }

        let serverResult = await syncWithServer(result.jwsRepresentation, context: context)
        guard isCurrent(context) else {
            // A confirmed request used the captured account's bearer. Finishing is safe and
            // prevents a completed transaction from looping, but no new account state changes.
            if case .confirmed = serverResult {
                await transaction.finish()
            }
            return
        }
        if case .rejected = serverResult {
            return
        }

        let unlockedFromThisTransaction: Bool
        if isFreshPurchase {
            unlockedFromThisTransaction = unlockIfEntitled(
                transaction,
                isFreshPurchase: true,
                context: context
            )
        } else {
            unlockedFromThisTransaction = false
        }
        await transaction.finish()
        guard isCurrent(context) else { return }
        // A just-verified Angles purchase is entitled even when `currentEntitlements`
        // has not listed it yet. Do not overwrite that unlock with an empty refresh, and do
        // not let an unfinished transaction pulse unlock on then off mid-checkout. Outside a
        // purchase the refresh is authoritative: an expiry or revocation must lock.
        await refreshEntitlements(
            lockWhenEmpty: !isPurchasing && !unlockedFromThisTransaction,
            context: context
        )
    }

    private func processUnfinishedTransactionsOnce() async {
        guard let context = currentAccountContext else {
            return
        }
        for await result in Transaction.unfinished {
            guard !Task.isCancelled, isCurrent(context) else {
                return
            }
            do {
                try await applyVerifiedTransaction(result, context: context)
            } catch {
                Self.debugLog("verification failed for unfinished transaction")
            }
            guard isCurrent(context) else { return }
        }
    }

    @discardableResult
    private func unlockIfEntitled(
        _ transaction: Transaction,
        isFreshPurchase: Bool,
        context: AccountContext
    ) -> Bool {
        guard isCurrent(context) else {
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

    private func refreshEntitlements(
        lockWhenEmpty: Bool,
        context: AccountContext?
    ) async {
        guard let context else {
            if currentAccountContext == nil {
                clearActiveEntitlement()
            }
            return
        }
        guard isCurrent(context) else { return }
        let statuses = await groupStatuses(context: context)
        guard isCurrent(context) else { return }
        let detail = await activeSubscriptionDetail(statuses: statuses, context: context)
        guard isCurrent(context) else { return }
        if let detail {
            activeProductID = detail.productID
            activeExpiresAt = detail.expiresAt
            activeEnvironment = detail.environment
            priorMembershipProductID = nil
            hasUnlockedFullApp = true
            if !serverSyncPending {
                errorMessage = nil
            }
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
        guard let context = currentAccountContext else {
            return
        }
        expiryTask = Task { [weak self] in
            let wait = max(expiresAt.timeIntervalSinceNow, 0) + Self.expiryRefreshSlack
            do {
                try await Task.sleep(for: .milliseconds(Int(wait * 1000)))
            } catch {
                return
            }
            while let self, self.isBusy, self.isCurrent(context) {
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    return
                }
            }
            guard let self, !Task.isCancelled, self.isCurrent(context) else {
                return
            }
            Self.debugLog("expiry watchdog refresh")
            await self.refreshEntitlements(lockWhenEmpty: true, context: context)
            guard self.isCurrent(context) else { return }
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
    private func groupStatuses(context: AccountContext) async -> [Product.SubscriptionInfo.Status] {
        var seenGroups = Set<String>()
        var statuses: [Product.SubscriptionInfo.Status] = []
        for product in products {
            guard isCurrent(context) else { return [] }
            guard Self.productIDs.contains(product.id),
                  let subscription = product.subscription,
                  seenGroups.insert(subscription.subscriptionGroupID).inserted else {
                continue
            }
            statuses += await subscriptionStatuses(for: subscription, productID: product.id)
            guard isCurrent(context) else { return [] }
        }
        return statuses
    }

    /// Apple's live answer only: subscribed / grace / billing-retry status first, then an
    /// unexpired verified `currentEntitlements` transaction. `Transaction.latest` is deliberately
    /// absent: a leftover receipt for an expired subscription must never unlock Home.
    private func activeSubscriptionDetail(
        statuses: [Product.SubscriptionInfo.Status],
        context: AccountContext
    ) async -> ActiveSubscription? {
        for status in statuses {
            guard isCurrent(context) else { return nil }
            Self.debugLog("subscription status: \(String(describing: status.state))")
            switch status.state {
            case .subscribed, .inGracePeriod, .inBillingRetryPeriod:
                guard let transaction = try? verified(status.transaction),
                      Self.productIDs.contains(transaction.productID),
                      isAppStoreBacked(transaction),
                      isForConfiguredAccount(transaction, context: context) else {
                    Self.debugLog("ignored non-App Store status")
                    continue
                }
                Self.logTransaction("status", transaction)
                let syncResult = await syncWithServer(
                    status.transaction.jwsRepresentation,
                    context: context
                )
                guard isCurrent(context) else { return nil }
                if case .rejected = syncResult {
                    continue
                }
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
            guard isCurrent(context) else { return nil }
            guard case .verified(let transaction) = result else {
                Self.debugLog("verification failed for current entitlement")
                continue
            }
            Self.logTransaction("current entitlement", transaction)
            guard isActiveAnglesEntitlement(transaction, now: now),
                  isForConfiguredAccount(transaction, context: context) else {
                continue
            }
            let syncResult = await syncWithServer(result.jwsRepresentation, context: context)
            guard isCurrent(context) else { return nil }
            if case .rejected = syncResult {
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
    private func membershipHistoryProbe(context: AccountContext) async -> MembershipHistoryProbe {
        let statuses = await groupStatuses(context: context)
        guard isCurrent(context) else { return .none }
        if await activeSubscriptionDetail(statuses: statuses, context: context) != nil {
            guard isCurrent(context) else { return .none }
            return .active
        }

        let now = Date()
        var candidates: [EndedMembershipCandidate] = []
        for productID in Self.productIDs {
            guard isCurrent(context) else { return .none }
            let latest = await Transaction.latest(for: productID)
            guard isCurrent(context) else { return .none }
            guard let result = latest,
                  case .verified(let transaction) = result,
                  Self.productIDs.contains(transaction.productID) else {
                continue
            }
            Self.logTransaction("latest", transaction)
            guard isAppStoreBacked(transaction),
                  isForConfiguredAccount(transaction, context: context) else {
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
                  isAppStoreBacked(transaction),
                  isForConfiguredAccount(transaction, context: context) else {
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

    private func isForConfiguredAccount(
        _ transaction: Transaction,
        context: AccountContext
    ) -> Bool {
        guard isCurrent(context) else { return false }
        guard let transactionToken = transaction.appAccountToken else {
            // Legacy StoreKit transactions can be claimed once by the backend.
            return true
        }
        return transactionToken == context.token
    }

    private func syncWithServer(
        _ signedTransactionInfo: String,
        context: AccountContext
    ) async -> ServerSyncResult {
        guard isCurrent(context) else { return .stale }
        do {
            let body = try await profileService.syncSubscription(
                signedTransactionInfo: signedTransactionInfo
            )
            guard isCurrent(context) else {
                return .confirmed(body)
            }
            pendingSignedTransactions.removeAll { $0 == signedTransactionInfo }
            serverSyncPending = !pendingSignedTransactions.isEmpty
            if !serverSyncPending, errorMessage == Self.serverSyncError {
                errorMessage = nil
            }
            return .confirmed(body)
        } catch let APIError.httpStatus(code, payload, rawBody) where code == 409 {
            guard isCurrent(context) else { return .stale }
            pendingSignedTransactions.removeAll { $0 == signedTransactionInfo }
            serverSyncPending = !pendingSignedTransactions.isEmpty
            Self.debugLog(
                "server rejected subscription ownership: \(payload?.code ?? rawBody ?? "conflict")"
            )
            errorMessage = "This subscription is linked to another Angles account."
            return .rejected
        } catch {
            guard isCurrent(context) else { return .stale }
            if !pendingSignedTransactions.contains(signedTransactionInfo) {
                pendingSignedTransactions.append(signedTransactionInfo)
            }
            serverSyncPending = true
            errorMessage = Self.serverSyncError
            Self.debugLog("server subscription sync failed: \(error.localizedDescription)")
            return .retryable
        }
    }

    private var currentAccountContext: AccountContext? {
        guard let accountToken, !isSignedOut else {
            return nil
        }
        return AccountContext(token: accountToken, generation: accountGeneration)
    }

    private func isCurrent(_ context: AccountContext) -> Bool {
        currentAccountContext == context
    }

    /// Invalidates every continuation that captured the old account. Known child tasks are
    /// cancelled, while unstructured callers become harmless at their next generation check.
    private func invalidateAccountWork() {
        accountGeneration &+= 1
        unfinishedProcessingTask?.cancel()
        unfinishedProcessingTask = nil
        offerProbeTask?.cancel()
        offerProbeTask = nil
        expiryTask?.cancel()
        expiryTask = nil
        pendingSignedTransactions = []
        serverSyncPending = false
        isProbingSubscription = false
        isPurchasing = false
        isRestoring = false
        releaseCheckoutLock()
        priorMembershipProductID = nil
        errorMessage = nil
        clearActiveEntitlement()
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
    private static let serverSyncError = "Apple confirmed your membership, but Angles couldn’t sync it for cooking. Tap to retry."
    private static let statusTimeout: Duration = .seconds(6)
    private static let expiryRefreshSlack: TimeInterval = 2
}

private struct EndedMembershipCandidate {
    let productID: String
    let endedAt: Date
}

private struct AccountContext: Equatable {
    let token: UUID
    let generation: UInt64
}

private enum MembershipHistoryProbe {
    case active
    case ended(String)
    case none
}

private enum StoreKitVerificationError: Error {
    case failed
}

private enum ServerSyncResult {
    case confirmed(SubscriptionBody)
    case retryable
    case rejected
    case stale
}
