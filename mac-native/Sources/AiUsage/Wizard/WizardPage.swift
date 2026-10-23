import AppKit
import UsageCore

/// First-run setup: wizard.html in a `PageWindow`. Welcome → Claude → the other tools → where it lives (only with a
/// notch) → start at login → done. The page keeps which step you're on; this sends it what was detected and does
/// what you click.
@MainActor
final class WizardPage {
    private let usage: UsageService
    private let onDisplayModeChange: (DisplayMode) -> Void
    private let onFinish: () -> Void
    private var page: PageWindow?

    init(usage: UsageService, onDisplayModeChange: @escaping (DisplayMode) -> Void, onFinish: @escaping () -> Void) {
        self.usage = usage
        self.onDisplayModeChange = onDisplayModeChange
        self.onFinish = onFinish
    }

    func show() {
        if let page { return page.show() }
        let p = PageWindow(page: "wizard.html", title: "Welcome to AI Usage", size: NSSize(width: 460, height: 520))
        p.state = { [weak self] in self?.state() ?? [:] }
        p.act = { [weak self] name, arg in self?.act(name, arg) }
        p.closed = { [weak self] in self?.page = nil }
        page = p
        p.show()
    }

    private func state() -> [String: Any] {
        [
            "notch": NotchGeometry.hasHardwareNotch,
            "displayMode": Settings.shared.displayMode.rawValue,
            "launchAtLogin": Settings.shared.launchAtLogin,
            "provider": Settings.shared.minis.provider,
            "providers": Provider.all.map(detection),
        ]
    }

    /// One tool as the page shows it: a status line, how it reads (ok / warn / bad), and what unblocks it.
    private func detection(_ p: Provider) -> [String: Any] {
        var d: [String: Any] = ["id": p.id, "name": p.name]
        let install: [String: Any]? = p.installCommand == nil ? nil : ["title": "install", "name": "install"]
        let signIn: [String: Any]? = p.loginCommand == nil ? nil : ["title": "log in", "name": "signin"]
        switch usage.status(p.id).state {
        case .checking:
            d["line"] = "looking..."
        case .notInstalled:
            d["line"] = "not installed."
            d["action"] = install
        case .installed:
            d["line"] = "found it. sign in to read your usage."
            d["tone"] = "warn"
            d["action"] = signIn
        case .loggedIn:
            d["line"] = usage.primaryPct(p.id).map { "signed in. \($0)% used." } ?? "signed in."
            d["tone"] = "ok"
        case .error(let message):
            d["line"] = message.lowercased()
            d["tone"] = "bad"
            d["action"] = signIn
        case .disabled:
            d["line"] = "turned off in settings."
        }
        return d
    }

    private func act(_ name: String, _ arg: String?) {
        switch name {
        case "install":
            if let cmd = arg.flatMap(Provider.byID)?.installCommand { TerminalLauncher.run(cmd) }
        case "signin":
            if let cmd = arg.flatMap(Provider.byID)?.loginCommand { TerminalLauncher.run(cmd) }
        case "recheck":
            Task { await usage.refresh() }
        case "mode":
            guard let mode = arg.flatMap(DisplayMode.init(rawValue:)) else { return }
            Settings.shared.displayMode = mode
            onDisplayModeChange(mode)
        case "startAtLogin":
            let on = arg == "true"
            Settings.shared.launchAtLogin = on
            LoginItem.setEnabled(on)
        case "finish":
            Settings.shared.setupComplete = true
            onFinish()
            page?.close()
        default:
            break
        }
    }
}
