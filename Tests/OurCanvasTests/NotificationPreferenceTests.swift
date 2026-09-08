import XCTest
import Foundation
@testable import OurCanvas

// MARK: - NOTIFICATION PREFERENCE CATEGORIES (Settings gates)

final class NotificationPreferenceTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testAllCategoriesDefaultOn() {
        let preferences = NotificationPreferences()
        for pushType in allPushTypes {
            XCTAssertTrue(preferences.isEnabled(for: pushType),
                          "\(pushType.rawValue) must be ON by default")
        }
    }

    func testCategoryMappingCoversEveryPushType() {
        XCTAssertEqual(NotificationPreferences.category(for: .newDrawing), .drawings)
        XCTAssertEqual(NotificationPreferences.category(for: .newReaction), .reactions)
        XCTAssertEqual(NotificationPreferences.category(for: .newGameTurn), .games)
        XCTAssertEqual(NotificationPreferences.category(for: .guessResult), .games)
        XCTAssertEqual(NotificationPreferences.category(for: .memberJoined), .other)
    }

    func testEachToggleMutesOnlyItsCategory() {
        var preferences = NotificationPreferences()

        preferences.newDrawingEnabled = false
        XCTAssertFalse(preferences.isEnabled(for: .newDrawing))
        XCTAssertTrue(preferences.isEnabled(for: .newReaction))
        XCTAssertTrue(preferences.isEnabled(for: .newGameTurn))
        XCTAssertTrue(preferences.isEnabled(for: .guessResult))
        XCTAssertTrue(preferences.isEnabled(for: .memberJoined))

        preferences = NotificationPreferences()
        preferences.newReactionEnabled = false
        XCTAssertFalse(preferences.isEnabled(for: .newReaction))
        XCTAssertTrue(preferences.isEnabled(for: .newDrawing))

        preferences = NotificationPreferences()
        preferences.gameEventsEnabled = false
        XCTAssertFalse(preferences.isEnabled(for: .newGameTurn), "game turn invites are muted")
        XCTAssertFalse(preferences.isEnabled(for: .guessResult), "guess results are muted")
        XCTAssertTrue(preferences.isEnabled(for: .newDrawing))

        preferences = NotificationPreferences()
        preferences.otherEnabled = false
        XCTAssertFalse(preferences.isEnabled(for: .memberJoined), "circle-join notices are muted")
        XCTAssertTrue(preferences.isEnabled(for: .guessResult))
    }

    func testReEnableRestoresDelivery() {
        var preferences = NotificationPreferences()
        preferences.otherEnabled = false
        XCTAssertFalse(preferences.isEnabled(for: .memberJoined))
        preferences.otherEnabled = true
        XCTAssertTrue(preferences.isEnabled(for: .memberJoined),
                      "re-enabling the toggle restores delivery immediately")
    }

    /// Migration: preferences stored by the previous app version (two keys) must
    /// decode cleanly — new categories default ON, previously saved OFF states stick.
    func testLegacyTwoKeyStorageMigrates() throws {
        let legacyJSON = """
        {"newDrawingEnabled":false,"newReactionEnabled":true}
        """
        let decoded = try JSONDecoder().decode(NotificationPreferences.self,
                                               from: Data(legacyJSON.utf8))
        XCTAssertFalse(decoded.newDrawingEnabled, "saved OFF state preserved")
        XCTAssertTrue(decoded.newReactionEnabled)
        XCTAssertTrue(decoded.gameEventsEnabled, "new Guess category defaults ON")
        XCTAssertTrue(decoded.otherEnabled, "new Other category defaults ON")
    }

    func testRoundTripThroughUserScopedStore() {
        let defaults = makeDefaults()
        var store = UserScopedStore(uid: "u1", defaults: defaults)

        var preferences = NotificationPreferences()
        preferences.gameEventsEnabled = false
        preferences.otherEnabled = false
        store.notificationPreferences = preferences

        let reloaded = UserScopedStore(uid: "u1", defaults: defaults).notificationPreferences
        XCTAssertEqual(reloaded, preferences)
        XCTAssertFalse(reloaded.isEnabled(for: .newGameTurn))
        XCTAssertFalse(reloaded.isEnabled(for: .memberJoined))
        XCTAssertTrue(reloaded.isEnabled(for: .newDrawing))
    }

    func testPreferencesAreUserScoped() {
        let defaults = makeDefaults()
        var userA = UserScopedStore(uid: "aaa", defaults: defaults)
        userA.notificationPreferences = NotificationPreferences(newReactionEnabled: false)
        let userB = UserScopedStore(uid: "bbb", defaults: defaults)
        XCTAssertTrue(userB.notificationPreferences.isEnabled(for: .newReaction),
                      "one account's mute never silences another")
    }

    private var allPushTypes: [PushPayload.PushType] {
        [.newDrawing, .newReaction, .newGameTurn, .guessResult, .memberJoined]
    }
}
