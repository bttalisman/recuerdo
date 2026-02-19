import SwiftUI
import StoreKit
import Observation

@Observable
class PremiumManager {
    static let shared = PremiumManager()

    private(set) var isPurchased = false
    private(set) var product: Product?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    @ObservationIgnored
    @AppStorage("isPremiumOverride") var devOverride = false

    @ObservationIgnored
    private var updateTask: Task<Void, Never>?

    static let productId = "com.recuerdo.premium"

    var isPremium: Bool { isPurchased || devOverride }
    var displayPrice: String { product?.displayPrice ?? "$24.99" }

    private init() {
        updateTask = Task { [weak self] in
            await self?.listenForTransactions()
        }
        Task { [weak self] in
            await self?.loadProduct()
            await self?.loadPurchaseState()
        }
    }

    deinit {
        updateTask?.cancel()
    }

    // MARK: - Load Product

    func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.productId])
            await MainActor.run {
                self.product = products.first
            }
        } catch {
            print("[Premium] Failed to load product: \(error)")
        }
    }

    // MARK: - Check Existing Purchases

    func loadPurchaseState() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productId,
               transaction.revocationDate == nil {
                await MainActor.run { self.isPurchased = true }
                return
            }
        }
        await MainActor.run { self.isPurchased = false }
    }

    // MARK: - Purchase

    @MainActor
    func purchase() async {
        guard let product else {
            errorMessage = "Product not available. Check your connection."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    isPurchased = true
                } else {
                    errorMessage = "Purchase could not be verified."
                }
            case .userCancelled:
                break
            case .pending:
                errorMessage = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            errorMessage = "Purchase failed: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Restore

    @MainActor
    func restorePurchases() async {
        isLoading = true
        errorMessage = nil

        do {
            try await AppStore.sync()
            await loadPurchaseState()
            if !isPurchased {
                errorMessage = "No previous purchase found."
            }
        } catch {
            errorMessage = "Restore failed: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            if case .verified(let transaction) = result {
                if transaction.productID == Self.productId {
                    let revoked = transaction.revocationDate != nil
                    await MainActor.run {
                        self.isPurchased = !revoked
                    }
                }
                await transaction.finish()
            }
        }
    }
}
