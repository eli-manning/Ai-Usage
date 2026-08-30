import AppKit
import SwiftUI
import UsageCore

/// Owns the one `UsageService`, the two shells, and the auxiliary windows.
///
/// The whole point of the native rebuild lives in `apply(mode:)`: switching
/// between the menu-bar and notch shells is an in-process view swap, not a
/// helper process being spawned and fed over a pipe. Both shells observe the
/// same service, so switching never re-fetches, never double-fetches, and
/// never shows one shell stale data the other already has.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let usage = UsageService()

    private lazy var statusItem = StatusItemController(
        usage: usage,
        onOpenSettings: { [weak self] in self?.openSettings() },
        onRunWizard: { [weak self] in self?.openWizard() })

    private lazy var panel = PanelController(usage: usage)

    private var settingsWindow: NSWindow?
    private var wizardWindow: NSWindow?
    private var currentMode: DisplayMode?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar app: no Dock icon, no app menu, no windows unless asked for.
        NSApp.setActivationPolicy(.accessory)

        NotificationCenter.default.addObserver(
            self, selector: #selector(openSettings),
            name: .openSettingsRequested, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(openWizard),
            name: .openWizardRequested, object: nil)

        apply(mode: resolvedMode())

        if !Settings.shared.setupComplete {
            openWizard()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Anything mid-flight is a `ptydrive` child holding a CLI's process
        // group open. `Process` termination on our side is what lets the
        // helper's own cleanup run, so give it an explicit chance rather than
        // letting the app exit out from under it.
        statusItem.remove()
        panel.hide()
    }

    // MARK: - Display mode

    /// The notch shell can't render on a display with no notch, so a settings
    /// file carried over from a MacBook to a Mac mini falls back rather than
    /// leaving the user with no UI at all.
    private func resolvedMode() -> DisplayMode {
        let stored = Settings.shared.displayMode
        if stored == .notch && !NotchGeometry.hasHardwareNotch { return .tray }
        return stored
    }

    func apply(mode: DisplayMode) {
        guard mode != currentMode else { return }
        currentMode = mode

        switch mode {
        case .tray:
            panel.hide()
            statusItem.install()
        case .notch:
            statusItem.remove()
            panel.show()
        }
    }

    // MARK: - Windows

    @objc func openSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView(
            usage: usage,
            onDisplayModeChange: { [weak self] mode in self?.apply(mode: mode) },
            onRunWizard: { [weak self] in self?.openWizard() })

        let window = makeWindow(title: "AI Usage Settings", content: view)
        window.delegate = self
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openWizard() {
        if let wizardWindow {
            wizardWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = WizardView(
            usage: usage,
            onDisplayModeChange: { [weak self] mode in self?.apply(mode: mode) },
            onFinish: { [weak self] in
                self?.wizardWindow?.close()
                self?.wizardWindow = nil
            })

        let window = makeWindow(title: "Welcome", content: view)
        window.delegate = self
        wizardWindow = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow<V: View>(title: String, content: V) -> NSWindow {
        let hosting = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(Theme.bg)
        window.appearance = NSAppearance(named: .darkAqua)
        // An accessory-policy app has no Dock icon to restore a window from, so
        // a released window would be unreachable — keep them alive and reuse.
        window.isReleasedWhenClosed = false
        return window
    }
}

extension AppDelegate: NSWindowDelegate {
    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            guard let closing = notification.object as? NSWindow else { return }
            if closing === settingsWindow { settingsWindow = nil }
            if closing === wizardWindow { wizardWindow = nil }
        }
    }
}
