import XCTest
import Foundation
import FirebaseFirestore
@testable import OurCanvas

final class UserActivityTests: XCTestCase {

    func testIsOnlineThreshold() {
        let now = Date(timeIntervalSince1970: 1774350000)

        // nil -> not online
        XCTAssertFalse(UserActivityFormatter.isOnline(lastActiveAt: nil, now: now))

        // 1 minute ago -> online
        let active1mAgo = now.addingTimeInterval(-60)
        XCTAssertTrue(UserActivityFormatter.isOnline(lastActiveAt: active1mAgo, now: now))

        // 4 minutes 50 seconds ago -> online
        let active290sAgo = now.addingTimeInterval(-290)
        XCTAssertTrue(UserActivityFormatter.isOnline(lastActiveAt: active290sAgo, now: now))

        // 5 minutes 1 second ago -> offline (beyond 300s threshold)
        let active301sAgo = now.addingTimeInterval(-301)
        XCTAssertFalse(UserActivityFormatter.isOnline(lastActiveAt: active301sAgo, now: now))

        // 1 hour ago -> offline
        let active1hAgo = now.addingTimeInterval(-3600)
        XCTAssertFalse(UserActivityFormatter.isOnline(lastActiveAt: active1hAgo, now: now))
    }

    func testUserActivityFormatting() {
        let now = Date(timeIntervalSince1970: 1774350000)
        let enLocale = Locale(identifier: "en_US")

        // nil
        XCTAssertEqual(UserActivityFormatter.format(lastActiveAt: nil, now: now, locale: enLocale), "Offline")

        // Active right now (30s ago)
        let active30sAgo = now.addingTimeInterval(-30)
        XCTAssertEqual(UserActivityFormatter.format(lastActiveAt: active30sAgo, now: now, locale: enLocale), "Active now")

        // Active 4 minutes ago
        let active4mAgo = now.addingTimeInterval(-240)
        XCTAssertEqual(UserActivityFormatter.format(lastActiveAt: active4mAgo, now: now, locale: enLocale), "Active now")

        // Active 12 minutes ago
        let active12mAgo = now.addingTimeInterval(-720)
        XCTAssertEqual(UserActivityFormatter.format(lastActiveAt: active12mAgo, now: now, locale: enLocale), "Active 12m ago")

        // Active 3 hours ago
        let active3hAgo = now.addingTimeInterval(-10800)
        XCTAssertEqual(UserActivityFormatter.format(lastActiveAt: active3hAgo, now: now, locale: enLocale), "Active 3h ago")

        // Active yesterday (30 hours ago)
        let activeYesterday = now.addingTimeInterval(-108000)
        XCTAssertEqual(UserActivityFormatter.format(lastActiveAt: activeYesterday, now: now, locale: enLocale), "Active yesterday")

        // Active 3 days ago (259200s)
        let active3DaysAgo = now.addingTimeInterval(-259200)
        let formattedPast = UserActivityFormatter.format(lastActiveAt: active3DaysAgo, now: now, locale: enLocale)
        XCTAssertTrue(formattedPast.hasPrefix("Active "), "Should start with 'Active '")
        XCTAssertFalse(formattedPast.contains("yesterday"))
        XCTAssertFalse(formattedPast.contains("ago"))
    }

    func testUserDecodingParsesLastActiveAt() {
        let testTimestamp = Timestamp(date: Date(timeIntervalSince1970: 1774351234))
        let data: [String: Any] = [
            "uid": "user_activity_test",
            "displayName": "Tester",
            "lastActiveAt": testTimestamp,
            "lastActiveDate": "2026-09-23"
        ]

        let user = User.from(documentID: "user_activity_test", data: data)
        XCTAssertNotNil(user.lastActiveAt)
        XCTAssertEqual(user.lastActiveAt?.timeIntervalSince1970, 1774351234)
        XCTAssertEqual(user.lastActiveDate, "2026-09-23")
    }

    func testUserDecodingFallbackToLastSeenAt() {
        let testTimestamp = Timestamp(date: Date(timeIntervalSince1970: 1774355555))
        let data: [String: Any] = [
            "uid": "user_activity_fallback",
            "displayName": "Fallback User",
            "lastSeenAt": testTimestamp
        ]

        let user = User.from(documentID: "user_activity_fallback", data: data)
        XCTAssertNotNil(user.lastActiveAt)
        XCTAssertEqual(user.lastActiveAt?.timeIntervalSince1970, 1774355555)
    }

    func testUserFieldUpdateLastActive() {
        let updateWithDay = UserFieldUpdate.lastActive(day: "2026-09-23")
        XCTAssertNotNil(updateWithDay["lastActiveAt"])
        XCTAssertEqual(updateWithDay["lastActiveDate"] as? String, "2026-09-23")

        let updateWithoutDay = UserFieldUpdate.lastActive(day: nil)
        XCTAssertNotNil(updateWithoutDay["lastActiveAt"])
        XCTAssertNil(updateWithoutDay["lastActiveDate"])
    }

    func testCreationFieldsIncludeLastActiveAt() {
        let fields = User.creationFields(uid: "u_new", displayName: "Newbie", email: "new@example.com")
        XCTAssertNotNil(fields["lastActiveAt"])
        XCTAssertEqual(fields["lastActiveDate"] as? String, "")
    }
}
