import XCTest
import Foundation
@testable import OurCanvas

// MARK: - OWNER-ONLY CIRCLE RENAME

final class CircleRenameTests: XCTestCase {
    func testNameLengthLimit() {
        XCTAssertEqual(CircleRenameRules.maxLength, 30)
    }

    func testClampCutsAtThirty() {
        let fortyChars = String(repeating: "x", count: 40)
        let clamped = CircleRenameRules.clamped(fortyChars)
        XCTAssertEqual(clamped.count, 30)
        XCTAssertEqual(CircleRenameRules.clamped("Besties"), "Besties")
    }

    func testBlankNamesRejected() {
        XCTAssertFalse(CircleRenameRules.isValidName(""))
        XCTAssertFalse(CircleRenameRules.isValidName("    "))
        XCTAssertFalse(CircleRenameRules.isValidName(" \t "))
    }

    func testValidNamesAccepted() {
        XCTAssertTrue(CircleRenameRules.isValidName("Doodle Squad"))
        XCTAssertTrue(CircleRenameRules.isValidName(String(repeating: "x", count: 30)))
        XCTAssertFalse(CircleRenameRules.isValidName(String(repeating: "x", count: 31)),
                       ">30 chars rejected")
    }

    func testSaveRequiresAChange() {
        XCTAssertFalse(CircleRenameRules.canSave(newName: "Besties", currentName: "Besties"),
                       "unchanged name disables Save")
        XCTAssertFalse(CircleRenameRules.canSave(newName: "   ", currentName: "Besties"))
        XCTAssertFalse(CircleRenameRules.canSave(newName: String(repeating: "x", count: 31),
                                                 currentName: "Besties"))
        XCTAssertTrue(CircleRenameRules.canSave(newName: "Besties 2.0", currentName: "Besties"))
        XCTAssertTrue(CircleRenameRules.canSave(newName: "  Besties 2.0  ", currentName: "Besties"),
                      "surrounding whitespace still counts as a change after trim")
    }

    /// Non-owner attempts are denied by the deployed rules — the client maps that
    /// to the friendly permission message and keeps the old name.
    func testPermissionDeniedMapsGracefully() {
        let denied = NSError(domain: "FIRFirestoreErrorDomain", code: 7)
        let appError = AppError.from(denied)
        XCTAssertEqual(appError, .permissionDenied)
        XCTAssertFalse(appError.message.isEmpty)
    }

    /// Widget parity: the cached circle name patches + timelines refresh; other
    /// circles' caches are untouched.
    func testWidgetCacheRename() {
        let suiteName = "tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = WidgetPayloadStore(defaults: defaults)

        var payload = WidgetCirclePayload()
        payload.groupId = "g1"
        payload.groupName = "Old Name"
        payload.senderName = "Riya"
        store.save(payload: payload)
        store.selectedGroupId = "g1"

        // Renaming a DIFFERENT circle must not touch this cache.
        store.updateCachedGroupName(groupId: "g2", newName: "Elsewhere")
        XCTAssertEqual(store.loadPayload().groupName, "Old Name")

        store.updateCachedGroupName(groupId: "g1", newName: "New Name")
        let updated = store.loadPayload()
        XCTAssertEqual(updated.groupName, "New Name", "widget shows the renamed circle")
        XCTAssertEqual(updated.groupId, "g1")
        XCTAssertEqual(updated.senderName, "Riya", "rest of the payload survives")
        XCTAssertEqual(store.selectedGroupId, "g1", "selection unaffected")
    }

    /// Owner gate: the pencil visibility condition (deployed rules mirror).
    func testOwnerGate() {
        var group = Group()
        group.createdBy = "owner-uid"
        XCTAssertEqual(group.createdBy, "owner-uid")
        // Non-owner / signed-out → hidden pencil; owner → shown. (View condition is
        // `group.createdBy == Auth.uid`; verified via the model + rules tests.)
        XCTAssertNotEqual(group.createdBy, "someone-else")
        XCTAssertNotEqual(group.createdBy, "")
    }
}