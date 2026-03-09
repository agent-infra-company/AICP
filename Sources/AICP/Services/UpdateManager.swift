import Foundation
import Sparkle

/// Wraps Sparkle's `SPUStandardUpdaterController` to provide auto-update
/// functionality. The controller is initialized lazily so the app still
/// launches cleanly when `SUFeedURL` is not yet configured in Info.plist.
///
/// To complete setup:
/// 1. Generate an EdDSA keypair: `./Sparkle.framework/bin/generate_keys`
/// 2. Add `SUFeedURL` (appcast URL) and `SUPublicEDKey` to Info.plist
/// 3. Host an appcast.xml feed updated on each release
@MainActor
final class UpdateManager: ObservableObject {
    private var updaterController: SPUStandardUpdaterController?

    init() {
        // Only initialize Sparkle when the feed URL is configured.
        if Bundle.main.infoDictionary?["SUFeedURL"] != nil {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        }
    }

    var canCheckForUpdates: Bool {
        updaterController?.updater.canCheckForUpdates ?? false
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }
}
