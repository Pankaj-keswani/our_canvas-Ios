import XCTest
import UIKit
@testable import OurCanvas

// MARK: - Premium Tab Bar parity (Android `MainActivity.PremiumBottomBar`, 2026-09-24)

final class PremiumTabBarTests: XCTestCase {

    // MARK: Bar geometry

    func testFloatingPillGeometry() {
        XCTAssertEqual(PremiumTabBarLayout.barHeight, 74, "Bar must be a 74pt tall pill.")
        XCTAssertEqual(PremiumTabBarLayout.barCornerRadius, 37, "Corner radius must be half the height (fully-rounded pill).")
        XCTAssertGreaterThan(PremiumTabBarLayout.barHeight, 72, "74pt pill must be taller than the old 72pt Android bar.")
    }

    // MARK: Center Create disc

    func testCreateDiscRaisedAbovePillMidline() {
        XCTAssertEqual(PremiumTabBarLayout.createDiscSize, 58, "Create disc must be 58pt.")
        XCTAssertEqual(PremiumTabBarLayout.createDiscRaise, 16, "Disc must be raised 16pt so its top edge pokes above the pill.")
        // 74pt bar / 2 = 37pt half-height; disc radius 29 + raise 16 = 45 > 37 → pokes above.
        XCTAssertGreaterThan(PremiumTabBarLayout.createDiscRaise + PremiumTabBarLayout.createDiscSize / 2,
                             PremiumTabBarLayout.barHeight / 2,
                             "Disc top edge must clear the pill's top edge.")
        // Bottom edge must stay inside the pill: barHeight - raise - radius >= 0.
        XCTAssertGreaterThanOrEqual(PremiumTabBarLayout.barHeight - PremiumTabBarLayout.createDiscRaise - PremiumTabBarLayout.createDiscSize / 2, 0)
    }

    func testCreateDiscHasDedicatedSlot() {
        XCTAssertEqual(PremiumTabBarLayout.createSlotWidth, 72, "Create disc owns a dedicated 72pt slot.")
        XCTAssertGreaterThan(PremiumTabBarLayout.createSlotWidth, PremiumTabBarLayout.createDiscSize)
    }

    // MARK: Selection capsule highlight

    func testCapsuleHighlightGeometry() {
        XCTAssertEqual(PremiumTabBarLayout.capsuleWidth, 44, "Highlight capsule must be 44pt wide.")
        XCTAssertEqual(PremiumTabBarLayout.capsuleHeight, 32, "Highlight capsule must be 32pt tall.")
        XCTAssertEqual(PremiumTabBarLayout.capsuleCornerRadius, 16, "Highlight capsule radius must be 16pt.")
        XCTAssertEqual(PremiumTabBarLayout.capsuleOpacity, 0.15, accuracy: 0.0001, "Capsule is brand primary at 15% opacity.")
    }

    // MARK: Motion timings

    func testSquashAndStretchPressMotion() {
        XCTAssertEqual(PremiumTabBarLayout.pressSquashX, 0.85, "Touch-down compresses X to 0.85.")
        XCTAssertEqual(PremiumTabBarLayout.pressStretchY, 1.08, accuracy: 0.0001, "Y compensates up to ~1.08.")
        XCTAssertEqual(PremiumTabBarLayout.pressSquashDuration, 0.09, accuracy: 0.0001, "Touch-down ease is 90ms.")
    }

    func testSelectionPopAndEntrance() {
        XCTAssertEqual(PremiumTabBarLayout.selectionPopScale, 1.15, "Selected icon spring-pops to 1.15x.")
        XCTAssertEqual(PremiumTabBarLayout.entranceFromScale, 0.92, "Pill entrance springs from 0.92 to 1.0.")
    }

    // MARK: Breathing halo

    func testHaloPulseEnvelope() {
        XCTAssertEqual(PremiumTabBarLayout.haloAlphaMin, 0.25, accuracy: 0.0001)
        XCTAssertEqual(PremiumTabBarLayout.haloAlphaMax, 0.55, accuracy: 0.0001)
        XCTAssertEqual(PremiumTabBarLayout.haloCycleDuration, 1.4, accuracy: 0.0001, "One ease loop is 1.4s.")
        XCTAssertLessThan(PremiumTabBarLayout.haloAlphaMin, PremiumTabBarLayout.haloAlphaMax)
    }

    func testHaloUsesCoreAnimationNotSwiftUITimers() {
        // 60fps requirement: the halo pulses via CABasicAnimation on the layer, so the
        // view class must own a CAGradientLayer and no Timer-driven machinery.
        let halo = BreathingHaloView(frame: CGRect(x: 0, y: 0, width: 78, height: 78))
        let hasGradientLayer = halo.layer.sublayers?.contains { $0 is CAGradientLayer } ?? false
        XCTAssertTrue(hasGradientLayer, "Halo must render via CAGradientLayer (Core Animation).")
        let gradient = halo.layer.sublayers?.first { $0 is CAGradientLayer } as? CAGradientLayer
        XCTAssertEqual(gradient?.type, .radial, "Halo glow must be radial (brand cyan core fading out).")
        XCTAssertNotNil(gradient?.animation(forKey: "breathingHalo"), "Breathing pulse must be an attached CAAnimation, not a Timer.")
    }

    func testHaloNeverBlocksTouches() {
        let halo = BreathingHaloView(frame: CGRect(x: 0, y: 0, width: 78, height: 78))
        XCTAssertFalse(halo.isUserInteractionEnabled, "Halo must not intercept touches.")
        XCTAssertNil(halo.hitTest(CGPoint(x: 39, y: 39), with: nil),
                     "hitTest must return nil so touches pass through to the Create disc.")
        XCTAssertNil(halo.hitTest(CGPoint(x: 0, y: 0), with: nil))
    }

    // MARK: Tab model invariants

    func testTabModelPreservesDotAndBadgeFields() {
        let dotTab = PremiumTab(id: 2, label: "What's New", icon: "sparkles", showUnreadDot: true)
        XCTAssertTrue(dotTab.showUnreadDot)
        XCTAssertNil(dotTab.badgeCount)

        let badgeTab = PremiumTab(id: 0, label: "Alerts", icon: "bell", badgeCount: 4)
        XCTAssertEqual(badgeTab.badgeCount, 4)
        XCTAssertFalse(badgeTab.showUnreadDot, "Badge and dot are independent signals.")

        // Falls back to the same glyph when no distinct active icon is provided.
        XCTAssertEqual(dotTab.activeIcon, dotTab.icon)
    }

    // MARK: Reserved bottom space (safe-area handling)

    func testReservedChromeHeightCoversPillAndGap() {
        XCTAssertEqual(PremiumTabBarLayout.chromeReservedHeight, 86,
                       "Content must reserve pill (74) + bottom gap (12) so nothing hides behind the bar.")
    }

    // MARK: iPad / large-width handling

    func testPillWidthCapCentersOniPad() {
        // Four tab cells + create slot + outer/inner horizontal padding must fit.
        let minimumContentWidth = PremiumTabBarLayout.capsuleWidth * 4
            + PremiumTabBarLayout.createSlotWidth
            + PremiumTabBarLayout.barHorizontalPadding * 2
            + 12 // inner HStack padding (6pt each side)
        XCTAssertGreaterThan(PremiumTabBarLayout.pillMaxWidth, minimumContentWidth,
                             "Width cap must leave room for all four tab cells + create slot.")
        // Android's bar is a fixed-width card; iOS centers a capped-width pill instead
        // of stretching, so wide layouts never jump or overstretch.
        XCTAssertLessThan(PremiumTabBarLayout.pillMaxWidth, 700)
    }
}
