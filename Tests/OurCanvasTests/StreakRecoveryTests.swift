import XCTest
import Foundation
@testable import OurCanvas

final class StreakRecoveryTests: XCTestCase {

    // MARK: - CoinManager Tests

    func testCalculateHintCost() {
        XCTAssertEqual(CoinManager.calculateHintCost(hintsRevealedCount: 0), 1)
        XCTAssertEqual(CoinManager.calculateHintCost(hintsRevealedCount: 1), 2)
        XCTAssertEqual(CoinManager.calculateHintCost(hintsRevealedCount: 2), 3)
        XCTAssertEqual(CoinManager.calculateHintCost(hintsRevealedCount: 5), 6)
    }

    func testCalculateStreakRecoveryCostTiers() {
        // 1...10 -> 3
        XCTAssertEqual(CoinManager.calculateStreakRecoveryCost(streakLength: 1), 3)
        XCTAssertEqual(CoinManager.calculateStreakRecoveryCost(streakLength: 5), 3)
        XCTAssertEqual(CoinManager.calculateStreakRecoveryCost(streakLength: 10), 3)

        // 11...20 -> 5
        XCTAssertEqual(CoinManager.calculateStreakRecoveryCost(streakLength: 11), 5)
        XCTAssertEqual(CoinManager.calculateStreakRecoveryCost(streakLength: 15), 5)
        XCTAssertEqual(CoinManager.calculateStreakRecoveryCost(streakLength: 20), 5)

        // 21...50 -> 8
        XCTAssertEqual(CoinManager.calculateStreakRecoveryCost(streakLength: 21), 8)
        XCTAssertEqual(CoinManager.calculateStreakRecoveryCost(streakLength: 35), 8)
        XCTAssertEqual(CoinManager.calculateStreakRecoveryCost(streakLength: 50), 8)

        // 51...100 -> 12
        XCTAssertEqual(CoinManager.calculateStreakRecoveryCost(streakLength: 51), 12)
        XCTAssertEqual(CoinManager.calculateStreakRecoveryCost(streakLength: 75), 12)
        XCTAssertEqual(CoinManager.calculateStreakRecoveryCost(streakLength: 100), 12)

        // 101+ -> 20
        XCTAssertEqual(CoinManager.calculateStreakRecoveryCost(streakLength: 101), 20)
        XCTAssertEqual(CoinManager.calculateStreakRecoveryCost(streakLength: 500), 20)

        // <= 0 fallback -> 3
        XCTAssertEqual(CoinManager.calculateStreakRecoveryCost(streakLength: 0), 3)
        XCTAssertEqual(CoinManager.calculateStreakRecoveryCost(streakLength: -5), 3)
    }

    // MARK: - StreakManager calculateStreaks with recoveredDates

    func testCalculateStreaksWithRecoveredDates() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current

