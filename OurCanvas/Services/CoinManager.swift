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

    // MARK: - Daily Coin Reward (streak-aware)

    /// Result of a daily coin claim attempt.
    struct DailyRewardResult {
        /// `nil` means already claimed today.
        var coinsAwarded: Int?
        /// New streak day (1–7) after this claim. Only valid when `coinsAwarded != nil`.
        var streakDay: Int
        /// `true` when this claim completed a 7-day cycle (+5 coins jackpot).
        var isJackpot: Bool
    }

    /// Awards +1 coin (or +5 on day 7) on the first app open of each calendar day.
    /// Implements a 7-day streak with jackpot — atomic Firestore transaction, idempotent on
    /// same-day calls.
    ///
    /// Streak rules (mirrors Android):
    /// - Same day as `lastCoinRewardDate`: already claimed, return `nil` coins.
    /// - Yesterday == `lastCoinRewardDate`: continue streak (streak + 1).
    /// - Any earlier date (or empty): reset streak to 1.
    /// - Day 1–6: award +1 coin.
    /// - Day 7: award +5 coins (jackpot), then reset streak to 0 so next day starts at 1.
    @discardableResult
    func claimDailyCoinIfEligible(userId: String,
                                  timeZone: TimeZone = .current,
                                  referenceDate: Date = Date()) async throws -> DailyRewardResult {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = timeZone
        let todayStr = formatter.string(from: referenceDate)

        // Compute yesterday string for streak continuity check.
        let cal = Calendar(identifier: .gregorian)
        let yesterdayDate = cal.date(byAdding: .day, value: -1, to: referenceDate) ?? referenceDate
        let yesterdayStr = formatter.string(from: yesterdayDate)

        let userRef = db.collection("users").document(userId)

        struct TxResult {
            var coinsAwarded: Int?
            var streakDay: Int
            var isJackpot: Bool
        }

        let txResult: TxResult = try await withCheckedThrowingContinuation { continuation in
            db.runTransaction({ (transaction, errorPointer) -> Any? in
                let snapshot: DocumentSnapshot
                do {
                    snapshot = try transaction.getDocument(userRef)
                } catch let e as NSError {
                    errorPointer?.pointee = e
                    return nil
                }

                let data = snapshot.data() ?? [:]
                let lastDate = FieldCast.string(data["lastCoinRewardDate"]) ?? ""

                // Already claimed today.
                if lastDate == todayStr {
                    return TxResult(coinsAwarded: nil, streakDay: FieldCast.int(data["coinLoginStreak"]) ?? 0, isJackpot: false)
                }

                let currentStreak = FieldCast.int(data["coinLoginStreak"]) ?? 0
                let currentCoins  = FieldCast.int(data["coins"]) ?? 3

                // Determine new streak.
                let newStreak: Int
                if lastDate == yesterdayStr {
                    newStreak = currentStreak + 1      // consecutive day
                } else {
                    newStreak = 1                      // broken or first-ever
                }

                let isJackpot = (newStreak >= 7)
                let coinsAwarded = isJackpot ? 5 : 1
                let finalStreak  = isJackpot ? 0 : newStreak   // reset after jackpot

                transaction.updateData([
                    "coins":              currentCoins + coinsAwarded,
                    "lastCoinRewardDate": todayStr,
                    "coinLoginStreak":    finalStreak,
                ], forDocument: userRef)

                return TxResult(coinsAwarded: coinsAwarded, streakDay: newStreak, isJackpot: isJackpot)
            }) { value, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let r = value as? TxResult {
                    continuation.resume(returning: r)
                } else {
                    // Defensive: treat unknown result as no award.
                    continuation.resume(returning: TxResult(coinsAwarded: nil, streakDay: 0, isJackpot: false))
                }
            }
        }

        if txResult.coinsAwarded != nil {
            _ = try? await UserRepository.shared.getUser(uid: userId, ignoreCache: true)
        }
        return DailyRewardResult(coinsAwarded: txResult.coinsAwarded,
                                 streakDay: txResult.streakDay,
                                 isJackpot: txResult.isJackpot)
    }

    // MARK: - Coin Tipping (Doodle Gifts)

    /// POSTs a `sendCoinTip` action to the Cloudflare Push Relay Worker.
    /// The worker atomically deducts from sender, credits recipient, fires push + in-app notification.
    /// Never write the tip directly with the client SDK — Firestore rules block cross-user writes.
    func sendCoinTip(senderId: String,
                     recipientId: String,
                     amount: Int,
                     drawingId: String,
                     groupId: String,
                     groupName: String,
                     senderName: String) async throws {
        let workerURL = URL(string: "https://ourcanvas-push-relay.ourcanvas-app.workers.dev")!
        let apiKey = "zXeJyuEteKt-ubdpqajiFa4M3m3LZsMLi_sG6_NFrDo"

        let payload: [String: Any] = [
            "action":      "sendCoinTip",
            "senderId":    senderId,
            "recipientId": recipientId,
            "amount":      amount,
            "drawingId":   drawingId,
            "groupId":     groupId,
            "groupName":   groupName,
            "senderName":  senderName,
        ]

        var request = URLRequest(url: workerURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 15

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw AppError.underlying("Tip failed (HTTP \(code)). Please try again.")
        }

        // Refresh sender's coin balance from Firestore after successful tip.
        _ = try? await UserRepository.shared.getUser(uid: senderId, ignoreCache: true)
    }
}
