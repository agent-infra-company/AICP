import Foundation

struct AppRuntimeEnvironment: Equatable, Sendable {
    let bundleURL: URL
    let bundleIdentifier: String?

    init(bundleURL: URL = Bundle.main.bundleURL, bundleIdentifier: String? = Bundle.main.bundleIdentifier) {
        self.bundleURL = bundleURL
        self.bundleIdentifier = bundleIdentifier
    }

    static var current: AppRuntimeEnvironment {
        AppRuntimeEnvironment()
    }

    var isBundledApp: Bool {
        bundleURL.pathExtension == "app" && bundleIdentifier != nil
    }

    var supportsMenuBarExtra: Bool {
        isBundledApp
    }

    var supportsOnboarding: Bool {
        isBundledApp
    }

    var supportsNotifications: Bool {
        isBundledApp
    }

    var supportsLoginItemRegistration: Bool {
        isBundledApp
    }
}
