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

    private(set) var products: [Product] = []
    private(set) var subscriptionStatus: AnglesSubscriptionStatus
    private(set) var hasUnlockedFullApp: Bool {
        didSet {
            UserDefaults.standard.set(hasUnlockedFullApp, forKey: Self.unlockDefaultsKey)
        }
    }
    private(set) var isLoadingProducts = false
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    private(set) var errorMessage: String?

    private var transactionListener: Task<Void, Never>?

    init() {
        let cachedUnlock = UserDefaults.standard.bool(forKey: Self.unlockDefaultsKey)
        hasUnlockedFullApp = cachedUnlock
        subscriptionStatus = cachedUnlock ? .subscribed : .inactive
        transactionListener = listenForTransactions()
    }

    var annualProduct: Product? {
        products.first { $0.id == Self.annualProductID }
    }

    var monthlyProduct: Product? {
        products.first { $0.id == Self.monthlyProductID }
    }

    var isBusy: Bool {
        isPurchasing || isRestoring
    }

    func prepare() async {
        async let products: Void = loadProducts()
        async let entitlements: Void = refreshEntitlements()
        _ = await (products, entitlements)
    }

    func loadProducts() async {
        guard !isLoadingProducts else {
            return
        }

        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let fetched = try await Product.products(for: Self.productIDs)
            products = fetched.sorted { lhs, rhs in
                productOrder(lhs.id) < productOrder(rhs.id)
            }
            if fetched.count != Self.productIDs.count {
                errorMessage = "Subscriptions are temporarily unavailable."
            } else {
                errorMessage = nil
            }
        } catch {
            errorMessage = "Subscriptions are temporarily unavailable."
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

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verified(verification)
                await transaction.finish()
                await refreshEntitlements()
                return hasUnlockedFullApp
            case .pending:
                errorMessage = "Your purchase is pending approval."
                return false
            case .userCancelled:
                return false
            @unknown default:
                errorMessage = "The purchase could not be completed."
                return false
            }
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

        if products.first(where: { $0.id == productID }) == nil {
            await loadProducts()
        }
        guard let product = products.first(where: { $0.id == productID }) else {
            errorMessage = "Subscriptions are unavailable. Run this Debug build from Xcode with Angles.storekit selected."
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
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !hasUnlockedFullApp {
                errorMessage = "No active Angles subscription was found."
            }
            return hasUnlockedFullApp
        } catch {
            errorMessage = "Purchases could not be restored. Try again."
            return false
        }
    }

    func refreshEntitlements() async {
        var hasActiveSubscription = false
        let now = Date()

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  Self.productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil,
                  transaction.expirationDate.map({ $0 > now }) ?? true
            else {
                continue
            }

            hasActiveSubscription = true
        }

        hasUnlockedFullApp = hasActiveSubscription
        subscriptionStatus = hasActiveSubscription ? .subscribed : .inactive
    }

    /// Keeps the StoreKit transaction intact; the next launch or StoreKit event verifies it again.
    func resetForOnboardingTest() {
        errorMessage = nil
        subscriptionStatus = .inactive
        hasUnlockedFullApp = false
    }

    func clearError() {
        errorMessage = nil
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled else {
                    return
                }
                guard case .verified(let transaction) = result else {
                    continue
                }
                await transaction.finish()
                await self?.refreshEntitlements()
            }
        }
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
}

private enum StoreKitVerificationError: Error {
    case failed
}
