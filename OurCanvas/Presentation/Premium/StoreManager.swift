import Foundation
import StoreKit
import FirebaseFirestore
import FirebaseAuth

/// StoreKit 2 lifetime-Pro store.
///
/// RULES COMPATIBILITY (documented blocker — see Phase 3 report):
/// Production Firestore rules only permit premium-field updates with
/// `premiumSource` ∈ {CODE, PLAY, WELCOME_PROMO, test-reset}. An Apple purchase
/// is NOT a Play purchase, so this client attempts the honest `APP_STORE` grant;
/// until the backend adds an APP_STORE path (mirroring `isPlayPurchaseUpdate`
/// with a `play_purchases`-style claim doc keyed by the StoreKit transaction id),
/// the Firestore write will be denied by rules. In that case we:
///   - keep the verified StoreKit entitlement locally (purchase is not lost),
///   - surface an honest "pending server activation" state,
///   - DO NOT treat the local entitlement as account-wide Pro (server plan stays
///     authoritative for gating), and
///   - retry the grant on next launch/restore.
@MainActor
final class StoreManager: ObservableObject {
    enum ProductState: Equatable {
        case loading
        case unavailable
        case loaded(price: String)
    }

    enum GrantState: Equatable {
        case idle
        case granted
        case pendingServerActivation   // purchase verified; rules denied the server grant
        case failed(String)
    }

    static let productId = "prempatra_lifetime_pro"

    @Published private(set) var productState: ProductState = .loading
    @Published private(set) var hasLocalEntitlement = false
    @Published private(set) var grantState: GrantState = .idle
    @Published private(set) var isPurchasing = false

    private var updatesTask: Task<Void, Never>?
    private let db = Firestore.firestore()

    init() {
        updatesTask = listenForTransactions()
        Task {
            await loadProducts()
            await refreshEntitlements()
            await attemptPendingGrantIfEntitled()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: - Products

    func loadProducts() async {
        productState = .loading
        do {
            let products = try await Product.products(for: [Self.productId])
            if let product = products.first {
                productState = .loaded(price: product.displayPrice)
            } else {
                productState = .unavailable
            }
        } catch {
            print("StoreKit product load failed: \(error.localizedDescription)")
            productState = .unavailable
        }
    }

    // MARK: - Purchase

    func purchase() async {
        guard case .loaded = productState,
              let product = try? await Product.products(for: [Self.productId]).first else {
            grantState = .failed("Product loading from the App Store. Try again in a moment.")
            return
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try Self.checkVerified(verification)
                await transaction.finish()
                await refreshEntitlements()
                await attemptServerGrant(transaction: transaction)
            case .userCancelled:
                break
            case .pending:
                grantState = .failed("Purchase is pending approval.")
            @unknown default:
                break
            }
        } catch {
            grantState = .failed("Purchase couldn't be completed. Please try again.")
        }
    }

    // MARK: - Restore

    func restore() async {
        await refreshEntitlements()
        await attemptPendingGrantIfEntitled()
        if hasLocalEntitlement {
            grantState = grantState == .granted ? .granted : .pendingServerActivation
        } else {
            grantState = .failed("No previous purchases were found for this Apple ID.")
        }
    }

    // MARK: - Entitlements

    func refreshEntitlements() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            if let transaction = try? Self.checkVerified(result),
               transaction.productID == Self.productId {
                entitled = true
            }
        }
        hasLocalEntitlement = entitled
    }

    private func attemptPendingGrantIfEntitled() async {
        guard hasLocalEntitlement else { return }
        for await result in Transaction.currentEntitlements {
            if let transaction = try? Self.checkVerified(result),
               transaction.productID == Self.productId {
                await attemptServerGrant(transaction: transaction)
                return
            }
        }
    }

    // MARK: - Server grant (1:1 binding; rules-gated)

    /// Writes the shared-schema grant fields with the StoreKit transaction id as the
    /// purchase token. 1:1 binding is enforced by writing the claim doc first and
    /// aborting when the transaction is already bound to a different account.
    private func attemptServerGrant(transaction: Transaction) async {
        guard let uid = Auth.auth().currentUser?.uid else {
            grantState = .failed("You need to be signed in to activate Pro.")
            return
        }

        let token = String(transaction.id)
        let claimRef = db.collection("play_purchases").document(token)

        do {
            // 1:1 binding check (same claim collection the Play path uses).
            let claim = try await claimRef.getDocument()
            if claim.exists, claim.data()?["uid"] as? String != uid {
                grantState = .failed("This purchase is already linked to another account.")
                return
            }
            if !claim.exists {
                // Claim docs are rules-blocked for clients (play_purchases: no access).
                // The write below will surface the real limitation instead of pretending.
                try await claimRef.setData([
                    "uid": uid,
                    "source": "APP_STORE",
                    "productId": transaction.productID,
                    "verifiedAt": FieldValue.serverTimestamp(),
                ])
            }

            try await db.collection("users").document(uid).updateData([
                "plan": "pro",
                "premiumSource": "APP_STORE",
                "premiumExpiry": Self.lifetimeExpiry,
                "playPurchaseToken": token,
                "playProductId": transaction.productID,
                "playOrderId": "",
                "lastPremiumUpdate": FieldValue.serverTimestamp(),
            ])
            grantState = .granted
        } catch {
            // Expected while the backend lacks an APP_STORE path: the user's purchase
            // stays verified on their Apple ID and retries on next launch/restore.
            print("Pro grant denied by backend: \(error.localizedDescription)")
            grantState = .pendingServerActivation
        }
    }

    static let lifetimeExpiry: Timestamp = Timestamp(date: Date(timeIntervalSince1970: 32503680000))

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if let transaction = try? Self.checkVerified(result) {
                    await transaction.finish()
                    await self?.refreshEntitlements()
                }
            }
        }
    }

    private static func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
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
