import Foundation
import ServiceManagement

/// Start-at-login registration.
///
/// `SMAppService.mainApp` is the modern replacement for the deprecated
/// `LSSharedFileList` dance, and it only works for a real, signed `.app`
/// bundle — running the raw SwiftPM binary during development throws, which is
/// expected and not worth surfacing to the user as a failure.
enum LoginItem {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            // Unbundled dev builds always land here; a packaged build only
            // does if the user denied the request in System Settings.
            return false
        }
    }
}
