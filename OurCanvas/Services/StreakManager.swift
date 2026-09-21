import Foundation
import UIKit
import FirebaseFirestore
import FirebaseAuth

/// Streak recovery eligibility metadata.
struct StreakRecoveryInfo: Equatable {
    var missedDate: String = ""
    var streakToRecover: Int = 0
    var costCoins: Int = 0
    var isEligible: Bool = false

    var brokenStreak: Int { streakToRecover }
}

/// Service managing streak calculation, eligibility checking, and atomic streak recovery.
final class StreakManager {
    static let shared = StreakManager()

    private let db = Firestore.firestore()

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    // MARK: - Calculation with Recovered Dates

    /// Calculates current streak, longest streak, and last active date from drawing dates (Date) and recovered dates.
    static func calculateStreaks(drawingDates: [Date],
                                 recoveredDates: [String] = [],
                                 now: Date = Date()) -> (currentStreak: Int, longestStreak: Int, lastActiveDate: String) {
        let formatter = dayFormatter
        let stringDates = drawingDates.map { formatter.string(from: $0) }
        return calculateStreaks(drawingDates: stringDates, recoveredDates: recoveredDates, now: now)
    }

    /// Calculates current streak, longest streak, and last active date from drawing date strings (yyyy-MM-dd) and recovered dates.
    static func calculateStreaks(drawingDates: [String],
                                 recoveredDates: [String] = [],
                                 now: Date = Date()) -> (currentStreak: Int, longestStreak: Int, lastActiveDate: String) {
        let formatter = dayFormatter
        var activeDates = Set(drawingDates.filter { !$0.isEmpty })
        for rec in recoveredDates where !rec.isEmpty {
            activeDates.insert(rec)
        }

        guard !activeDates.isEmpty else {
            return (0, 0, "")
        }

        let sortedDates = activeDates.sorted()
        let todayStr = formatter.string(from: now)
        let yesterdayStr = formatter.string(from: now.addingTimeInterval(-86400))

        // Compute longest streak
        var longest = 0
        var currentSequence = 0
        var prevDate: Date? = nil

        for dateStr in sortedDates {
            guard let date = formatter.date(from: dateStr) else { continue }
            if let prev = prevDate {
                let diffDays = Calendar.current.dateComponents([.day], from: prev, to: date).day ?? 0
                if diffDays == 1 {
                    currentSequence += 1
                } else if diffDays > 1 {
                    currentSequence = 1
                }
            } else {
                currentSequence = 1
            }
            longest = max(longest, currentSequence)
            prevDate = date
        }

        // Compute current streak ending at today or yesterday
        var current = 0
        var checkDate = activeDates.contains(todayStr) ? now : (activeDates.contains(yesterdayStr) ? now.addingTimeInterval(-86400) : nil)

        if let start = checkDate {
            var iter = start
            while true {
                let dateStr = formatter.string(from: iter)
                if activeDates.contains(dateStr) {
                    current += 1
                    guard let prevDay = Calendar.current.date(byAdding: .day, value: -1, to: iter) else { break }
                    iter = prevDay
                } else {
                    break
                }
            }
        }

        let lastActive = sortedDates.last ?? ""
        return (current, max(longest, current), lastActive)
    }

    // MARK: - Eligibility Check

    /// Checks if a user has a recoverable missed streak (48-hour grace window).
    static func getStreakRecoveryInfo(user: User, now: Date = Date()) -> StreakRecoveryInfo {
        let formatter = dayFormatter
        let yesterdayStr = formatter.string(from: now.addingTimeInterval(-86400))
        let twoDaysAgoStr = formatter.string(from: now.addingTimeInterval(-172800))

        // Case 1: User already drew today, breaking a previously active streak
        if user.previousBrokenStreak > 0,
           user.streakBrokenDate == yesterdayStr,
           !user.recoveredDates.contains(yesterdayStr) {
            let cost = CoinManager.calculateStreakRecoveryCost(streakLength: user.previousBrokenStreak)
            return StreakRecoveryInfo(missedDate: yesterdayStr,
                                      streakToRecover: user.previousBrokenStreak,
                                      costCoins: cost,
                                      isEligible: true)
        }

        // Case 2: User hasn't drawn today yet and missed drawing yesterday (active 2 days ago)
        if user.lastActiveDate == twoDaysAgoStr,
           user.currentStreak > 0,
           !user.recoveredDates.contains(yesterdayStr) {
            let cost = CoinManager.calculateStreakRecoveryCost(streakLength: user.currentStreak)
            return StreakRecoveryInfo(missedDate: yesterdayStr,
                                      streakToRecover: user.currentStreak,
                                      costCoins: cost,
                                      isEligible: true)
        }

        return StreakRecoveryInfo(missedDate: "", streakToRecover: 0, costCoins: 0, isEligible: false)
    }

    // MARK: - Atomic Recovery Action

    /// Executes atomic streak recovery with coin deduction, streak restoration, and haptics.
    func recoverStreak(uid: String, now: Date = Date()) async throws -> (success: Bool, newStreak: Int) {
        let userRef = db.collection("users").document(uid)
        let formatter = Self.dayFormatter
        let todayStr = formatter.string(from: now)

        let result = try await db.runTransaction { (transaction, errorPointer) -> Any? in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(userRef)
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return nil
            }

            guard let data = snapshot.data() else { return nil }
            let user = User.from(documentID: snapshot.documentID, data: data)
            let info = Self.getStreakRecoveryInfo(user: user, now: now)

            guard info.isEligible, user.coins >= info.costCoins else {
                return nil
            }

            let newCoins = user.coins - info.costCoins
            var newRecovered = user.recoveredDates
            if !newRecovered.contains(info.missedDate) {
                newRecovered.append(info.missedDate)
            }

            let newStreak: Int
            let newLastActiveDate: String

            if user.previousBrokenStreak > 0 {
                newStreak = user.previousBrokenStreak + (user.lastActiveDate == todayStr ? 1 : 0)
                newLastActiveDate = user.lastActiveDate
            } else {
                newStreak = info.streakToRecover
                newLastActiveDate = info.missedDate
            }

            let newLongest = max(user.longestStreak, newStreak)

            let updates: [String: Any] = [
                "coins": newCoins,
                "recoveredDates": newRecovered,
                "currentStreak": newStreak,
                "longestStreak": newLongest,
                "lastActiveDate": newLastActiveDate,
                "previousBrokenStreak": 0,
                "streakBrokenDate": "",
            ]

            transaction.updateData(updates, forDocument: userRef)
            return newStreak
        }

        if let newStreak = result as? Int {
            await MainActor.run {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
            _ = try? await UserRepository.shared.getUser(uid: uid, ignoreCache: true)
            return (true, newStreak)
        }

        return (false, 0)
    }
}
