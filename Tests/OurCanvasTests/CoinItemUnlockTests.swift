import XCTest
@testable import OurCanvas

/// Unit tests for Coin-Unlocked Brushes & Backgrounds (Tier-1: Fire/Midnight Rose, Tier-2: Aurora/Aurora Borealis).
/// These are pure value-level / serialization / rendering tests — no Firestore I/O.
final class CoinItemUnlockTests: XCTestCase {

    // MARK: - BrushType Android ID parity

    func testFireBrushAndroidID() {
        XCTAssertEqual(BrushType.fire.androidID, 14,
                       "Fire brush must map to Android ordinal 14 (cross-platform wire format).")
    }

    func testAuroraBrushAndroidID() {
        XCTAssertEqual(BrushType.aurora.androidID, 15,
                       "Aurora brush must map to Android ordinal 15 (cross-platform wire format).")
    }

    func testFireBrushFromAndroidID() {
        XCTAssertEqual(BrushType.from(androidID: 14), .fire)
    }

    func testAuroraBrushFromAndroidID() {
        XCTAssertEqual(BrushType.from(androidID: 15), .aurora)
    }

    // MARK: - Coin costs

    func testFireCoinCost() {
        XCTAssertEqual(BrushType.fire.coinCost, 10)
    }

    func testAuroraCoinCost() {
        XCTAssertEqual(BrushType.aurora.coinCost, 20)
    }

    func testFireIsCoinUnlockable() {
        XCTAssertTrue(BrushType.fire.isCoinUnlockable)
    }

    func testAuroraIsCoinUnlockable() {
        XCTAssertTrue(BrushType.aurora.isCoinUnlockable)
    }

    func testBasicBrushIsNotCoinUnlockable() {
        XCTAssertFalse(BrushType.basic.isCoinUnlockable)
    }

    // MARK: - Coin unlock IDs

    func testFireCoinUnlockId() {
        XCTAssertEqual(BrushType.fire.coinUnlockId, "FIRE")
    }

    func testAuroraCoinUnlockId() {
        XCTAssertEqual(BrushType.aurora.coinUnlockId, "AURORA")
    }

    // MARK: - Background template coin metadata

    func testMidnightRoseCoinCost() {
        XCTAssertEqual(DrawingBackground.Template.midnightRose.coinCost, 10)
    }

    func testAuroraBorealisCoinCost() {
        XCTAssertEqual(DrawingBackground.Template.auroraBorealis.coinCost, 20)
    }

    func testMidnightRoseUnlockId() {
        XCTAssertEqual(DrawingBackground.Template.midnightRose.coinUnlockId, "MIDNIGHT_ROSE")
    }

    func testAuroraBorealisUnlockId() {
        XCTAssertEqual(DrawingBackground.Template.auroraBorealis.coinUnlockId, "AURORA_BOREALIS")
    }

    func testMidnightRoseIsCoinUnlockable() {
        XCTAssertTrue(DrawingBackground.Template.midnightRose.isCoinUnlockable)
    }

    func testAuroraBorealisIsCoinUnlockable() {
        XCTAssertTrue(DrawingBackground.Template.auroraBorealis.isCoinUnlockable)
    }

    func testPlainBackgroundIsNotCoinUnlockable() {
        XCTAssertFalse(DrawingBackground.Template.plain.isCoinUnlockable)
    }

    // MARK: - User.isBrushUnlocked

    func testFireBrushLockedWhenUnlockedBrushesEmpty() {
        var user = User()
        user.unlockedBrushes = []
        XCTAssertFalse(user.isBrushUnlocked(.fire))
    }

    func testFireBrushUnlockedWhenContainsFIRE() {
        var user = User()
        user.unlockedBrushes = ["FIRE"]
        XCTAssertTrue(user.isBrushUnlocked(.fire))
    }

    func testFireBrushUnlockedCaseInsensitive() {
        var user = User()
        user.unlockedBrushes = ["fire"]
        XCTAssertTrue(user.isBrushUnlocked(.fire),
                      "isBrushUnlocked must be case-insensitive to handle Android-written entries.")
    }

    func testAuroraBrushLockedByDefault() {
        var user = User()
        user.unlockedBrushes = []
        XCTAssertFalse(user.isBrushUnlocked(.aurora))
    }

