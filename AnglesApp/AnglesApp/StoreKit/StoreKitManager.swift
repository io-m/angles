import Foundation
import Observation
import StoreKit
import UIKit

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
    private static let ignoreEntitlementsKey = "ignoreEntitlementsForQA"
    private static let legacySignedOutKey = "subscriptionSignedOut"

    private(set) var products: [Product] = []
    private(set) var subscriptionStatus: AnglesSubscriptionStatus
    private(set) var entitlementsReady = false
    private(set) var hasUnlockedFullApp: Bool {
        didSet {
            UserDefaults.standard.set(hasUnlockedFullApp, forKey: Self.unlockDefaultsKey)
        }
    }
    private(set) var isLoadingProducts = false
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    private(set) var isOpeningSubscriptions = false
    private(set) var isConfirmingAccess = false
    private(set) var canOfferAppleRenew = false
    private(set) var errorMessage: String?
    private var isProbingSubscription = false

    private var transactionListener: Task<Void, Never>?
    private var unfinishedListener: Task<Void, Never>?

    init() {
        Self.migrateLegacySignOutFlag()
        if UserDefaults.standard.bool(forKey: Self.signedOutSessionKey) {
            hasUnlockedFullApp = false
            subscriptionStatus = .inactive
        } else {
            let cachedUnlock = UserDefaults.standard.bool(forKey: Self.unlockDefaultsKey)
            hasUnlockedFullApp = cachedUnlock
            subscriptionStatus = cachedUnlock ? .subscribed : .inactive
        }
        transactionListener = listenForTransactions()
        unfinishedListener = listenForUnfinishedTransactions()
    }

    var annualProduct: Product? {
        product(for: Self.annualProductID)
    }

    var monthlyProduct: Product? {
        product(for: Self.monthlyProductID)
    }

    var isBusy: Bool {
        isPurchasing || isRestoring || isOpeningSubscriptions || isConfirmingAccess
    }

    var checkoutLockMessage: String {
        if isPurchasing {
            return "Subscribing…"
        }
        if isOpeningSubscriptions {
            return "Opening Apple…"
        }
        return "Checking your subscription…"
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

        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }

        signIn()
        await refreshEntitlements()
        if hasUnlockedFullApp {
            holdCheckoutUntilHome()
            return true
        }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                signIn()
                try await applyVerifiedTransaction(verification, isFreshPurchase: true)
                if hasUnlockedFullApp {
                    holdCheckoutUntilHome()
                }
                return hasUnlockedFullApp
            case .pending:
                errorMessage = "Your purchase is pending approval."
                return false
            case .userCancelled:
                await refreshEntitlements()
                if hasUnlockedFullApp {
                    holdCheckoutUntilHome()
                }
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
        canOfferAppleRenew = false
        defer { isRestoring = false }

        signIn()
        await refreshEntitlements()
        if hasUnlockedFullApp {
            errorMessage = nil
            holdCheckoutUntilHome()
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
            holdCheckoutUntilHome()
            return true
        }
        if let syncError, Self.isNetworkFailure(syncError) {
            errorMessage = Self.restoreNetworkError
            return false
        }

        if await hasEndedAnglesSubscription() {
            presentEndedSubscriptionOffer()
            return false
        }

        canOfferAppleRenew = false
        errorMessage = "No active Angles subscription was found."
        return false
    }

    /// Fast local probe. Reads Apple's status and `currentEntitlements` only — never
    /// `AppStore.sync()`, so it cannot raise a password sheet.
    func probeSubscriptionOffer() async {
        guard !isProbingSubscription, !hasUnlockedFullApp, !canOfferAppleRenew else {
            return
        }

        isProbingSubscription = true
        defer { isProbingSubscription = false }

        // A live subscription is not an ended one. If they are still paid, Restore unlocks them.
        if await hasActiveAnglesSubscription() {
            return
        }
        guard await hasEndedAnglesSubscription() else {
            return
        }
        presentEndedSubscriptionOffer()
    }

    func offerAppleRenew() async {
        guard !isBusy else {
            return
        }

        isOpeningSubscriptions = true

        guard let scene = Self.foregroundWindowScene() else {
            isOpeningSubscriptions = false
            errorMessage = "Open Settings to manage your Apple subscriptions."
            return
        }

        do {
            try await AppStore.showManageSubscriptions(in: scene)
        } catch {
            isOpeningSubscriptions = false
            Self.debugLog("manage subscriptions failed: \(error.localizedDescription)")
            errorMessage = "Couldn't open Apple subscriptions. Tap Subscribe to continue."
            return
        }

        isConfirmingAccess = true
        isOpeningSubscriptions = false
        signIn()

        if await waitForUnlock() {
            errorMessage = nil
            canOfferAppleRenew = false
            return
        }

        isConfirmingAccess = false
        if await hasEndedAnglesSubscription() {
            presentEndedSubscriptionOffer()
        } else {
            errorMessage = "We couldn't confirm a renewal yet. Try Restore purchases or Subscribe."
        }
    }

    func releaseCheckoutLock() {
        isConfirmingAccess = false
        isOpeningSubscriptions = false
        isPurchasing = false
        isRestoring = false
    }

    func refreshEntitlements() async {
        await refreshEntitlements(lockWhenEmpty: true)
    }

    /// Local session only. Does not cancel the Apple subscription.
    func signOut() {
        errorMessage = nil
        canOfferAppleRenew = false
        releaseCheckoutLock()
        UserDefaults.standard.set(true, forKey: Self.signedOutSessionKey)
        subscriptionStatus = .inactive
        hasUnlockedFullApp = false
    }

    func clearError() {
        if canOfferAppleRenew {
            return
        }
        errorMessage = nil
    }

    private var isSignedOut: Bool {
        UserDefaults.standard.bool(forKey: Self.signedOutSessionKey)
    }

    private func signIn() {
        UserDefaults.standard.set(false, forKey: Self.signedOutSessionKey)
    }

    private func presentEndedSubscriptionOffer() {
        canOfferAppleRenew = true
        errorMessage = Self.endedSubscriptionError
    }

    private func holdCheckoutUntilHome() {
        isConfirmingAccess = true
    }

    /// The checkout glass must drop at the deadline no matter what StoreKit is doing, so the
    /// poll runs in its own task and this never awaits a refresh that is already in flight.
    private func waitForUnlock() async -> Bool {
        if hasUnlockedFullApp {
            return true
        }

        let poll = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }
                await self.refreshEntitlements(lockWhenEmpty: false)
                if self.hasUnlockedFullApp {
                    return
                }
                try? await Task.sleep(for: Self.confirmationPoll)
            }
        }
        defer { poll.cancel() }

        let deadline = ContinuousClock.now + Self.confirmationTimeout
        while ContinuousClock.now < deadline {
            if hasUnlockedFullApp {
                return true
            }
            try? await Task.sleep(for: Self.confirmationPoll)
        }

        Self.debugLog("renew confirmation timed out still locked")
        return hasUnlockedFullApp
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
        guard Self.productIDs.contains(transaction.productID) else {
            return false
        }
        guard transaction.revocationDate == nil else {
            return false
        }
        if isFreshPurchase || isActiveAnglesEntitlement(transaction, now: Date()) {
            hasUnlockedFullApp = true
            subscriptionStatus = .subscribed
            Self.debugLog("unlocked from verified transaction \(transaction.productID)")
            return true
        }
        return false
    }

    private func refreshEntitlements(lockWhenEmpty: Bool) async {
        if isSignedOut {
            hasUnlockedFullApp = false
            subscriptionStatus = .inactive
            return
        }

        let hasActiveSubscription = await hasActiveAnglesSubscription()
        if hasActiveSubscription {
            hasUnlockedFullApp = true
            subscriptionStatus = .subscribed
            canOfferAppleRenew = false
            errorMessage = nil
        } else if lockWhenEmpty {
            hasUnlockedFullApp = false
            subscriptionStatus = .inactive
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
                    return true
                default:
                    continue
                }
            }
        }
        return false
    }

    /// Sandbox status reads stall, especially right after Apple's manage-subscriptions sheet.
    /// Bound every one so a launch probe or a renew poll cannot wait on a hung call.
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

            guard isActiveAnglesEntitlement(transaction, now: now) else {
                continue
            }

            hasActive = true
        }
        return hasActive
    }

    /// Ended-subscription detection only. Never call this from the unlock path.
    private func hasEndedLatestTransaction() async -> Bool {
        let now = Date()
        var sawEnded = false
        for productID in Self.productIDs {
            guard let result = await Transaction.latest(for: productID),
                  case .verified(let transaction) = result,
                  Self.productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil else {
                continue
            }
            if isActiveAnglesEntitlement(transaction, now: now) {
                return false
            }
            if let expirationDate = transaction.expirationDate, expirationDate <= now {
                sawEnded = true
            }
        }
        return sawEnded
    }

    private func hasEndedAnglesSubscription() async -> Bool {
        if await hasEndedLatestTransaction() {
            return true
        }

        for product in products {
            guard Self.productIDs.contains(product.id), let subscription = product.subscription else {
                continue
            }
            for status in await subscriptionStatuses(for: subscription, productID: product.id) {
                if status.state == .expired {
                    return true
                }
            }
        }
        return false
    }

    private static func foregroundWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    /// `Transaction.currentEntitlements` already includes grace and billing-retry while Apple
    /// still considers the user entitled. Expired or revoked transactions are skipped.
    private func isActiveAnglesEntitlement(_ transaction: Transaction, now: Date) -> Bool {
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
        if UserDefaults.standard.bool(forKey: ignoreEntitlementsKey)
            || UserDefaults.standard.bool(forKey: legacySignedOutKey) {
            UserDefaults.standard.set(true, forKey: signedOutSessionKey)
        }
        UserDefaults.standard.removeObject(forKey: ignoreEntitlementsKey)
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
    private static let restoreNetworkError = "Need a connection to check your subscription."
    private static let endedSubscriptionError = "We found your previous subscription."
    private static let confirmationTimeout: Duration = .seconds(12)
    private static let confirmationPoll: Duration = .milliseconds(400)
    private static let statusTimeout: Duration = .seconds(6)
}

private enum StoreKitVerificationError: Error {
    case failed
}
