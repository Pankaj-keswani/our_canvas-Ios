import Foundation
import FirebaseFirestore
import FirebaseAuth

/// Manages coins economy calculations and atomic Firestore wallet mutations.
final class CoinManager {
    static let shared = CoinManager()

    private let db = Firestore.firestore()

    // MARK: - Economy Calculations

    /// Progressive hint cost: 1st hint = 1 coin, 2nd = 2 coins, 3rd = 3 coins, etc.
    static func calculateHintCost(hintsRevealedCount: Int) -> Int {
        max(1, hintsRevealedCount + 1)
    }

    /// Tiered streak recovery cost based on streak length.
    static func calculateStreakRecoveryCost(streakLength: Int) -> Int {
        switch streakLength {
        case ...10:
            return 3
        case 11...20:
            return 5
        case 21...50:
            return 8
        case 51...100:
            return 12
        default:
            return 20
        }
    }

    // MARK: - Wallet Transactions

    /// Atomically deducts `amount` coins if balance is sufficient.
    @discardableResult
    func spendCoins(uid: String, amount: Int) async throws -> Bool {
        try await UserRepository.shared.deductCoins(uid: uid, amount: amount)
    }

    /// Atomically credits `amount` coins to user's wallet.
    func earnCoins(uid: String, amount: Int) async throws {
        try await UserRepository.shared.addCoins(uid: uid, amount: amount)
    }
}