    func testAuroraBrushUnlockedWhenContainsAURORA() {
        var user = User()
        user.unlockedBrushes = ["AURORA"]
        XCTAssertTrue(user.isBrushUnlocked(.aurora))
    }

    func testNonCoinBrushAlwaysUnlocked() {
        var user = User()
        user.unlockedBrushes = []
        // basic, pencil, marker are not coin-unlockable — should always return true
        XCTAssertTrue(user.isBrushUnlocked(.basic))
        XCTAssertTrue(user.isBrushUnlocked(.pencil))
        XCTAssertTrue(user.isBrushUnlocked(.marker))
    }

    // MARK: - User.isBackgroundUnlocked

    func testMidnightRoseLockedWhenUnlockedBackgroundsEmpty() {
        var user = User()
        user.unlockedBackgrounds = []
        XCTAssertFalse(user.isBackgroundUnlocked(.midnightRose))
    }

    func testMidnightRoseUnlockedWhenContainsMIDNIGHT_ROSE() {
        var user = User()
        user.unlockedBackgrounds = ["MIDNIGHT_ROSE"]
        XCTAssertTrue(user.isBackgroundUnlocked(.midnightRose))
    }

    func testAuroraBorealisLockedByDefault() {
        var user = User()
        user.unlockedBackgrounds = []
        XCTAssertFalse(user.isBackgroundUnlocked(.auroraBorealis))
    }

    func testAuroraBorealisUnlockedWhenContainsKey() {
        var user = User()
        user.unlockedBackgrounds = ["AURORA_BOREALIS"]
        XCTAssertTrue(user.isBackgroundUnlocked(.auroraBorealis))
    }

    func testNonCoinBackgroundAlwaysUnlocked() {
        var user = User()
        user.unlockedBackgrounds = []
        XCTAssertTrue(user.isBackgroundUnlocked(.plain))
        XCTAssertTrue(user.isBackgroundUnlocked(.dots))
        XCTAssertTrue(user.isBackgroundUnlocked(.grid))
        XCTAssertTrue(user.isBackgroundUnlocked(.gradient))
    }

    // MARK: - StrokeSerializer round-trip for coin backgrounds

    func testMidnightRoseTemplateRawValue() {
        XCTAssertEqual(DrawingBackground.Template.midnightRose.rawValue, "midnight_rose")
    }

    func testAuroraBorealisTemplateRawValue() {
        XCTAssertEqual(DrawingBackground.Template.auroraBorealis.rawValue, "aurora_borealis")
    }

    func testStrokeSerializerRoundTripMidnightRose() {
        let bg = DrawingBackground(template: .midnightRose, colorHex: "#FFFFFF")
        let json = StrokeSerializer.encode(strokes: [], background: bg, canvasSize: CGSize(width: 1080, height: 1080))
        let decoded = StrokeSerializer.decode(json)
        XCTAssertEqual(decoded.background.template, .midnightRose,
                       "midnight_rose template must survive a StrokeSerializer encode → decode round-trip.")
    }

    func testStrokeSerializerRoundTripAuroraBorealis() {
        let bg = DrawingBackground(template: .auroraBorealis, colorHex: "#FFFFFF")
        let json = StrokeSerializer.encode(strokes: [], background: bg, canvasSize: CGSize(width: 1080, height: 1080))
        let decoded = StrokeSerializer.decode(json)
        XCTAssertEqual(decoded.background.template, .auroraBorealis,
                       "aurora_borealis template must survive a StrokeSerializer encode → decode round-trip.")
    }

    // MARK: - StrokeRenderer does not crash for fire/aurora brushes

