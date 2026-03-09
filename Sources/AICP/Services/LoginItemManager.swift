import Foundation
import ServiceManagement

protocol LoginItemManaging: AnyObject {
    func setEnabled(_ enabled: Bool) throws
}

final class LoginItemManager: LoginItemManaging {
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
                // Ignore already-registered transient errors.
            }
        } else {
            do {
                try SMAppService.mainApp.unregister()
            } catch {
                // Ignore if not currently registered.
            }
        }
    }
}
