import AppKit
import UsageCore

/// The Settings window: settings.html in a `PageWindow`, on Mochi's paper. Where usage shows, which providers
/// it reads, the mini and its alerts, and the general switches.
@MainActor
final class SettingsPage {

    private let usage: UsageService
    private let minis: MinisController
    private let onDisplayModeChange: (DisplayMode) -> Void
    private let onRunWizard: () -> Void
    private var page: PageWindow?
    /// Said under the hook rows after connecting one, e.g. that Codex wants the hook approved.
    private var note: String?
    private var error: String?

    init(usage: UsageService, minis: MinisController,
         onDisplayModeChange: @escaping (DisplayMode) -> Void, onRunWizard: @escaping () -> Void) {
        self.usage = usage
        self.minis = minis
        self.onDisplayModeChange = onDisplayModeChange
        self.onRunWizard = onRunWizard
    }

    func show() {
        if let page { return page.show() }
        let p = PageWindow(page: "settings.html", title: "AI Usage Settings", size: NSSize(width: 460, height: 700))
        p.state = { [weak self] in self?.state() ?? [:] }
        p.act = { [weak self] name, arg in self?.act(name, arg) }
        page = p
        p.show()
    }

    // MARK: - State

    private func state() -> [String: Any] {
        let c = minis.config
        return [
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            "displayMode": Settings.shared.displayMode.rawValue,
            "hasNotch": NotchGeometry.hasHardwareNotch,
            "launchAtLogin": Settings.shared.launchAtLogin,
            "providers": Provider.all.map { p -> [String: Any] in
                let on = Settings.shared.isEnabled(p.id)
                let status = usage.status(p.id)
                var row: [String: Any] = ["id": p.id, "name": p.name.lowercased(), "enabled": on,
                                          "status": statusText(status, on: on), "tone": tone(status, on: on)]
                if on, let a = primaryAction(p, status) { row["action"] = a.title }
                return row
            },
            "minis": [
                "enabled": c.enabled, "listening": minis.listening, "port": Int(HookServer.port), "provider": c.provider,
                "hooks": Provider.all.map { p -> [String: Any] in
                    ["id": p.id, "name": p.name.lowercased(), "installed": minis.installed[p.id] == true,
                     "canInstall": HookInstaller.canInstall(p.id), "alertsOn": c.providerOn(p.id),
                     "live": minis.sessions.filter { $0.provider == p.id }.count]
                },
                "note": note ?? "", "error": error ?? "",
                "speech": c.speech.rawValue, "animation": c.animation.rawValue, "motion": c.motion.rawValue,
                "placement": c.placement.rawValue, "scale": c.scale, "idleMinutes": c.idleMinutes,
                "alerts": Dictionary(uniqueKeysWithValues: AlertKind.allCases.map {
                    ($0.rawValue, ["on": c.alerts($0), "sound": c.sound($0)] as [String: Any])
                }),
                "repeatSeconds": c.repeatSeconds, "volume": c.volume, "notifications": c.notifications,
                "sounds": MinisConfig.soundChoices,
            ] as [String: Any],
        ]
    }

    private func statusText(_ status: ProviderStatus, on: Bool) -> String {
        guard on else { return "turned off." }
        switch status.state {
        case .checking: return "checking…"
        case .notInstalled: return "not installed."
        case .installed: return "installed, not signed in."
        case .loggedIn: return status.message.map { "signed in (\($0.lowercased()))" } ?? "signed in."
        case .error(let message): return message.lowercased()
        case .disabled: return "turned off."
        }
    }

    private func tone(_ status: ProviderStatus, on: Bool) -> String {
        guard on else { return "" }
        switch status.state {
        case .loggedIn: return status.message == nil ? "ok" : "warn"
        case .error: return "error"
        default: return ""
        }
    }

