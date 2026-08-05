import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // One shared `UsageService` — both styles below just render whatever it
    // publishes, so switching styles in Settings never re-fetches or shows
    // different numbers.
    private let authStore = AuthStore()
    private lazy var usage = UsageService(authStore: authStore)
    private let preferences = AppPreferences()

    private lazy var fanController = PanelController(usage: usage, onOpenSettings: { [weak self] in self?.showSettings() })
    private lazy var pillController = PillPanelController(usage: usage, onOpenSettings: { [weak self] in self?.showSettings() })
    private var settingsWindowController: SettingsWindowController?
    private var styleObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // no Dock icon, menu-bar-only app

        authStore.onChange = { [weak self] in
            Task { await self?.usage.refresh() }
        }
        authStore.onManualAuthRequested = { [weak self] in
            self?.showSettings()
        }

        // No NSStatusItem — the app has no icon in the real menu bar at
        // all now, just its own bump/fan (or pill) living over the notch.
        // Quitting and Settings are reached via a right-click context menu
        // on the fan style's hub, or the pill style's own Settings button.
        styleObserver = preferences.$style.sink { [weak self] style in
            self?.applyStyle(style)
        }
    }

    private func applyStyle(_ style: AppStyle) {
        switch style {
        case .fan:
            pillController.hide()
            fanController.show()
        case .pill:
            fanController.hide()
            pillController.show()
        }
    }

    func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(preferences: preferences, authStore: authStore)
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow()
        settingsWindowController?.onClose = { [weak self] in
            self?.returnToAccessory()
        }
    }

    private func returnToAccessory() {
        let anyRegularWindowVisible = NSApp.windows.contains { $0.isVisible && !$0.title.isEmpty }
        if !anyRegularWindowVisible {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
