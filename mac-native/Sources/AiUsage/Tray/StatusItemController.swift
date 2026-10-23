import AppKit
import Combine
import SwiftUI
import UsageCore

/// Owns the menu-bar status item — the tray shell.
///
/// The icon is the selected provider's mini with its usage beside it (`TrayIconRenderer`). Clicking it opens the
/// `UsageMenu` dropdown hanging from the menu bar. One of the two shells `AppDelegate` switches between; it holds no
/// data of its own and observes the shared `UsageService`.
@MainActor
final class StatusItemController {

    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    private let usage: UsageService
    private let menu: UsageMenu

    init(usage: UsageService, menu: UsageMenu) {
        self.usage = usage
        self.menu = menu
    }

    // MARK: - Lifecycle

    func install() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item

        // Redraw the icon whenever anything it reflects changes. Cheap enough
        // to just recompute on every publish rather than diffing.
        usage.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateIcon()
                self?.menu.update()
            }
            .store(in: &cancellables)
        // The menu bar's text colour follows the wallpaper and light/dark mode.
        DistributedNotificationCenter.default().publisher(for: Notification.Name("AppleInterfaceThemeChangedNotification"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)

        menu.onSelect = { [weak self] in self?.updateIcon() }
        updateIcon()
    }

    func remove() {
        menu.close()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        cancellables.removeAll()
    }

    // MARK: - Icon

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        let provider = UsageMenu.selected
        let mood: TrayIconRenderer.Mood
        if usage.isRefreshing { mood = .busy } else if case .error = usage.status(provider.id).state { mood = .error } else { mood = .fine }
        let dark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        button.image = TrayIconRenderer.icon(provider: provider.id, pct: usage.primaryPct(provider.id), mood: mood, darkBar: dark)
        button.toolTip = tooltip(for: provider, status: usage.status(provider.id))
    }

    private func tooltip(for provider: Provider, status: ProviderStatus) -> String {
        switch provider.id {
        case "claude":
            let d = usage.claude
            guard d.session != nil || d.weekly != nil else {
                return d.error.map { "AI Usage — \($0)" } ?? "AI Usage — fetching…"
            }
            let base = "Claude — Session: \(Format.pct(d.session))%  Weekly: \(Format.pct(d.weekly))%"
            return d.error.map { "\(base) (\($0))" } ?? base
        case "antigravity":
            guard status.state == .loggedIn, let g = usage.antigravity else { break }
            return "Antigravity — 5hr: \(Format.pct(g.fiveHourPct))%  Weekly: \(Format.pct(g.weeklyPct))%"
        case "codex":
            guard status.state == .loggedIn, let c = usage.codex else { break }
            return "Codex (\(c.plan ?? "?")) — \(Format.pct(c.primaryPct))%"
        case "cursor":
            guard status.state == .loggedIn, let c = usage.cursor else { break }
            return "Cursor (\(c.plan ?? "?")) — \(Format.pct(c.primaryPct))%"
        default:
            break
        }
        return "\(provider.name): \(status.message(installHint: provider.hint))"
    }

    // MARK: - Dropdown

    /// Left or right click: the dropdown has everything the old right-click menu did.
    @objc private func statusItemClicked() {
        guard let button = statusItem?.button, let window = button.window else { return }
        let r = window.convertToScreen(button.convert(button.bounds, to: nil))
        menu.show(x: r.midX, top: r.maxY, feet: r.minY - 2)
    }
}