    func testFireBrushRenderDoesNotCrash() {
        let stroke = Stroke(
            points: [CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 200)],
            color: 0xFFFF4400,
            width: 20,
            brush: .fire
        )
        let canvasSize = CGSize(width: 1080, height: 1080)
        let result = StrokeRenderer.renderInkImage(strokes: [stroke], canvasSize: canvasSize, outputPixels: 256)
        XCTAssertNotNil(result, "Fire brush render must produce a non-nil image.")
    }

    func testAuroraBrushRenderDoesNotCrash() {
        let stroke = Stroke(
            points: [CGPoint(x: 100, y: 100), CGPoint(x: 500, y: 300), CGPoint(x: 900, y: 500)],
            color: 0xFF00FFA3,
            width: 25,
            brush: .aurora
        )
        let canvasSize = CGSize(width: 1080, height: 1080)
        let result = StrokeRenderer.renderInkImage(strokes: [stroke], canvasSize: canvasSize, outputPixels: 256)
        XCTAssertNotNil(result, "Aurora brush render must produce a non-nil image.")
    }

    func testMidnightRoseBackgroundRenderDoesNotCrash() {
        let bg = DrawingBackground(template: .midnightRose, colorHex: "#FFFFFF")
        let result = StrokeRenderer.renderBackgroundImage(bg, canvasSize: CGSize(width: 1080, height: 1080), outputPixels: 256)
        XCTAssertNotNil(result, "Midnight Rose background must produce a non-nil image.")
    }

    func testAuroraBorealisBackgroundRenderDoesNotCrash() {
        let bg = DrawingBackground(template: .auroraBorealis, colorHex: "#FFFFFF")
        let result = StrokeRenderer.renderBackgroundImage(bg, canvasSize: CGSize(width: 1080, height: 1080), outputPixels: 256)
        XCTAssertNotNil(result, "Aurora Borealis background must produce a non-nil image.")
    }

    // MARK: - CoinManager cost constants

    func testBrushTier1Cost() {
        XCTAssertEqual(CoinManager.BRUSH_TIER_1_COST, 10)
    }

    func testBrushTier2Cost() {
        XCTAssertEqual(CoinManager.BRUSH_TIER_2_COST, 20)
    }

    func testBackgroundTier1Cost() {
        XCTAssertEqual(CoinManager.BACKGROUND_TIER_1_COST, 10)
    }

    func testBackgroundTier2Cost() {
        XCTAssertEqual(CoinManager.BACKGROUND_TIER_2_COST, 20)
    }

    // MARK: - BrushType display names

    func testFireDisplayName() {
        XCTAssertEqual(BrushType.fire.displayName, "Fire 🔥")
    }

    func testAuroraDisplayName() {
        XCTAssertEqual(BrushType.aurora.displayName, "Aurora 🌌")
    }

    func testVelvetRibbonDisplayName() {
        XCTAssertEqual(BrushType.velvetRibbon.displayName, "Velvet Ribbon 🎀")
    }

    func testFireEngineDisplayName() {
        XCTAssertEqual(BrushType.fireEngine.displayName, "Fire Engine 🚒")
    }

    // MARK: - Velvet Ribbon & Fire Engine Parity

    func testVelvetRibbonBrushAndroidID() {
        XCTAssertEqual(BrushType.velvetRibbon.androidID, 17)
        XCTAssertEqual(BrushType.from(androidID: 17), .velvetRibbon)
    }

    func testFireEngineBrushAndroidID() {
        XCTAssertEqual(BrushType.fireEngine.androidID, 18)
        XCTAssertEqual(BrushType.from(androidID: 18), .fireEngine)
    }

    func testVelvetRibbonCoinCostAndUnlockId() {
        XCTAssertEqual(BrushType.velvetRibbon.coinCost, 10)
        XCTAssertEqual(BrushType.velvetRibbon.coinUnlockId, "brush_velvet_ribbon")
        XCTAssertTrue(BrushType.velvetRibbon.isCoinUnlockable)
    }

    func testFireEngineCoinCostAndUnlockId() {
        XCTAssertEqual(BrushType.fireEngine.coinCost, 15)
        XCTAssertEqual(BrushType.fireEngine.coinUnlockId, "brush_fire_engine")
        XCTAssertTrue(BrushType.fireEngine.isCoinUnlockable)
    }

    // MARK: - Midnight Galaxy & Vintage Parchment Parity

    func testMidnightGalaxyBackgroundMetadata() {
        let template = DrawingBackground.Template.midnightGalaxy
        XCTAssertEqual(template.displayName, "Midnight Galaxy 🌌")
        XCTAssertEqual(template.coinCost, 10)
        XCTAssertEqual(template.coinUnlockId, "bg_midnight_galaxy")
        XCTAssertTrue(template.isCoinUnlockable)
    }

    func testParchmentBackgroundMetadata() {
        let template = DrawingBackground.Template.parchment
        XCTAssertEqual(template.displayName, "Vintage Parchment 📜")
        XCTAssertEqual(template.coinCost, 15)
        XCTAssertEqual(template.coinUnlockId, "bg_parchment")
        XCTAssertTrue(template.isCoinUnlockable)
    }

    // MARK: - Rendering Tests for New Items

    func testVelvetRibbonRenderDoesNotCrash() {
        let stroke = Stroke(
            points: [CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 200), CGPoint(x: 500, y: 300)],
            color: 0xFFC026D3,
            width: 20,
            brush: .velvetRibbon
        )
        let result = StrokeRenderer.renderInkImage(strokes: [stroke], canvasSize: CGSize(width: 1080, height: 1080), outputPixels: 256)
        XCTAssertNotNil(result)
    }

    func testFireEngineRenderDoesNotCrash() {
        let stroke = Stroke(
            points: [CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 200), CGPoint(x: 500, y: 300)],
            color: 0xFFEF4444,
            width: 20,
            brush: .fireEngine
        )
        let result = StrokeRenderer.renderInkImage(strokes: [stroke], canvasSize: CGSize(width: 1080, height: 1080), outputPixels: 256)
        XCTAssertNotNil(result)
    }

    func testMidnightGalaxyBackgroundRenderDoesNotCrash() {
        let bg = DrawingBackground(template: .midnightGalaxy, colorHex: "#000000")
        let result = StrokeRenderer.renderBackgroundImage(bg, canvasSize: CGSize(width: 1080, height: 1080), outputPixels: 256)
        XCTAssertNotNil(result)
    }

    func testParchmentBackgroundRenderDoesNotCrash() {
        let bg = DrawingBackground(template: .parchment, colorHex: "#F5EBE0")
        let result = StrokeRenderer.renderBackgroundImage(bg, canvasSize: CGSize(width: 1080, height: 1080), outputPixels: 256)
        XCTAssertNotNil(result)
    }

    // MARK: - User Model Item Unlock & Pro Tests

    func testUserIsItemUnlockedViaUnlockedItems() {
        var user = User()
        user.unlockedItems = ["brush_velvet_ribbon", "bg_midnight_galaxy"]
        XCTAssertTrue(user.isItemUnlocked("brush_velvet_ribbon"))
        XCTAssertTrue(user.isItemUnlocked("bg_midnight_galaxy"))
        XCTAssertTrue(user.isBrushUnlocked(.velvetRibbon))
        XCTAssertTrue(user.isBackgroundUnlocked(.midnightGalaxy))
        XCTAssertFalse(user.isBrushUnlocked(.fireEngine))
        XCTAssertFalse(user.isBackgroundUnlocked(.parchment))
    }

    func testUserProUnlocksAllItems() {
        var user = User()
        user.plan = "pro"
        XCTAssertTrue(user.isPro)
        XCTAssertTrue(user.isItemUnlocked("brush_velvet_ribbon"))
        XCTAssertTrue(user.isItemUnlocked("brush_fire_engine"))
        XCTAssertTrue(user.isItemUnlocked("bg_midnight_galaxy"))
        XCTAssertTrue(user.isItemUnlocked("bg_parchment"))
        XCTAssertTrue(user.isBrushUnlocked(.velvetRibbon))
        XCTAssertTrue(user.isBrushUnlocked(.fireEngine))
        XCTAssertTrue(user.isBackgroundUnlocked(.midnightGalaxy))
        XCTAssertTrue(user.isBackgroundUnlocked(.parchment))
    }

    func testUserDecodesUnlockedItemsAndLastLoginDate() {
        let data: [String: Any] = [
            "uid": "test_uid",
            "unlockedItems": ["brush_velvet_ribbon"],
            "lastLoginDate": "2026-09-23",
        ]
        let user = User.from(documentID: "test_uid", data: data)
        XCTAssertEqual(user.unlockedItems, ["brush_velvet_ribbon"])
        XCTAssertEqual(user.lastLoginDate, "2026-09-23")
    }

    func testUserFieldUpdates() {
        let itemUpdate = UserFieldUpdate.unlockedItems(["item1"])
        XCTAssertEqual(itemUpdate["unlockedItems"] as? [String], ["item1"])

        let loginDateUpdate = UserFieldUpdate.lastLoginDate("2026-09-23")
        XCTAssertEqual(loginDateUpdate["lastLoginDate"] as? String, "2026-09-23")
    }
}
