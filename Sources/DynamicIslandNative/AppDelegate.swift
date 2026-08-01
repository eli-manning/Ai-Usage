import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let panelController = PanelController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // no Dock icon, menu-bar-only app

        // No NSStatusItem — the app has no icon in the real menu bar at
        // all now, just its own bump/fan living over the notch. Quitting
        // moved to a right-click context menu on the hub itself (see
        // RingView's `hub`), so removing this doesn't strand anyone
        // without a way out.
        panelController.show()
    }
}