    /// Install beats log-in beats nothing: whichever one actually unblocks you from here.
    private func primaryAction(_ p: Provider, _ status: ProviderStatus) -> (title: String, run: () -> Void)? {
        switch status.state {
        case .notInstalled:
            if let command = p.installCommand { return ("install", { TerminalLauncher.run(command) }) }
            if let s = p.installURL, let url = URL(string: s) { return ("docs", { NSWorkspace.shared.open(url) }) }
            return nil
        case .installed, .error:
            return p.loginCommand.map { cmd in ("log in", { TerminalLauncher.run(cmd) }) }
        default:
            return nil
        }
    }

    // MARK: - Actions

    /// `arg` is a provider id, or `key=value`.
    private func act(_ name: String, _ arg: String?) {
        let (key, value) = Self.split(arg)
        switch name {
        case "displayMode":
            guard let mode = DisplayMode(rawValue: arg ?? ""), mode == .tray || NotchGeometry.hasHardwareNotch else { return }
            Settings.shared.displayMode = mode
            onDisplayModeChange(mode)
        case "enable":
            guard Provider.byID(key) != nil else { return }
            Task { await usage.setProviderEnabled(key, value == "true") }
        case "providerAction":
            guard let p = Provider.byID(arg ?? ""), let a = primaryAction(p, usage.status(p.id)) else { return }
            a.run()
        case "hook":
            guard Provider.byID(key) != nil else { return }
            let on = value == "true"
            do {
                try minis.setInstalled(key, on)
                error = nil
                note = on ? HookInstaller.targets[key]?.followUp.map { "\(Provider.byID(key)!.name.lowercased()): \($0.lowercased())" } : nil
            } catch {
                self.error = error.localizedDescription
            }
        case "test":
            if Provider.byID(arg ?? "") != nil { minis.test(arg!) }
        case "preview":
            if let kind = AlertKind(rawValue: arg ?? "") { minis.previewSound(kind) }
        case "set":
            set(key, value)
        case "openNotifications":
            let id = Bundle.main.bundleIdentifier ?? "com.eli.aiusage"
            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
                NSWorkspace.shared.open(url)
            }
        case "login":
            let on = arg == "true"
            Settings.shared.launchAtLogin = on
            LoginItem.setEnabled(on)
        case "wizard":
            onRunWizard()
        case "reveal":
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: Settings.supportDirectory.path)
        case "quit":
            NSApp.terminate(nil)
        default:
            break
        }
    }

    /// One of the mini's settings, as `key=value`; anything unrecognised is ignored.
    private func set(_ key: String, _ value: String) {
        var c = minis.config
        switch key {
        case "enabled": c.enabled = value == "true"
        case "provider": if Provider.byID(value) != nil { c.provider = value }
        case "speech": if let v = MiniSpeech(rawValue: value) { c.speech = v }
        case "animation": if let v = MiniAnimation(rawValue: value) { c.animation = v }
        case "motion": if let v = MiniMotion(rawValue: value) { c.motion = v }
        case "placement": if let v = MiniPlacement(rawValue: value) { c.placement = v }
        case "scale": if let v = Double(value), (1.5...4).contains(v) { c.scale = v }
        case "idleMinutes": if let v = Double(value), v > 0 { c.idleMinutes = v }
        case "repeatSeconds": if let v = Double(value), v >= 0 { c.repeatSeconds = v }
        case "volume": if let v = Double(value), (0...1).contains(v) { c.volume = v }
        case "notifications": c.notifications = value == "true"
        default:
            let parts = key.split(separator: ".", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return }
            switch parts[0] {
            case "alert": if let k = AlertKind(rawValue: parts[1]) { c.alertOn[k.rawValue] = value == "true" }
            case "sound": if AlertKind(rawValue: parts[1]) != nil, MinisConfig.soundChoices.contains(value) { c.sounds[parts[1]] = value }
            case "alerts": if Provider.byID(parts[1]) != nil { c.providers[parts[1]] = value == "true" }
            default: return
            }
        }
        minis.config = c
    }

    private static func split(_ arg: String?) -> (String, String) {
        guard let arg, let eq = arg.firstIndex(of: "=") else { return (arg ?? "", "") }
        return (String(arg[..<eq]), String(arg[arg.index(after: eq)...]))
    }
}
