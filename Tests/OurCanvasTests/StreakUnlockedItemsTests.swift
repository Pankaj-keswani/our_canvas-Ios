import XCTest
import UIKit
@testable import OurCanvas

final class StreakUnlockedItemsTests: XCTestCase {

    // MARK: - 1. Pastel Brush Model & Ordinal Parity

    func testPastelBrushAndroidIDAndDecoding() {
        XCTAssertEqual(BrushType.pastel.androidID, 16)
        XCTAssertEqual(BrushType.from(androidID: 16), .pastel)
    }

    func testPastelBrushMetadata() {
        XCTAssertEqual(BrushType.pastel.displayName, "Pastel 🖍️")
        XCTAssertTrue(BrushType.pastel.isStreakUnlockable)
        XCTAssertEqual(BrushType.pastel.requiredStreak, 3)
        XCTAssertEqual(BrushType.pastel.streakUnlockId, "PASTEL")
        XCTAssertEqual(BrushType.pastel.coinCost, 0)
        XCTAssertFalse(BrushType.pastel.isCoinUnlockable)
    }

    // MARK: - 2. Lavender Mist Background Model Parity

    func testLavenderMistBackgroundMetadata() {
        let template = DrawingBackground.Template.lavenderMist
        XCTAssertEqual(template.rawValue, "lavender_mist")
        XCTAssertEqual(template.displayName, "Lavender Mist 🪻")
        XCTAssertTrue(template.isStreakUnlockable)
        XCTAssertEqual(template.requiredStreak, 3)
        XCTAssertEqual(template.streakUnlockId, "LAVENDER_MIST")
        XCTAssertEqual(template.coinCost, 0)
        XCTAssertFalse(template.isCoinUnlockable)
    }

    // MARK: - 3. Stroke & Template Serialization Parity

    func testPastelBrushStrokeSerializationRoundTrip() {
        let stroke = Stroke(
            points: [CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 200)],
            color: 0xFFFF69B4,
            width: 14.0,
            brush: .pastel
        )
        let bg = DrawingBackground(template: .lavenderMist, colorHex: "#F1EBFD")
        let json = StrokeSerializer.encode(strokes: [stroke], background: bg, canvasSize: CGSize(width: 1080, height: 1080))

        XCTAssertTrue(json.contains("\"b\":16"))
        XCTAssertTrue(json.contains("lavender_mist"))

        let parsed = StrokeSerializer.decode(json)
        XCTAssertEqual(parsed.strokes.count, 1)
        XCTAssertEqual(parsed.strokes[0].brush, .pastel)
        XCTAssertEqual(parsed.background.template, .lavenderMist)
    }

    func testLavenderMistTemplateAliasParsing() {
        let aliases = ["lavender_mist", "lavendermist", "lavender", "LAVENDER_MIST"]
        for alias in aliases {
            let json = """
            {"cw":1080,"ch":1080,"bg":{"t":"\(alias)","c":"#F1EBFD"},"strokes":[]}
            """
            let parsed = StrokeSerializer.decode(json)
            XCTAssertEqual(parsed.background.template, .lavenderMist, "Alias '\(alias)' should decode to .lavenderMist")
        }
    }

    // MARK: - 4. Streak Unlock Eligibility & Permanent Unlock Rules

    func testFreeUserWithZeroStreakIsLocked() {
        var user = User()
        user.plan = "free"
        user.currentStreak = 0
        user.longestStreak = 0
        user.unlockedBrushes = []
        user.unlockedBackgrounds = []

        XCTAssertFalse(user.isBrushUnlocked(.pastel))
        XCTAssertFalse(user.isBackgroundUnlocked(.lavenderMist))
        // Regular brushes remain unlocked
        XCTAssertTrue(user.isBrushUnlocked(.basic))
        XCTAssertTrue(user.isBrushUnlocked(.pencil))
        XCTAssertTrue(user.isBackgroundUnlocked(.plain))
    }

    func testUserWithCurrentStreakOfThreeIsUnlocked() {
        var user = User()
        user.plan = "free"
        user.currentStreak = 3
        user.longestStreak = 3

        XCTAssertTrue(user.isBrushUnlocked(.pastel))
        XCTAssertTrue(user.isBackgroundUnlocked(.lavenderMist))
    }

    func testPermanentUnlockWhenStreakResetsToZero() {
        // User once achieved a 3-day streak (longestStreak = 3), but current streak reset to 0 or 1
        var user = User()
        user.plan = "free"
        user.currentStreak = 0
        user.longestStreak = 3

        XCTAssertTrue(user.isBrushUnlocked(.pastel), "Pastel must stay permanently unlocked even after streak resets")
        XCTAssertTrue(user.isBackgroundUnlocked(.lavenderMist), "Lavender Mist must stay permanently unlocked even after streak resets")

        user.currentStreak = 1
        user.longestStreak = 5
        XCTAssertTrue(user.isBrushUnlocked(.pastel))
        XCTAssertTrue(user.isBackgroundUnlocked(.lavenderMist))
    }

    func testExplicitUnlockedArrayGrantsAccess() {
        var user = User()
        user.plan = "free"
        user.currentStreak = 1
        user.longestStreak = 1
        user.unlockedBrushes = ["PASTEL"]
        user.unlockedBackgrounds = ["LAVENDER_MIST"]

        XCTAssertTrue(user.isBrushUnlocked(.pastel))
        XCTAssertTrue(user.isBackgroundUnlocked(.lavenderMist))
    }

    func testProUserHasAccessRegardlessOfStreak() {
        var user = User()
        user.plan = "pro"
        user.currentStreak = 0
        user.longestStreak = 0

        XCTAssertTrue(user.isBrushUnlocked(.pastel))
        XCTAssertTrue(user.isBackgroundUnlocked(.lavenderMist))
    }

    // MARK: - 5. Rendering Parity

    func testStrokeRendererWithPastelAndLavenderMist() {
        let stroke = Stroke(
            points: [CGPoint(x: 50, y: 50), CGPoint(x: 100, y: 120), CGPoint(x: 150, y: 80)],
            color: 0xFFB39DDB,
            width: 16.0,
            brush: .pastel
        )
        let bg = DrawingBackground(template: .lavenderMist, colorHex: "#F1EBFD")

        let image = StrokeRenderer.renderComposite(
            background: bg,
            strokes: [stroke],
            stickers: [],
            texts: [],
            canvasSize: CGSize(width: 400, height: 400),
            outputPixels: 200
        )

        XCTAssertNotNil(image)
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }
}
