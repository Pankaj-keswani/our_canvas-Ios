import XCTest
import Foundation
@testable import OurCanvas

final class DoodleTipAndStreakWarningTests: XCTestCase {

    // MARK: - Doodle Tip Push Notifications

    func testParseCoinTipPayload() {
        let userInfo: [AnyHashable: Any] = [
            "type": "coin_tip",
            "amount": "1",
            "senderId": "sender_123",
            "senderName": "Alice",
            "drawingId": "draw_789",
            "groupId": "grp_456",
            "groupName": "Family Circle"
        ]

        let payload = PushPayload.parse(userInfo)
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.type, .coinTip)
        XCTAssertEqual(payload?.amount, "1")
        XCTAssertEqual(payload?.senderId, "sender_123")
        XCTAssertEqual(payload?.senderName, "Alice")
        XCTAssertEqual(payload?.drawingId, "draw_789")
        XCTAssertEqual(payload?.groupId, "grp_456")
        XCTAssertEqual(payload?.groupName, "Family Circle")
    }

    func testToInAppNotificationForCoinTipSingleCoin() {
        let payload = PushPayload(
            type: .coinTip,
            senderName: "Bob",
            senderId: "bob_uid",
            groupId: "grp_1",
            groupName: "Art Club",
            drawingId: "draw_99",
            amount: "1"
        )

        let notification = payload.toInAppNotification(recipientId: "my_uid")
        XCTAssertEqual(notification.type, .coinTip)
        XCTAssertEqual(notification.recipientId, "my_uid")
        XCTAssertEqual(notification.senderId, "bob_uid")
        XCTAssertEqual(notification.senderName, "Bob")
        XCTAssertEqual(notification.groupId, "grp_1")
        XCTAssertEqual(notification.groupName, "Art Club")
        XCTAssertEqual(notification.drawingId, "draw_99")
        XCTAssertEqual(notification.notificationId, "tip:draw_99:bob_uid")
        XCTAssertEqual(notification.title, "🎁 Gift from Bob")
        XCTAssertEqual(notification.body, "Bob tipped you 1 Coin 🪙 for your doodle!")
        XCTAssertEqual(notification.type.emoji, "🎁")
    }

    func testToInAppNotificationForCoinTipMultipleCoins() {
        let payload = PushPayload(
            type: .coinTip,
            senderName: "Charlie",
            senderId: "charlie_uid",
            groupId: "grp_2",
            groupName: "Doodlers",
            drawingId: "draw_100",
            amount: "5"
        )

        let notification = payload.toInAppNotification(recipientId: "my_uid")
        XCTAssertEqual(notification.title, "🎁 Gift from Charlie")
        XCTAssertEqual(notification.body, "Charlie tipped you 5 Coins 🪙 for your doodle!")
    }

    func testToInAppNotificationCustomTitleAndBody() {
        var payload = PushPayload(
            type: .coinTip,
            senderName: "Dave",
            senderId: "dave_uid",
            groupId: "grp_3",
            drawingId: "draw_101",
            amount: "2"
        )
        payload.title = "Custom Tip Title"
        payload.body = "Custom Tip Message"

        let notification = payload.toInAppNotification(recipientId: "my_uid")
        XCTAssertEqual(notification.title, "Custom Tip Title")
        XCTAssertEqual(notification.body, "Custom Tip Message")
    }

    func testCoinTipDeepLinkURL() {
        let payload = PushPayload(
            type: .coinTip,
            senderName: "Eve",
            senderId: "eve_uid",
            groupId: "grp_xyz",
            groupName: "Sketchers",
            drawingId: "draw_456",
            amount: "1"
        )

        guard let url = payload.deepLinkURL() else {
            XCTFail("deepLinkURL should not be nil")
            return
        }

        XCTAssertEqual(url.scheme, "ourcanvas")
        XCTAssertEqual(url.host, "feed")

        let route = AppRoute(url: url)
        XCTAssertEqual(route, .drawing(groupId: "grp_xyz", drawingId: "draw_456", groupName: "Sketchers"))
    }

    // MARK: - Streak Warning Eligibility

    func testStreakWarningEligibility() {
        let today = "2026-09-23"
        let yesterday = "2026-09-22"

        // Unauthenticated
        XCTAssertFalse(StreakWarningEligibility.isEligible(
            isAuthenticated: false,
            isNotifyOtherEnabled: true,
            currentStreak: 5,
            lastActiveDate: yesterday,
            lastDrawingSentDate: nil,
            todayDateString: today
        ))

        // notify_other disabled
        XCTAssertFalse(StreakWarningEligibility.isEligible(
            isAuthenticated: true,
            isNotifyOtherEnabled: false,
            currentStreak: 5,
            lastActiveDate: yesterday,
            lastDrawingSentDate: nil,
            todayDateString: today
        ))

        // Streak < 2
        XCTAssertFalse(StreakWarningEligibility.isEligible(
            isAuthenticated: true,
            isNotifyOtherEnabled: true,
            currentStreak: 0,
            lastActiveDate: yesterday,
            lastDrawingSentDate: nil,
            todayDateString: today
        ))
        XCTAssertFalse(StreakWarningEligibility.isEligible(
            isAuthenticated: true,
            isNotifyOtherEnabled: true,
            currentStreak: 1,
            lastActiveDate: yesterday,
            lastDrawingSentDate: nil,
            todayDateString: today
        ))

        // Streak >= 2 and already active/drew today via lastActiveDate
        XCTAssertFalse(StreakWarningEligibility.isEligible(
            isAuthenticated: true,
            isNotifyOtherEnabled: true,
            currentStreak: 3,
            lastActiveDate: today,
            lastDrawingSentDate: nil,
            todayDateString: today
        ))

        // Streak >= 2 and already drew today via lastDrawingSentDate
        XCTAssertFalse(StreakWarningEligibility.isEligible(
            isAuthenticated: true,
            isNotifyOtherEnabled: true,
            currentStreak: 3,
            lastActiveDate: yesterday,
            lastDrawingSentDate: today,
            todayDateString: today
        ))

        // Eligible: Authenticated, notify_other enabled, streak >= 2, no drawing today
        XCTAssertTrue(StreakWarningEligibility.isEligible(
            isAuthenticated: true,
            isNotifyOtherEnabled: true,
            currentStreak: 2,
            lastActiveDate: yesterday,
            lastDrawingSentDate: yesterday,
            todayDateString: today
        ))
        XCTAssertTrue(StreakWarningEligibility.isEligible(
            isAuthenticated: true,
            isNotifyOtherEnabled: true,
            currentStreak: 10,
            lastActiveDate: "2026-09-21",
            lastDrawingSentDate: nil,
            todayDateString: today
        ))
    }

    // MARK: - Streak Warning Notification Content and Trigger

    func testStreakWarningNotificationContent() {
        let content = StreakWarningManager.buildNotificationContent(currentStreak: 5)
        XCTAssertEqual(content.title, "🔥 Streak Expiring Soon!")
        XCTAssertEqual(content.body, "Your 5-day streak will break in 60 minutes! Send a doodle to keep the flame alive 🔥")
        XCTAssertEqual(content.userInfo["type"] as? String, "streak_expiration_warning")
    }

    func testStreakWarningTrigger() {
        let trigger = StreakWarningManager.buildTrigger()
        XCTAssertTrue(trigger.repeats)
        XCTAssertEqual(trigger.dateComponents.hour, 23)
        XCTAssertEqual(trigger.dateComponents.minute, 0)
    }

    func testOnDrawingSentRecordsDateInDefaults() {
        let suiteName = "tests.streak.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let manager = StreakWarningManager(defaults: defaults)
        let uid = "test_user_streak"

        let testDate = Date(timeIntervalSince1970: 1774310400) // Fixed timestamp
        let timeZone = TimeZone(identifier: "UTC")!
        manager.onDrawingSent(uid: uid, date: testDate, timeZone: timeZone)

        let key = StreakWarningManager.lastDrawingSentDateKey(for: uid)
        let recordedDate = defaults.string(forKey: key)
        let expectedDate = StreakWarningManager.dayFormatter(timeZone: timeZone).string(from: testDate)

        XCTAssertEqual(recordedDate, expectedDate)
    }
}
