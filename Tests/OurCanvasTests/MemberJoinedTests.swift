import XCTest
import Foundation
@testable import OurCanvas

// MARK: - MEMBER-JOINED NOTIFICATIONS (circle join fan-out)

@MainActor
final class MemberJoinedTests: XCTestCase {
    func testParsesMemberJoinedPayloadWithDefaults() {
        let payload = PushPayload.parse(["type": "member_joined", "groupId": "g1"])!
        XCTAssertEqual(payload.type, .memberJoined)
        XCTAssertEqual(payload.senderName, "Someone", "missing joiner name defaults")
        XCTAssertEqual(payload.groupName, "your circle", "missing circle name defaults")
    }

    func testParsesFullMemberJoinedPayload() {
        let payload = PushPayload.parse([
            "type": "member_joined",
            "groupId": "g1",
            "groupName": "Besties",
            "senderId": "u9",
            "senderName": "Riya",
            "joinedAt": "1700000000000",
            "eventId": "member_joined:g1:u9:1700000000000",
        ])!
        XCTAssertEqual(payload.type, .memberJoined)
        XCTAssertEqual(payload.senderName, "Riya")
        XCTAssertEqual(payload.groupName, "Besties")
        XCTAssertEqual(payload.eventId, "member_joined:g1:u9:1700000000000")
    }

    func testUsesExactRequestedCopy() {
        let payload = PushPayload.parse([
            "type": "member_joined",
            "groupId": "g1",
            "groupName": "Doodle Squad",
            "senderName": "Riya",
        ])!
        let notification = payload.toInAppNotification(recipientId: "me")
        XCTAssertEqual(notification.type, .memberJoined)
        XCTAssertEqual(notification.body, "Riya has joined your circle Doodle Squad",
                       "exact requested copy: %user% has joined your circle %Circle name%")
        XCTAssertEqual(notification.title, "👋 Riya joined Doodle Squad")
        XCTAssertEqual(notification.type.emoji, "👋")
        XCTAssertEqual(notification.recipientId, "me")
    }

    func testStableEventIdDedupesWhileRejoinStaysDistinct() {
        let base: [AnyHashable: Any] = [
            "type": "member_joined",
            "groupId": "g1",
            "groupName": "Besties",
            "senderId": "u9",
            "senderName": "Riya",
        ]

        let first = PushPayload.parse(base.merging(["eventId": "member_joined:g1:u9:111"]) { _, new in new })!
        XCTAssertEqual(first.toInAppNotification(recipientId: "me").notificationId,
                       "member_joined:g1:u9:111")

        // Same event re-delivered → same id → receiver-side dedupe collapses it.
        let repeatDelivery = PushPayload.parse(base.merging(["eventId": "member_joined:g1:u9:111"]) { _, new in new })!
        XCTAssertEqual(first.toInAppNotification(recipientId: "me").notificationId,
                       repeatDelivery.toInAppNotification(recipientId: "me").notificationId)

        // Leave + rejoin later → new event id → a distinct notification.
        let second = PushPayload.parse(base.merging(["eventId": "member_joined:g1:u9:222"]) { _, new in new })!
        XCTAssertNotEqual(first.toInAppNotification(recipientId: "me").notificationId,
                          second.toInAppNotification(recipientId: "me").notificationId)

        // Missing eventId falls back to a stable sender-keyed id.
        let fallback = PushPayload.parse(base)!
        XCTAssertEqual(fallback.toInAppNotification(recipientId: "me").notificationId,
                       "member_joined:Riya")
    }

    func testDecodesMemberJoinedNotificationDocument() {
        let data: [String: Any] = [
            "notificationId": "member_joined:g1:u9:111",
            "type": "MEMBER_JOINED",
            "title": "👋 Riya joined Besties",
            "body": "Riya has joined your circle Besties",
            "read": false,
            "senderId": "u9",
            "senderName": "Riya",
            "groupId": "g1",
            "groupName": "Besties",
            "targetId": "g1",
        ]
        let notification = InAppNotification.from(documentID: "member_joined:g1:u9:111", data: data)
        XCTAssertEqual(notification.type, .memberJoined)
        XCTAssertEqual(notification.body, "Riya has joined your circle Besties")
    }

    func testTapRoutesToCircleFeed() throws {
        let payload = PushPayload.parse([
            "type": "member_joined",
            "groupId": "g7",
            "groupName": "Besties",
            "senderName": "Riya",
            "eventId": "member_joined:g7:u9:111",
        ])!

        // Push tap URL routes through the shared parser.
        let url = try XCTUnwrap(payload.deepLinkURL())
        XCTAssertEqual(AppRoute(url: url), .drawingFeed(groupId: "g7", groupName: "Besties"))

        // Hub row routing maps the persisted notification to the same destination.
        let notification = payload.toInAppNotification(recipientId: "me")
        let router = AppRouter(authProvider: MockAuthNoUser(), profileProvider: MockProfileNil())
        router.openDeepLink(notification: notification)
        XCTAssertEqual(router.pendingRoute, .drawingFeed(groupId: "g7", groupName: "Besties"))
    }
}

// Minimal router mocks (avoid touching Firebase in unit tests).
private final class MockAuthNoUser: AuthSessionProviding {
    var activeUser: AuthUserSnapshot? { nil }
    func addStateObserver(_ handler: @escaping (AuthUserSnapshot?) -> Void) -> () -> Void {
        handler(nil)
        return {}
    }
    func signOut() throws {}
}

private final class MockProfileNil: UserProfileProviding {
    func fetchOrCreateProfile(uid: String,
                              fallbackDisplayName: String?,
                              fallbackEmail: String?) async throws -> User? { nil }
    func updateFields(uid: String, _ fields: [String: Any]) async throws {}
}
