import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    init(preferences: AppPreferences, authStore: AuthStore) {
        let view = SettingsView(preferences: preferences, authStore: authStore)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Ai Usage Settings"
        window.styleMask = [.titled, .closable]
        // `NSWindow(contentViewController:)` doesn't size itself from the
        // hosted SwiftUI view's own intrinsic size — without an explicit
        // content size the window collapses to just its title bar.
        window.setContentSize(NSSize(width: 520, height: 390))
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWindow() {
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
