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
    private lazy var minis = MinisController(usage: usage)

    private lazy var statusItem = StatusItemController(
        usage: usage,
        onOpenSettings: { [weak self] in self?.openSettings() })

    private lazy var panel = PanelController(usage: usage)

    private lazy var settings = SettingsPage(
        usage: usage, minis: minis,
        onDisplayModeChange: { [weak self] mode in self?.apply(mode: mode) },
        onRunWizard: { [weak self] in self?.openWizard() })

    private lazy var wizard = WizardPage(
        usage: usage,
        onDisplayModeChange: { [weak self] mode in self?.apply(mode: mode) },
        onFinish: {})

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
        minis.start()

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

    @objc func openSettings() { settings.show() }

    @objc func openWizard() { wizard.show() }
}
