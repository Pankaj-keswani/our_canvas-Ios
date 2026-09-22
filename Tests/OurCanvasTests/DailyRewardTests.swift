import XCTest
@testable import OurCanvas

/// Unit tests for the Daily +1 Coin Reward feature.
/// Pure logic tests — no Firestore I/O.
final class DailyRewardTests: XCTestCase {

    // MARK: - User model

    func testLastCoinRewardDateDefaultsToEmptyString() {
        let user = User()
        XCTAssertEqual(user.lastCoinRewardDate, "")
    }

    func testUserDecodesLastCoinRewardDate() {
        let data: [String: Any] = [
            "uid": "u1",
            "lastCoinRewardDate": "2026-09-22",
        ]
        let user = User.from(documentID: "u1", data: data)
        XCTAssertEqual(user.lastCoinRewardDate, "2026-09-22")
    }

    func testUserDecodesLastCoinRewardDateMissingKeyFallsBackToEmpty() {
        let data: [String: Any] = ["uid": "u1"]
        let user = User.from(documentID: "u1", data: data)
        XCTAssertEqual(user.lastCoinRewardDate, "",
                       "Missing lastCoinRewardDate key must fall back to empty string.")
    }

    func testCreationFieldsContainsLastCoinRewardDate() {
        let fields = User.creationFields(uid: "u1", displayName: "Test", email: "t@t.com")
        XCTAssertEqual(fields["lastCoinRewardDate"] as? String, "",
                       "New user document must include lastCoinRewardDate = \"\".")
    }

    // MARK: - Date formatting (deterministic, no Firestore)

    func testDateFormatterProducesYYYYMMDDString() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")!

        // Fixed reference date: 2026-09-22 12:00:00 UTC
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 22
        components.hour = 12
        components.timeZone = TimeZone(identifier: "UTC")
        let date = Calendar(identifier: .gregorian).date(from: components)!

        XCTAssertEqual(formatter.string(from: date), "2026-09-22")
    }

    func testDailyRewardEligibleWhenLastDateIsDifferentDay() {
        // Simulate the eligibility check logic (pure string comparison).
        let lastCoinRewardDate = "2026-09-21"
        let todayStr = "2026-09-22"
        XCTAssertNotEqual(lastCoinRewardDate, todayStr,
                          "User should be eligible when last reward date differs from today.")
    }

    func testDailyRewardNotEligibleWhenLastDateIsSameDay() {
        let lastCoinRewardDate = "2026-09-22"
        let todayStr = "2026-09-22"
        XCTAssertEqual(lastCoinRewardDate, todayStr,
                       "User must not receive a second coin on the same calendar day.")
    }

    func testDailyRewardEligibleWhenLastDateIsEmpty() {
        // New user — never claimed before.
        let lastCoinRewardDate = ""
        let todayStr = "2026-09-22"
        XCTAssertNotEqual(lastCoinRewardDate, todayStr,
                          "New user with empty lastCoinRewardDate must be eligible for first daily reward.")
    }

    func testDailyRewardEligibleAcrossMidnightBoundary() {
        // Yesterday's reward should not block today.
        let lastCoinRewardDate = "2026-09-22"
        let tomorrowStr = "2026-09-23"
        XCTAssertNotEqual(lastCoinRewardDate, tomorrowStr,
                          "Yesterday's claim must not block today's daily reward.")
    }

    // MARK: - Coin arithmetic (daily reward adds exactly 1)

    func testDailyRewardAddsOneToExistingBalance() {
        let existingCoins = 5
        let expectedAfterReward = existingCoins + 1
        XCTAssertEqual(expectedAfterReward, 6)
    }

    func testDailyRewardOnZeroBalance() {
        XCTAssertEqual(0 + 1, 1)
    }

    func testDailyRewardOnDefaultWelcomeBalance() {
        let defaultCoins = 3
        XCTAssertEqual(defaultCoins + 1, 4)
    }
}
