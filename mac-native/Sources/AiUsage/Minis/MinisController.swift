import AppKit
import Combine
import UsageCore

/// The mini: one small critter on screen, in the look of the provider you pick in its panel (Claude, Codex,
/// Antigravity or Cursor). It follows that provider's sessions and shows whichever needs you most.
///
/// Hook scripts in each CLI's config post events to `HookServer`; `AgentSessionStore` turns them into sessions.
/// Every connected provider still raises alerts (sound + notification) when a session finishes or needs you,
/// whichever mini is on screen. An alert holds until you respond in that session, or click the mini, the
/// session in the panel, or the notification. Right-clicking the mini opens its panel (`MiniPanel`), Mochi's.
@MainActor
final class MinisController: ObservableObject {

    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var installed: [String: Bool] = [:]
    @Published private(set) var listening = false
    @Published var config: MinisConfig {
        didSet {
            guard config != oldValue else { return }
            Settings.shared.minis = config
            configChanged(from: oldValue)
        }
    }

    private let usage: UsageService
    private var store = AgentSessionStore()
    private let server = HookServer()
    private let alerts = AlertCenter()
    private var window: MiniWindow?
    private lazy var panel = makePanel()
    /// Hidden from the panel's eye button, until something needs you.
    private var hidden = false
    /// Said under the panel after connecting a provider, e.g. that Codex wants the hook approved.
    private var note: String?
    private var tickTimer: Timer?
    private var mouseTimer: Timer?

    init(usage: UsageService) {
        self.usage = usage
        config = Settings.shared.minis
        refreshInstalled()
    }

    func start() {
        HookInstaller.refreshScripts()
        server.onHook = { [weak self] d in self?.receive(d) }
        alerts.onResponse = { [weak self] id, focus in
            self?.acknowledge(id)
            if focus { self?.focus(id) }
        }
        if config.enabled { enable() }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
    }

    private func enable() {
        server.start()
        alerts.start()
        // The listener reports ready asynchronously.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.listening = self?.server.listening ?? false }
        sync()
    }

    private func disable() {
        server.stop()
        listening = false
        panel.close()
        window?.close()
        window = nil
        for s in store.sessions.values { alerts.clear(s.id) }
        store = AgentSessionStore()
        sync()
    }

    // MARK: - Hooks

    func refreshInstalled() {
        installed = Dictionary(uniqueKeysWithValues: Provider.ids.map { ($0, HookInstaller.isInstalled($0)) })
    }

    func setInstalled(_ provider: String, _ on: Bool) throws {
        defer { refreshInstalled() }
        try HookInstaller.setInstalled(provider, on)
    }

    private func receive(_ d: HookServer.Delivery) {
        guard config.enabled, config.providerOn(d.provider) else { return }
        var session = d.session
        // Antigravity names no session; one agy process is one session.
        if d.provider == "antigravity", session == nil, d.pid > 0 { session = "pid\(d.pid)" }
        guard let event = HookNormalizer.normalize(provider: d.provider, event: d.event, session: session, json: d.json)
        else { return }
        // Mochi checking Claude usage runs Claude Code in its own folder: not a real session.
        if event.cwd.hasSuffix("/Application Support/Mochi") { return }
        apply(event, pid: d.pid)
    }

    private func apply(_ event: AgentEvent, pid: Int32 = 0) {
        let key = AgentSession.key(event.provider, event.sessionID)
        switch store.apply(event, pid: pid) {
        case .alerted:
            if let s = store.sessions[key] {
                if s.provider == config.provider { hidden = false }   // a hidden mini comes back to ask for you
                alerts.raise(s, config: config)
            }
        case .answered, .removed:
            alerts.clear(key)
        default:
            break
        }
        sync()
    }

    // MARK: - Acting on sessions

    /// You looked at it.
    func acknowledge(_ id: String) {
        if store.acknowledge(id) {
            alerts.clear(id)
            sync()
        }
    }

    /// Brings the app the session runs in (terminal, editor, desktop app) to the front.
    func focus(_ id: String) {
        guard let pid = store.sessions[id]?.pid, pid > 0, let app = Self.app(owning: pid) else { return }
        app.activate()
    }

