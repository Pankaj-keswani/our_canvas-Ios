import XCTest
@testable import OurCanvas

@MainActor
final class AdMobProductionTests: XCTestCase {

    // MARK: - AdMob Production Identifiers

    func testProductionRewardedAdUnitId() {
        // Must match production AdMob rewarded ad unit ID exactly
        let expectedUnitId = "ca-app-pub-7815261539621331/7008584794"
        XCTAssertEqual(RewardedAdManager.REWARDED_AD_UNIT_ID, expectedUnitId,
                       "Production rewarded ad unit ID must match Android ca-app-pub-7815261539621331/7008584794.")
        XCTAssertEqual(RewardedAdManager.adUnitId, expectedUnitId,
                       "adUnitId alias must match production ID.")
    }

    func testNoTestAdMobIdsRemain() {
        let testAdMobPrefix = "ca-app-pub-3940256099942544"
        XCTAssertFalse(RewardedAdManager.REWARDED_AD_UNIT_ID.contains(testAdMobPrefix),
                       "Test AdMob publisher ID (3940256099942544) must not be in use.")
        XCTAssertFalse(RewardedAdManager.adUnitId.contains(testAdMobPrefix))
    }

    func testInfoDictionaryOrPlistHasProductionAppId() {
        let expectedAppId = "ca-app-pub-7815261539621331~6740991488"

        // If Info.plist exists in bundle or can be loaded directly from file
        if let path = Bundle.main.path(forResource: "Info", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
           let appId = dict["GADApplicationIdentifier"] as? String {
            XCTAssertEqual(appId, expectedAppId)
        } else {
            // Also verify bundle info dictionary if injected
            let bundleAppId = Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String
            if let bundleAppId {
                XCTAssertEqual(bundleAppId, expectedAppId)
            }
        }
    }
}
