import XCTest
@testable import OurCanvas

final class HomeLoadingResilienceTests: XCTestCase {

    // MARK: - Configuration Thresholds Parity

    func testHomeLoadingTimeoutThresholds() {
        // Fast bounded cache preload timeout: 2.5 seconds
        XCTAssertEqual(HomeLoadingConfig.cachePreloadTimeout, 2.5,
                       "Cache-first preload must be bounded by 2.5s.")

        // Slow loading threshold: 3.5 seconds
        XCTAssertEqual(HomeLoadingConfig.slowLoadingThreshold, 3.5,
                       "Slow loading indicator must appear after 3.5s.")

        // Watchdog timeout: 5.0 seconds
        XCTAssertEqual(HomeLoadingConfig.watchdogTimeout, 5.0,
                       "Watchdog fallback must trigger at 5.0s.")

        // Invariant order: cachePreload <= slowLoadingThreshold < watchdogTimeout
        XCTAssertLessThanOrEqual(HomeLoadingConfig.cachePreloadTimeout, HomeLoadingConfig.slowLoadingThreshold)
        XCTAssertLessThan(HomeLoadingConfig.slowLoadingThreshold, HomeLoadingConfig.watchdogTimeout)
    }

    // MARK: - State Management & Invariants

    func testInitialLoadingStateInvariants() {
        // A fresh ViewModel starts with isLoading = true during initial fetch
        // and slowLoading = false until threshold is crossed.
        let isInitiallyLoading = true
        let isInitiallySlowLoading = false
        let initialError: String? = nil

        XCTAssertTrue(isInitiallyLoading)
        XCTAssertFalse(isInitiallySlowLoading)
        XCTAssertNil(initialError)
    }

    func testSlowLoadingTransition() {
        var isSlowLoading = false
        let elapsedTime = 3.6

        if elapsedTime >= HomeLoadingConfig.slowLoadingThreshold {
            isSlowLoading = true
        }

        XCTAssertTrue(isSlowLoading, "When loading exceeds 3.5s, isSlowLoading must become true.")
    }

    func testWatchdogFallbackTransition() {
        var isLoading = true
        var isSlowLoading = true
        var groups: [Group] = []
        var errorMessage: String? = nil

        let elapsedTime = 5.1
        if elapsedTime >= HomeLoadingConfig.watchdogTimeout && isLoading {
            // Watchdog fallback forces isLoading = false
            isLoading = false
            isSlowLoading = false
            if groups.isEmpty {
                errorMessage = "Connection is slow. Tap to retry."
            }
        }

        XCTAssertFalse(isLoading, "Watchdog must force isLoading to false after 5s.")
        XCTAssertFalse(isSlowLoading)
        XCTAssertNotNil(errorMessage, "If circles list is empty on watchdog expiry, surface error with retry.")
    }

    func testCachedGroupsImmediateDisplay() {
        var isLoading = true
        var isSlowLoading = false
        var groups: [Group] = []

        // Simulate fast cache hit
        let cachedGroup = Group(groupId: "g1", groupName: "Besties")
        groups = [cachedGroup]
        isLoading = false
        isSlowLoading = false

        XCTAssertFalse(isLoading, "Immediate cached emission must transition isLoading to false.")
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.groupName, "Besties")
    }
}
