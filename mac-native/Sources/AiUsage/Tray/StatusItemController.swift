import AppKit
import Combine
import SwiftUI
import UsageCore

/// Owns the menu-bar status item and its popover — the tray shell.
///
/// One of the two shells `DisplayModeController` switches between; it holds no
/// data of its own and simply observes the shared `UsageService`.
@MainActor
final class StatusItemController {

    private var statusItem: NSStatusItem?
    private var popover: NSPanel?
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    private let usage: UsageService
    private let onOpenSettings: () -> Void
    private let onRunWizard: () -> Void

    init(usage: UsageService,
         onOpenSettings: @escaping () -> Void,
         onRunWizard: @escaping () -> Void) {
        self.usage = usage
        self.onOpenSettings = onOpenSettings
        self.onRunWizard = onRunWizard
    }

    // MARK: - Lifecycle

    func install() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item

        // Redraw the badge whenever anything it reflects changes. Cheap enough
        // to just recompute on every publish rather than diffing.
        usage.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateBadge() }
            .store(in: &cancellables)

        updateBadge()
    }

    func remove() {
        closePopover()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        cancellables.removeAll()
    }

    // MARK: - Badge

    /// The renderer is the source of truth for which tab is showing, but if
    /// that provider was just switched off there's a window before the popover
    /// notices — fall back to the first still-enabled provider rather than
    /// showing a disabled provider's stale colour in the menu bar.
    private var effectiveProvider: Provider {
        let selected = Settings.shared.selectedProvider
        let id = Settings.shared.isEnabled(selected) ? selected : Settings.shared.firstEnabledProvider()
        return Provider.byID(id) ?? Provider.all[0]
    }

    private func updateBadge() {
        guard let button = statusItem?.button else { return }
        let provider = effectiveProvider
        let color = NSColor(Color(hex: provider.colorHex))
        let status = usage.status(provider.id)
        let pct = usage.primaryPct(provider.id)

        if let pct {
            button.image = TrayIconRenderer.badge(pct: pct, color: color, letter: provider.letter)
        } else if case .error = status.state {
            button.image = TrayIconRenderer.placeholder(
                color: NSColor(Theme.red), letter: provider.letter)
        } else {
            button.image = TrayIconRenderer.placeholder(color: color, letter: provider.letter)
        }
        button.toolTip = tooltip(for: provider, status: status)
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

    // MARK: - Interaction

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp
            || event.modifierFlags.contains(.control) {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            .target = self
        menu.addItem(withTitle: "Run Setup Wizard…", action: #selector(runWizard), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit AI Usage", action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")

        // popUpContextMenu is deprecated in favour of assigning `menu`, but
        // assigning it permanently would steal the *left* click too — and the
        // left click has to open the popover, not a menu.
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func refreshNow() { Task { await usage.refresh() } }
    @objc private func openSettings() { onOpenSettings() }
    @objc private func runWizard() { onRunWizard() }

    // MARK: - Popover

    private func togglePopover() {
        if popover?.isVisible == true {
            closePopover()
        } else {
            showPopover()
        }
    }

    func showPopover() {
        guard let button = statusItem?.button,
              let buttonWindow = button.window else { return }

        let root = PopoverView(
            usage: usage,
            onOpenSettings: { [weak self] in
                self?.closePopover()
                self?.onOpenSettings()
            },
            onClose: { [weak self] in self?.closePopover() })

        let hosting = NSHostingView(rootView: root)
        // `PopoverView` already paints its own background and rounded border,
        // so the host must stay transparent or the corners sit on an opaque
        // square. This is also why this is a plain panel and not an
        // `NSPopover`: a popover always draws its own chrome *and* an arrow
        // pointing at the status item, which doubled up on the view's border
        // and left a stray sloped notch above it.
        hosting.layer?.backgroundColor = .clear
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false)
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The system chrome is gone, so the drop shadow has to come from the
        // window itself — without it the panel reads as painted onto the
        // desktop rather than floating above it.
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.animationBehavior = .utilityWindow

        panel.setFrameOrigin(origin(for: size, under: button, in: buttonWindow))
        panel.orderFrontRegardless()
        self.popover = panel

        // A borderless non-activating panel never becomes key, so nothing
        // dismisses it on its own — this monitor is now the only thing that
        // closes it on an outside click, rather than a backstop for the
        // transient popover's own handling.
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.closePopover()
        }
    }

    /// Centred under the status item, pinned just below the menu bar, and
    /// nudged back inside the screen if the item sits near a corner.
    private func origin(for size: NSSize, under button: NSStatusBarButton,
                        in buttonWindow: NSWindow) -> NSPoint {
        let buttonRect = buttonWindow.convertToScreen(
            button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
        let gap: CGFloat = 6

        var x = buttonRect.midX - size.width / 2
        let y = buttonRect.minY - gap - size.height

        if let visible = screen?.visibleFrame {
            let margin: CGFloat = 8
            x = min(max(x, visible.minX + margin), visible.maxX - size.width - margin)
        }
        return NSPoint(x: x, y: y)
    }

    func closePopover() {
        popover?.orderOut(nil)
        popover = nil
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}