        let today = Date()
        let calendar = Calendar.current
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today),
              let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: today) else {
            XCTFail("Date calculation failed")
            return
        }

        let todayStr = formatter.string(from: today)
        let yesterdayStr = formatter.string(from: yesterday)
        let twoDaysAgoStr = formatter.string(from: twoDaysAgo)
        let threeDaysAgoStr = formatter.string(from: threeDaysAgo)

        // User drew 3 days ago, 2 days ago, and today. Missed yesterday.
        let drawingDates = [threeDaysAgoStr, twoDaysAgoStr, todayStr]

        // Without recovery: streak is 1 (only today).
        let withoutRecovery = StreakManager.calculateStreaks(drawingDates: drawingDates, recoveredDates: [], now: today)
        XCTAssertEqual(withoutRecovery.currentStreak, 1)

        // With yesterday recovered: streak is 4 (3 days ago + 2 days ago + recovered yesterday + today).
        let withRecovery = StreakManager.calculateStreaks(drawingDates: drawingDates, recoveredDates: [yesterdayStr], now: today)
        XCTAssertEqual(withRecovery.currentStreak, 4)
        XCTAssertEqual(withRecovery.longestStreak, 4)
    }

    // MARK: - Streak Recovery Eligibility Info

    func testRecoveryEligibilityCase1_DrewTodayAfterBrokenStreakYesterday() {
        let calendar = Calendar.current
        let today = Date()
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else {
            XCTFail("Date calculation failed")
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current

        let todayStr = formatter.string(from: today)
        let yesterdayStr = formatter.string(from: yesterday)

        var user = User()
        user.uid = "u1"
        user.currentStreak = 1
        user.lastActiveDate = todayStr
        user.previousBrokenStreak = 15
        user.streakBrokenDate = yesterdayStr
        user.recoveredDates = []

        let info = StreakManager.getStreakRecoveryInfo(user: user, now: today)
        XCTAssertTrue(info.isEligible)
        XCTAssertEqual(info.brokenStreak, 15)
        XCTAssertEqual(info.missedDate, yesterdayStr)
        XCTAssertEqual(info.costCoins, 5, "15-day streak costs 5 coins")
    }

    func testRecoveryEligibilityCase2_MissedYesterdayActiveTwoDaysAgo() {
        let calendar = Calendar.current
        let today = Date()
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today) else {
            XCTFail("Date calculation failed")
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current

        let yesterdayStr = formatter.string(from: yesterday)
        let twoDaysAgoStr = formatter.string(from: twoDaysAgo)

        var user = User()
        user.uid = "u1"
        user.currentStreak = 7
        user.lastActiveDate = twoDaysAgoStr
        user.previousBrokenStreak = 0
        user.streakBrokenDate = ""
        user.recoveredDates = []

        let info = StreakManager.getStreakRecoveryInfo(user: user, now: today)
        XCTAssertTrue(info.isEligible)
        XCTAssertEqual(info.brokenStreak, 7)
        XCTAssertEqual(info.missedDate, yesterdayStr)
        XCTAssertEqual(info.costCoins, 3, "7-day streak costs 3 coins")
    }

    func testRecoveryIneligible_AlreadyRecovered() {
        let calendar = Calendar.current
        let today = Date()
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else {
            XCTFail("Date calculation failed")
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current

        let yesterdayStr = formatter.string(from: yesterday)

        var user = User()
        user.uid = "u1"
        user.currentStreak = 1
        user.previousBrokenStreak = 10
        user.streakBrokenDate = yesterdayStr
        user.recoveredDates = [yesterdayStr]

        let info = StreakManager.getStreakRecoveryInfo(user: user, now: today)
        XCTAssertFalse(info.isEligible)
    }

    func testRecoveryIneligible_ActiveYesterday() {
        let calendar = Calendar.current
        let today = Date()
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else {
            XCTFail("Date calculation failed")
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current

        let yesterdayStr = formatter.string(from: yesterday)

        var user = User()
        user.uid = "u1"
        user.currentStreak = 10
        user.lastActiveDate = yesterdayStr
        user.previousBrokenStreak = 0
        user.streakBrokenDate = ""
        user.recoveredDates = []

        let info = StreakManager.getStreakRecoveryInfo(user: user, now: today)
        XCTAssertFalse(info.isEligible)
    }

    func testRecoveryIneligible_NoPriorStreak() {
        let calendar = Calendar.current
        let today = Date()
        guard let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today) else {
            XCTFail("Date calculation failed")
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current

        let twoDaysAgoStr = formatter.string(from: twoDaysAgo)

        var user = User()
        user.uid = "u1"
        user.currentStreak = 0
        user.lastActiveDate = twoDaysAgoStr
        user.previousBrokenStreak = 0
        user.streakBrokenDate = ""
        user.recoveredDates = []

        let info = StreakManager.getStreakRecoveryInfo(user: user, now: today)
        XCTAssertFalse(info.isEligible)
    }
}
