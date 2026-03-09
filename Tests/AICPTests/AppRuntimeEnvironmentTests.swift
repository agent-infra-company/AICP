import Foundation
import XCTest
@testable import AICP

final class AppRuntimeEnvironmentTests: XCTestCase {
    func testBundledAppEnablesSystemIntegrations() {
        let environment = AppRuntimeEnvironment(
            bundleURL: URL(fileURLWithPath: "/Applications/AICP.app"),
            bundleIdentifier: "com.aicp.app"
        )

        XCTAssertTrue(environment.isBundledApp)
        XCTAssertTrue(environment.supportsMenuBarExtra)
        XCTAssertTrue(environment.supportsOnboarding)
        XCTAssertTrue(environment.supportsNotifications)
        XCTAssertTrue(environment.supportsLoginItemRegistration)
    }

    func testUnbundledRunDisablesSystemIntegrations() {
        let environment = AppRuntimeEnvironment(
            bundleURL: URL(fileURLWithPath: "/tmp/AICP"),
            bundleIdentifier: nil
        )

        XCTAssertFalse(environment.isBundledApp)
        XCTAssertFalse(environment.supportsMenuBarExtra)
        XCTAssertFalse(environment.supportsOnboarding)
        XCTAssertFalse(environment.supportsNotifications)
        XCTAssertFalse(environment.supportsLoginItemRegistration)
    }
}