    /// Lets you see a provider's mini and hear its alert without a real session.
    func test(_ provider: String) {
        config.provider = provider
        let id = "test-\(Int(Date().timeIntervalSince1970))"
        let cwd = NSHomeDirectory() + "/Example"
        apply(AgentEvent(provider: provider, sessionID: id, kind: .toolStart, activity: .editing, detail: "example.swift", cwd: cwd))
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.store.sessions[AgentSession.key(provider, id)] != nil else { return }
            self.apply(AgentEvent(provider: provider, sessionID: id, kind: .done, cwd: cwd))
        }
    }

    func previewSound(_ kind: AlertKind) {
        alerts.play(config.sound(kind), volume: config.volume)
    }

    // MARK: - The window

    private func tick() {
        guard config.enabled else { return }
        for id in store.prune(idleTimeout: config.idleMinutes * 60) { alerts.clear(id) }
        alerts.tick(waiting: store.alerting, config: config)
        sync()
    }

    /// Makes the window match the chosen provider's sessions.
    private func sync() {
        let next = store.ordered
        if next != sessions { sessions = next }
        panel.update()
        guard config.enabled, !hidden else {
            window?.panel.orderOut(nil)
            updateMouseTracking()
            return
        }
        let w = window ?? makeWindow()
        let s = store.shown(for: config.provider)
        let (state, detail) = s?.display(now: Date()) ?? ("idle", "")
        w.update([
            "provider": config.provider, "state": state, "detail": detail, "project": s?.project ?? "",
            "speech": config.speech.rawValue, "animation": config.animation.rawValue,
            "motion": config.motion.rawValue, "scale": config.scale, "panel": panel.isOpen,
        ])
        layout()
        updateMouseTracking()
    }

    private func makeWindow() -> MiniWindow {
        let w = MiniWindow(id: "mini", scale: config.scale)
        w.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .click: self.clicked()
            case .menu: self.openPanel()
            case .moved: break
            }
        }
        window = w
        return w
    }

    /// Clicking the mini answers whatever it's showing: clears its alert and brings its session forward.
    /// With nothing to show, it opens the panel instead.
    private func clicked() {
        guard let s = store.shown(for: config.provider) else { return openPanel() }
        acknowledge(s.id)
        focus(s.id)
    }

    /// In its corner, unless you've dragged it somewhere else.
    private func layout() {
        guard let w = window, !hidden, config.enabled else { return }
        guard !w.pinned else { if !w.panel.isVisible { w.panel.orderFrontRegardless() }; return }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let vf = screen.visibleFrame
        let offset = 40 + MiniWindow.size(scale: config.scale).width / 2
        let x = config.placement == .bottomRight ? vf.maxX - offset : vf.minX + offset
        w.place(foot: NSPoint(x: x, y: vf.minY))
    }

    private func updateMouseTracking() {
        let tracking = window?.panel.isVisible == true
        if !tracking {
            mouseTimer?.invalidate()
            mouseTimer = nil
        } else if mouseTimer == nil {
            mouseTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.window?.trackMouse(NSEvent.mouseLocation) }
            }
        }
    }

    private func configChanged(from old: MinisConfig) {
        if config.enabled != old.enabled { config.enabled ? enable() : disable() }
        if config.scale != old.scale { window?.resize(scale: config.scale) }
        if config.provider != old.provider { note = nil }
        if config.providers != old.providers {
            for s in store.sessions.values where !config.providerOn(s.provider) {
                store.remove(s.id)
                alerts.clear(s.id)
            }
        }
        sync()
    }

    // MARK: - The panel

    private func makePanel() -> MiniPanel {
        let p = MiniPanel(webDir: MiniWindow.resources)
        p.state = { [weak self] in self?.panelState() ?? [:] }
        p.act = { [weak self] name, arg in self?.panelAction(name, arg) }
        p.opened = { [weak self] _ in self?.sync() }
        return p
    }

    private func openPanel() {
        guard let w = window else { return }
        let foot = w.foot
        // The tallest critter's head is about 24 critter pixels over its feet.
        panel.show(x: foot.x, top: foot.y + CGFloat(24 * config.scale), feet: foot.y)
    }

    private func panelState() -> [String: Any] {
        let p = config.provider
        let now = Date()
        let mine = store.sessions(of: p)
        let shown = store.shown(for: p)
        var mood = "no sessions"
        if hidden { mood = "hidden until something needs you" } else if let shown {
            let (state, detail) = shown.display(now: now)
            mood = [shown.project, Self.line(state, detail)].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        var state: [String: Any] = [
            "provider": p, "mood": mood, "hidden": hidden,
            "connected": installed[p] == true, "canConnect": HookInstaller.canInstall(p),
            "listening": listening, "port": Int(HookServer.port),
            "sessions": mine.map { s -> [String: Any] in
                let (state, detail) = s.display(now: now)
                return ["id": s.id, "project": s.project, "line": Self.line(state, detail),
                        "need": s.alert == .needsInput || s.alert == .failed, "done": s.alert == .done,
                        "busy": s.phase == .working]
            },
            "config": [
                "scale": config.scale, "speech": config.speech.rawValue, "animation": config.animation.rawValue,
                "motion": config.motion.rawValue, "repeatSeconds": config.repeatSeconds, "notifications": config.notifications,
                "alerts": Dictionary(uniqueKeysWithValues: AlertKind.allCases.map { ($0.rawValue, config.alerts($0)) }),
            ],
        ]
        if let note { state["followUp"] = note }
        if let pct = usage.primaryPct(p) {
            var u: [String: Any] = ["pct": pct]
            if let at = usage.lastUpdated(p) {
                u["updated"] = RelativeDateTimeFormatter().localizedString(for: at, relativeTo: now)
            }
            state["usage"] = u
        }
        return state
    }

    /// "editing App.swift", "needs input", "idle": a session's state the way the panel says it.
    private static func line(_ state: String, _ detail: String) -> String {
        let word: String
        switch state {
        case "needsInput": word = "needs input"
        case "done": word = "finished"
        case "tool": word = "using a tool"
        default: word = state
        }
        return detail.isEmpty ? word : word + " " + detail
    }

    private func panelAction(_ name: String, _ arg: String?) {
        switch name {
        case "provider":
            if let arg, Provider.byID(arg) != nil { config.provider = arg }
        case "focus":
            guard let arg else { return }
            acknowledge(arg)
            focus(arg)
            panel.close()
        case "dismissAll":
            for s in store.sessions(of: config.provider) { acknowledge(s.id) }
        case "visible":
            hidden.toggle()
            sync()
        case "connect":
            let p = config.provider, on = installed[p] != true
            do {
                try setInstalled(p, on)
                note = on ? HookInstaller.targets[p]?.followUp : nil
            } catch {
                note = error.localizedDescription
            }
            sync()
        case "set":
            guard let arg, let eq = arg.firstIndex(of: "=") else { return }
            set(String(arg[..<eq]), String(arg[arg.index(after: eq)...]))
        case "settings":
            panel.close()
            NotificationCenter.default.post(name: .openSettingsRequested, object: nil)
        default:
            break
        }
    }

    /// One setting from the panel, as `key=value`.
    private func set(_ key: String, _ value: String) {
        var c = config
        switch key {
        case "scale": if let v = Double(value) { c.scale = v }
        case "speech": if let v = MiniSpeech(rawValue: value) { c.speech = v }
        case "animation": if let v = MiniAnimation(rawValue: value) { c.animation = v }
        case "motion": if let v = MiniMotion(rawValue: value) { c.motion = v }
        case "repeatSeconds": if let v = Double(value) { c.repeatSeconds = v }
        case "notifications": c.notifications = value == "true"
        default:
            if key.hasPrefix("alert."), let kind = AlertKind(rawValue: String(key.dropFirst(6))) {
                c.alertOn[kind.rawValue] = value == "true"
            }
        }
        config = c
    }

    // MARK: - Finding a session's app

    private static func parent(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let p = info.kp_eproc.e_ppid
        return p > 1 ? p : nil
    }

    /// The app a process belongs to: walk up its parents until one is an app with a window.
    static func app(owning pid: pid_t) -> NSRunningApplication? {
        var p: pid_t? = pid
        for _ in 0..<40 {
            guard let cur = p else { break }
            if let a = NSRunningApplication(processIdentifier: cur), a.activationPolicy == .regular { return a }
            p = parent(of: cur)
        }
        return nil
    }
}
