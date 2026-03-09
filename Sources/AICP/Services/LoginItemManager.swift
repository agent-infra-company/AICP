import Foundation
import ServiceManagement
import os.log

protocol LoginItemManaging: AnyObject {
    func setEnabled(_ enabled: Bool) throws
}

final class LoginItemManager: LoginItemManaging {
    private static let log = CompanionDiagnostics.logger(category: "LoginItemManager")

    func setEnabled(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else {
            return
        }
        guard AppRuntimeEnvironment.current.supportsLoginItemRegistration else {
            return
        }

        if enabled {
            do {
                try SMAppService.mainApp.register()
            } catch {
                Self.log.warning("Login item registration failed: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            do {
                try SMAppService.mainApp.unregister()
            } catch {
                Self.log.warning("Login item unregistration failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
