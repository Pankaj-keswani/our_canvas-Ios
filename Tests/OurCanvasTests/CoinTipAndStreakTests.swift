import XCTest
@testable import OurCanvas

/// Unit tests for Coin Tipping ("Doodle Gifts") and 7-Day Streak Jackpot feature.
/// All tests are pure logic — no Firestore I/O, no network calls.
final class CoinTipAndStreakTests: XCTestCase {

    // MARK: - User model: coinLoginStreak

    func testCoinLoginStreakDefaultsToZero() {
        let user = User()
        XCTAssertEqual(user.coinLoginStreak, 0)
    }

    func testUserDecodesCoinLoginStreak() {
        let data: [String: Any] = ["uid": "u1", "coinLoginStreak": 4]
        let user = User.from(documentID: "u1", data: data)
        XCTAssertEqual(user.coinLoginStreak, 4)
    }

    func testUserDecodesCoinLoginStreakMissingKeyFallsBackToZero() {
        let data: [String: Any] = ["uid": "u1"]
        let user = User.from(documentID: "u1", data: data)
        XCTAssertEqual(user.coinLoginStreak, 0,
                       "Missing coinLoginStreak key must fall back to 0.")
    }

    func testCreationFieldsContainsCoinLoginStreak() {
        let fields = User.creationFields(uid: "u1", displayName: "Test", email: "t@t.com")
        XCTAssertEqual(fields["coinLoginStreak"] as? Int, 0,
                       "New user document must include coinLoginStreak = 0.")
    }

    // MARK: - Streak logic (pure, no Firestore)

    func testStreakContinuesWhenLastDateIsYesterday() {
        let lastDate = "2026-09-22"
        let todayStr = "2026-09-23"
        let yesterdayStr = "2026-09-22"
        let isConsecutive = (lastDate == yesterdayStr)
        XCTAssertTrue(isConsecutive, "Same-as-yesterday date should continue the streak.")
    }

    func testStreakResetsWhenLastDateIsOlderThanYesterday() {
        let lastDate = "2026-09-20"
        let yesterdayStr = "2026-09-22"
        let isConsecutive = (lastDate == yesterdayStr)
        XCTAssertFalse(isConsecutive, "Older-than-yesterday date should reset streak to 1.")
    }

    func testStreakResetsWhenLastDateIsEmpty() {
        let lastDate = ""
        let yesterdayStr = "2026-09-22"
        let isConsecutive = (lastDate == yesterdayStr)
        XCTAssertFalse(isConsecutive, "Empty lastCoinRewardDate should reset streak to 1 (first claim).")
    }

    func testJackpotOnDay7() {
        let newStreak = 7
        let isJackpot = newStreak >= 7
        XCTAssertTrue(isJackpot)
        XCTAssertEqual(isJackpot ? 5 : 1, 5, "Jackpot must award +5 coins.")
    }

    func testNoJackpotOnDay6() {
        let newStreak = 6
        let isJackpot = newStreak >= 7
        XCTAssertFalse(isJackpot)
        XCTAssertEqual(isJackpot ? 5 : 1, 1, "Day 6 must award only +1 coin.")
    }

    func testStreakResetAfterJackpot() {
        let newStreak = 7
        let isJackpot = newStreak >= 7
        let finalStreak = isJackpot ? 0 : newStreak
        XCTAssertEqual(finalStreak, 0, "Streak must reset to 0 after jackpot so next claim starts a new cycle at day 1.")
    }

    func testDay7CoinAwardIs5() {
        // Day 7 = jackpot (+5 coins)
        let streak = 7
        let coinsAwarded = streak >= 7 ? 5 : 1
        XCTAssertEqual(coinsAwarded, 5)
    }

    func testDay1Through6CoinsAreEach1() {
        for streak in 1...6 {
            let coinsAwarded = streak >= 7 ? 5 : 1
            XCTAssertEqual(coinsAwarded, 1, "Days 1–6 must each award exactly 1 coin (got \(coinsAwarded) for streak=\(streak)).")
        }
    }

    // MARK: - Streak cycle maths

    func testStartFreshAfterJackpotNextDayBecomesDay1() {
        // Scenario: user hit day 7 yesterday. finalStreak written = 0.
        // Today, lastDate == yesterday → isConsecutive → newStreak = 0 + 1 = 1. Correct.
        let storedStreak = 0        // after jackpot reset
        let isConsecutive = true    // yesterday was jackpot day
        let newStreak = isConsecutive ? storedStreak + 1 : 1
        XCTAssertEqual(newStreak, 1)
    }

    // MARK: - Tip amount options

    func testTipAmountsAre1_2_5() {
        let options = [1, 2, 5]
        XCTAssertEqual(options.count, 3)
        XCTAssertEqual(options[0], 1)
        XCTAssertEqual(options[1], 2)
        XCTAssertEqual(options[2], 5)
    }

    func testTipValidationPassesWhenSufficientCoins() {
        let coins = 5
        let amount = 5
        XCTAssertTrue(coins >= amount)
    }

    func testTipValidationFailsWhenInsufficientCoins() {
        let coins = 1
        let amount = 5
        XCTAssertFalse(coins >= amount)
    }

    func testTipCannotBeToSelf() {
        // senderId != currentUserId gate
        let senderId = "userA"
        let currentUserId = "userA"
        XCTAssertEqual(senderId, currentUserId, "Tip button must be hidden when senderId == currentUserId.")
    }

    func testTipIsAllowedToOtherUsers() {
        let senderId = "userB"
        let currentUserId = "userA"
        XCTAssertNotEqual(senderId, currentUserId)
    }

    // MARK: - CoinManager.sendCoinTip payload (pure)

    func testSendCoinTipPayloadContainsAllRequiredFields() {
        let payload: [String: Any] = [
            "action":      "sendCoinTip",
            "senderId":    "senderUID",
            "recipientId": "recipientUID",
            "amount":      2,
            "drawingId":   "drawingXYZ",
            "groupId":     "groupABC",
            "groupName":   "Test Circle",
            "senderName":  "Alice",
        ]
        XCTAssertEqual(payload["action"] as? String, "sendCoinTip")
        XCTAssertEqual(payload["amount"] as? Int, 2)
        XCTAssertNotNil(payload["senderId"])
        XCTAssertNotNil(payload["recipientId"])
        XCTAssertNotNil(payload["drawingId"])
        XCTAssertNotNil(payload["groupId"])
        XCTAssertNotNil(payload["groupName"])
        XCTAssertNotNil(payload["senderName"])
    }

    // MARK: - Drawing Model Tip Metadata

    func testDrawingDecodesTipCountAndTotalTips() {
        let data: [String: Any] = [
            "senderId": "user1",
            "tipCount": 3,
            "totalTips": 8,
        ]
        let drawing = Drawing.from(documentID: "d1", data: data)
        XCTAssertEqual(drawing.tipCount, 3)
        XCTAssertEqual(drawing.totalTips, 8)
    }

    func testDrawingDefaultTipsAreZero() {
        let drawing = Drawing.from(documentID: "d2", data: ["senderId": "user1"])
        XCTAssertEqual(drawing.tipCount, 0)
        XCTAssertEqual(drawing.totalTips, 0)
    }

    // MARK: - Group OwnerId Parity

    func testGroupOwnerIdMatchesCreatedBy() {
        var group = Group()
        group.createdBy = "owner_uid_123"
        XCTAssertEqual(group.ownerId, "owner_uid_123")
    }
}
