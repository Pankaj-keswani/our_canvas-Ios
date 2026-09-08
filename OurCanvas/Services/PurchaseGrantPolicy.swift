import Foundation

/// Pure decision layer for the Apple-purchase → Firestore-grant flow (Phase 4 §7).
/// The production Firestore rules currently have no APP_STORE path, so the client
/// attempts an honest grant and surfaces `pendingServerActivation` when rules deny
/// it. This policy encodes the account-binding decisions that MUST hold regardless
/// of where the trusted verification finally runs (client now, server later):
///
///   - the transaction claim is keyed by the StoreKit transaction id
///   - a transaction may be bound to exactly ONE account
///   - re-granting to the SAME account is idempotent (restore path)
///   - a transaction claimed by a DIFFERENT account is rejected
enum PurchaseGrantPolicy {
    enum Decision: Equatable {
        /// First claim by this account, or an idempotent re-grant for the same owner.
        case allowed
        /// Claim exists under a different uid — never grant.
        case wrongAccount(ownerUid: String)
        /// Not signed in — cannot bind the purchase.
        case notSignedIn
    }

    static func decide(transactionOwnerUid: String?, currentUid: String?) -> Decision {
        guard let currentUid, !currentUid.isEmpty else {
            return .notSignedIn
        }
        guard let ownerUid = transactionOwnerUid, !ownerUid.isEmpty else {
            return .allowed // unclaimed transaction → first binding
        }
        if ownerUid == currentUid {
            return .allowed // same account → idempotent re-grant (restore/retry)
        }
        return .wrongAccount(ownerUid: ownerUid)
    }

    /// Maps a failed grant write to the honest UI state. A rules denial (no
    /// APP_STORE path server-side yet) must never appear as Pro.
    static func uiStateForDeniedGrant() -> StoreManager.GrantState {
        .pendingServerActivation
    }
}
