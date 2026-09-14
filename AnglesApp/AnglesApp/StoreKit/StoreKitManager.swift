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
    private var isProbingSubscription = false

    private var transactionListener: Task<Void, Never>?
    private var unfinishedListener: Task<Void, Never>?

    init() {
        Self.migrateLegacySignOutFlag()
        if UserDefaults.standard.bool(forKey: Self.signedOutSessionKey) {
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

    func prepare() async {
        await loadProducts()
        await refreshEntitlements()
        entitlementsReady = true
        // Products are loaded by now, so the probe can read status as well as receipts. It runs
        // detached: the launch gate must not wait on a status read to pick a destination.
        Task { await probeSubscriptionOffer() }
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
            priorMembershipProductID = nil
            hasUnlockedFullApp = true
            errorMessage = nil
            return true
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
            hasUnlockedFullApp = true
            errorMessage = nil
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
        releaseCheckoutLock()
        UserDefaults.standard.set(true, forKey: Self.signedOutSessionKey)
        hasUnlockedFullApp = false
        Self.debugLog("local session signed out")
    }

    func clearError() {
        errorMessage = nil
    }

    private var isSignedOut: Bool {
        UserDefaults.standard.bool(forKey: Self.signedOutSessionKey)
    }

    private func signIn() {
        UserDefaults.standard.set(false, forKey: Self.signedOutSessionKey)
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
        Self.debugLog("verified transaction product ID: \(transaction.productID)")
        Self.debugLog("transaction environment: \(String(describing: transaction.environment))")
        Self.debugLog(
            "transaction dates purchase=\(transaction.purchaseDate) expiration=\(String(describing: transaction.expirationDate)) revoked=\(String(describing: transaction.revocationDate))"
        )

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
            hasUnlockedFullApp = true
            Self.debugLog("unlocked from verified transaction \(transaction.productID)")
            return true
        }
        return false
    }

    private func refreshEntitlements(lockWhenEmpty: Bool) async {
        if isSignedOut {
            hasUnlockedFullApp = false
            return
        }

        let hasActiveSubscription = await hasActiveAnglesSubscription()
        guard !isSignedOut else {
            hasUnlockedFullApp = false
            Self.debugLog("entitlement refresh kept local signed-out session locked")
            return
        }
        if hasActiveSubscription {
            priorMembershipProductID = nil
            hasUnlockedFullApp = true
            errorMessage = nil
        } else if lockWhenEmpty {
            hasUnlockedFullApp = false
        }
        Self.debugLog(
            "entitlements active=\(hasActiveSubscription) unlocked=\(hasUnlockedFullApp) lockWhenEmpty=\(lockWhenEmpty)"
        )
    }

    /// Apple's live answer only. `Transaction.latest` is deliberately absent: a leftover receipt
    /// for an expired subscription must never unlock Home.
    private func hasActiveAnglesSubscription() async -> Bool {
        if await hasActiveSubscriptionStatus() {
            return true
        }
        return await hasActiveCurrentEntitlement()
    }

    private func hasActiveSubscriptionStatus() async -> Bool {
        for product in products {
            guard Self.productIDs.contains(product.id), let subscription = product.subscription else {
                continue
            }
            for status in await subscriptionStatuses(for: subscription, productID: product.id) {
                Self.debugLog("subscription status \(product.id): \(String(describing: status.state))")
                switch status.state {
                case .subscribed, .inGracePeriod, .inBillingRetryPeriod:
                    guard let transaction = try? verified(status.transaction),
                          Self.productIDs.contains(transaction.productID),
                          isAppStoreBacked(transaction) else {
                        Self.debugLog("ignored non-App Store status for \(product.id)")
                        continue
                    }
                    Self.debugLog("status transaction product ID: \(transaction.productID)")
                    Self.debugLog("transaction environment: \(String(describing: transaction.environment))")
                    Self.debugLog(
                        "transaction dates purchase=\(transaction.purchaseDate) expiration=\(String(describing: transaction.expirationDate)) revoked=\(String(describing: transaction.revocationDate))"
                    )
                    return true
                default:
                    continue
                }
            }
        }
        return false
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

    private func hasActiveCurrentEntitlement() async -> Bool {
        let now = Date()
        var hasActive = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                Self.debugLog("verification failed for current entitlement")
                continue
            }

            Self.debugLog("verified current entitlement product ID: \(transaction.productID)")
            Self.debugLog("transaction environment: \(String(describing: transaction.environment))")
            Self.debugLog(
                "transaction dates purchase=\(transaction.purchaseDate) expiration=\(String(describing: transaction.expirationDate)) revoked=\(String(describing: transaction.revocationDate))"
            )

            if transaction.environment == .xcode {
                Self.debugLog("skipped Xcode StoreKit Testing entitlement \(transaction.productID)")
                continue
            }

            guard isActiveAnglesEntitlement(transaction, now: now) else {
                continue
            }

            hasActive = true
        }
        return hasActive
    }

    /// Ended-membership UI hint only. `Transaction.latest` never reaches the unlock path.
    /// The active group check comes first so an expired Annual cannot beat a live Monthly.
    private func membershipHistoryProbe() async -> MembershipHistoryProbe {
        if await hasActiveAnglesSubscription() {
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
            Self.debugLog(
                "latest transaction \(transaction.productID) environment \(transaction.environment)"
            )
            guard isAppStoreBacked(transaction) else {
                continue
            }
            if isActiveAnglesEntitlement(transaction, now: now) {
                return .active
            }
            candidates.append(endedCandidate(for: transaction))
        }

        for product in products {
            guard Self.productIDs.contains(product.id), let subscription = product.subscription else {
                continue
            }
            for status in await subscriptionStatuses(for: subscription, productID: product.id) {
                guard let transaction = try? verified(status.transaction),
                      Self.productIDs.contains(transaction.productID),
                      isAppStoreBacked(transaction) else {
                    continue
                }
                switch status.state {
                case .subscribed, .inGracePeriod, .inBillingRetryPeriod:
                    return .active
                case .expired, .revoked:
                    candidates.append(endedCandidate(for: transaction))
                default:
                    continue
                }
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
    /// still considers the user entitled. Expired, revoked, or Xcode Testing receipts are skipped.
    private func isActiveAnglesEntitlement(_ transaction: Transaction, now: Date) -> Bool {
        guard isAppStoreBacked(transaction) else {
            return false
        }
        guard Self.productIDs.contains(transaction.productID) else {
            return false
        }
        guard transaction.revocationDate == nil else {
            return false
        }
        if let expirationDate = transaction.expirationDate, expirationDate <= now {
            return false
        }
        return true
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
