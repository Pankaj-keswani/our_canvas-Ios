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

    // MARK: - Coin Constants
    static let BRUSH_TIER_1_COST = 10
    static let BRUSH_TIER_2_COST = 20
    static let BACKGROUND_TIER_1_COST = 10
    static let BACKGROUND_TIER_2_COST = 20

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

    // MARK: - Coin Unlocking

    /// Atomically unlocks a brush using coins.
    @discardableResult
    func unlockBrush(userId: String, brushName: String, cost: Int) async throws -> Int {
        let userRef = db.collection("users").document(userId)
        let newCoins = try await db.runTransaction { (transaction, errorPointer) -> Any? in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(userRef)
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return nil
            }

            let data = snapshot.data() ?? [:]
            let currentCoins = FieldCast.int(data["coins"]) ?? 3
            var unlocked = FieldCast.stringArray(data["unlockedBrushes"]) ?? []

            // If already unlocked, no need to deduct coins
            if unlocked.contains(where: { $0.caseInsensitiveCompare(brushName) == .orderedSame }) {
                return currentCoins
            }

            guard currentCoins >= cost else {
                let error = NSError(domain: "OurCanvas",
                                    code: 402,
                                    userInfo: [NSLocalizedDescriptionKey: "Insufficient coins. You need \(cost) coins to unlock this brush."])
                errorPointer?.pointee = error
                return nil
            }

            let balance = currentCoins - cost
            unlocked.append(brushName)

            transaction.updateData([
                "coins": balance,
                "unlockedBrushes": unlocked,
            ], forDocument: userRef)

            return balance
        }

        guard let finalBalance = newCoins as? Int else {
            throw AppError.underlying("Insufficient coins to unlock \(brushName).")
        }

        _ = try? await UserRepository.shared.getUser(uid: userId, ignoreCache: true)
        return finalBalance
    }

    /// Atomically unlocks a background template using coins.
    @discardableResult
    func unlockBackground(userId: String, templateName: String, cost: Int) async throws -> Int {
        let userRef = db.collection("users").document(userId)
        let newCoins = try await db.runTransaction { (transaction, errorPointer) -> Any? in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(userRef)
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return nil
            }

            let data = snapshot.data() ?? [:]
            let currentCoins = FieldCast.int(data["coins"]) ?? 3
            var unlocked = FieldCast.stringArray(data["unlockedBackgrounds"]) ?? []

            // If already unlocked, no need to deduct coins
            if unlocked.contains(where: { $0.caseInsensitiveCompare(templateName) == .orderedSame }) {
                return currentCoins
            }

            guard currentCoins >= cost else {
                let error = NSError(domain: "OurCanvas",
                                    code: 402,
                                    userInfo: [NSLocalizedDescriptionKey: "Insufficient coins. You need \(cost) coins to unlock this background."])
                errorPointer?.pointee = error
                return nil
            }

            let balance = currentCoins - cost
            unlocked.append(templateName)

            transaction.updateData([
                "coins": balance,
                "unlockedBackgrounds": unlocked,
            ], forDocument: userRef)

            return balance
        }

        guard let finalBalance = newCoins as? Int else {
            throw AppError.underlying("Insufficient coins to unlock \(templateName).")
        }

        _ = try? await UserRepository.shared.getUser(uid: userId, ignoreCache: true)
        return finalBalance
    }

    // MARK: - Daily Coin Reward

    /// Awards +1 coin on first app open of each calendar day.
    /// Atomic Firestore transaction — idempotent: calling twice on the same day returns `false`.
    ///
    /// - Parameters:
    ///   - userId: The authenticated user's UID.
    ///   - timeZone: The time zone used for date formatting (defaults to device's current zone).
    ///   - referenceDate: The date to evaluate against (defaults to `Date()` — injectable for tests).
    /// - Returns: `true` if a coin was awarded, `false` if already claimed today.
    @discardableResult
    func claimDailyCoinIfEligible(userId: String,
                                  timeZone: TimeZone = .current,
                                  referenceDate: Date = Date()) async throws -> Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = timeZone
        let todayStr = formatter.string(from: referenceDate)

        let userRef = db.collection("users").document(userId)
        let awarded = try await db.runTransaction { (transaction, errorPointer) -> Any? in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(userRef)
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return false
            }

            let data = snapshot.data() ?? [:]
            let lastDate = FieldCast.string(data["lastCoinRewardDate"]) ?? ""

            // Already claimed today — skip.
            if lastDate == todayStr { return false }

            let currentCoins = FieldCast.int(data["coins"]) ?? 3
            transaction.updateData([
                "coins": currentCoins + 1,
                "lastCoinRewardDate": todayStr,
            ], forDocument: userRef)
            return true
        } as? Bool ?? false

        if awarded {
            // Refresh local cache so coin balance updates immediately.
            _ = try? await UserRepository.shared.getUser(uid: userId, ignoreCache: true)
        }
        return awarded
    }
}
