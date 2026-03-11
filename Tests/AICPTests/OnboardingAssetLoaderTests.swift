import XCTest
@testable import AICP

final class OnboardingAssetLoaderTests: XCTestCase {
    func testAppIconResolvesFromBundledResources() {
        XCTAssertNotNil(OnboardingAssetLoader.appIcon())
    }
}
