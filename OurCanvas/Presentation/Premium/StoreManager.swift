import Foundation
import StoreKit
import FirebaseFirestore
import FirebaseAuth

@MainActor
class StoreManager: ObservableObject {
    @Published var isPro: Bool = false
    @Published var products: [Product] = []
    
    private var updateListenerTask: Task<Void, Never>? = nil
    private let productId = "prempatra_lifetime_pro"
    
    init() {
        updateListenerTask = listenForTransactions()
        Task {
            await requestProducts()
            await updateCustomerProductStatus()
        }
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    func requestProducts() async {
        do {
            products = try await Product.products(for: [productId])
        } catch {
            print("Failed product request from App Store: \(error)")
        }
    }
    
    func purchase() async throws -> Bool {
        guard let product = products.first else { return false }
        
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updateCustomerProductStatus()
            await transaction.finish()
            
            // Sync with Firebase backend
            if let uid = Auth.auth().currentUser?.uid {
                let db = Firestore.firestore()
                try await db.collection("users").document(uid).updateData([
                    "plan": "pro",
                    "premiumSource": "APP_STORE",
                    "premiumExpiry": Timestamp(date: Date(timeIntervalSince1970: 32503680000)), // Year 3000
                    "appStoreTransactionId": String(transaction.id),
                    "lastPremiumUpdate": FieldValue.serverTimestamp()
                ])
            }
            return true
        case .userCancelled, .pending:
            return false
        default:
            return false
        }
    }
    
    private func listenForTransactions() -> Task<Void, Never> {
        return Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try await self.checkVerified(result)
                    await self.updateCustomerProductStatus()
                    await transaction.finish()
                } catch {
                    print("Transaction failed verification")
                }
            }
        }
    }
    
    private func updateCustomerProductStatus() async {
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                if transaction.productID == productId {
                    isPro = true
                }
            } catch {
                print("Failed entitlement verification")
            }
        }
    }
    
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
}

enum StoreError: Error {
    case failedVerification
}
