import AppKit
import Combine
import UsageCore

/// The minis: one small critter per running agent session, for every provider.
///
/// Hook scripts in each CLI's config post events to `HookServer`;
/// `AgentSessionStore` turns them into sessions; this spawns a `MiniWindow` per
/// session, keeps each one showing what its session is doing, and raises an
/// alert (sound + notification) when a session finishes or needs you. The
/// alert holds until you respond in that session or click the mini or the
/// notification.
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

    private var store = AgentSessionStore()
    private let server = HookServer()
    private let alerts = AlertCenter()
    private var windows: [String: MiniWindow] = [:]
    /// Minis you hid from their menu, until their session ends.
    private var hidden: Set<String> = []
    private var tickTimer: Timer?
    private var mouseTimer: Timer?

    init() {
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
    }

    private func disable() {
        server.stop()
        listening = false
        for id in Array(windows.keys) { closeWindow(id) }
        for s in store.sessions.values { alerts.clear(s.id) }
        store = AgentSessionStore()
        publish()
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

        let key = AgentSession.key(event.provider, event.sessionID)
        switch store.apply(event, pid: d.pid) {
        case .alerted:
            if let s = store.sessions[key] {
                hidden.remove(key)   // a hidden mini comes back to ask for you
                alerts.raise(s, config: config)
            }
        case .answered:
            alerts.clear(key)
        case .removed:
            alerts.clear(key)
            hidden.remove(key)
        default:
            break
        }
        sync()
    }

    // MARK: - Acting on a mini

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

    func hide(_ id: String) {
        hidden.insert(id)
        acknowledge(id)
        sync()
    }

    func dismiss(_ id: String) {
        store.remove(id)
        alerts.clear(id)
        hidden.remove(id)
        sync()
    }

    func test(_ provider: String) {
        // Lets you see a provider's mini and hear its alert without a real session.
        let id = "test-\(Int(Date().timeIntervalSince1970))"
        store.apply(AgentEvent(provider: provider, sessionID: id, kind: .toolStart, activity: .editing,
                               detail: "example.swift", cwd: NSHomeDirectory() + "/Example"))
        sync()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            self.receiveTest(AgentEvent(provider: provider, sessionID: id, kind: .done, cwd: NSHomeDirectory() + "/Example"))
        }
    }

    private func receiveTest(_ e: AgentEvent) {
        let key = AgentSession.key(e.provider, e.sessionID)
        guard store.sessions[key] != nil else { return }
        if case .alerted = store.apply(e), let s = store.sessions[key] { alerts.raise(s, config: config) }
        sync()
    }

    func previewSound(_ kind: AlertKind) {
        alerts.play(config.sound(kind), volume: config.volume)
    }

    // MARK: - Windows

    private func tick() {
        guard config.enabled else { return }
        let removed = store.prune(idleTimeout: config.idleMinutes * 60)
        for id in removed { alerts.clear(id); hidden.remove(id) }
        alerts.tick(waiting: store.alerting, config: config)
        sync()
    }

    /// Makes the windows match the sessions.
    private func sync() {
        publish()
        let visible = store.ordered.filter { !hidden.contains($0.id) }
        let ids = Set(visible.map(\.id))
        for id in windows.keys where !ids.contains(id) { closeWindow(id) }
        let now = Date()
        for s in visible {
            let w = windows[s.id] ?? makeWindow(s.id)
            let (state, detail) = s.display(now: now)
            w.update([
                "provider": s.provider, "state": state, "detail": detail, "project": s.project,
                "speech": config.speech.rawValue, "animation": config.animation.rawValue,
                "motion": config.motion.rawValue, "scale": config.scale,
            ])
        }
        layout()
        updateMouseTracking()
    }

    private func publish() {
        let next = store.ordered
        if next != sessions { sessions = next }
    }

    private func makeWindow(_ id: String) -> MiniWindow {
        let w = MiniWindow(id: id, scale: config.scale)
        w.onAction = { [weak self, weak w] action in
            guard let self, let w else { return }
            switch action {
            case .click:
                self.acknowledge(id)
                self.focus(id)
            case .menu:
                w.showMenu(self.menu(for: id))
            case .moved:
                break
            }
        }
        windows[id] = w
        return w
    }

    private func closeWindow(_ id: String) {
        windows[id]?.close()
        windows[id] = nil
    }

    /// Lines up every mini that hasn't been dragged elsewhere along the bottom
    /// of the main screen, in provider order.
    private func layout() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let vf = screen.visibleFrame
        let step = CGFloat(46 * config.scale) * 0.9 + 6
        var i: CGFloat = 0
        for s in store.ordered {
            guard let w = windows[s.id], !w.pinned else { continue }
            let offset = 40 + step / 2 + i * step
            let x = config.placement == .bottomRight ? vf.maxX - offset : vf.minX + offset
            w.place(foot: NSPoint(x: x, y: vf.minY))
            i += 1
        }
    }

    private func updateMouseTracking() {
        if windows.isEmpty {
            mouseTimer?.invalidate()
            mouseTimer = nil
        } else if mouseTimer == nil {
            mouseTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    let m = NSEvent.mouseLocation
                    self?.windows.values.forEach { $0.trackMouse(m) }
                }
            }
        }
    }

    private func configChanged(from old: MinisConfig) {
        if config.enabled != old.enabled { config.enabled ? enable() : disable() }
        if config.scale != old.scale { windows.values.forEach { $0.resize(scale: config.scale) } }
        if config.providers != old.providers {
            for s in store.sessions.values where !config.providerOn(s.provider) { dismiss(s.id) }
        }
        sync()
    }

    // MARK: - Menu

    private func menu(for id: String) -> NSMenu {
        let menu = NSMenu()
        let s = store.sessions[id]
        let name = s.flatMap { Provider.byID($0.provider)?.name } ?? "Session"
        let title = NSMenuItem(title: [name, s?.project ?? ""].filter { !$0.isEmpty }.joined(separator: " · "),
                               action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Show Session") { [weak self] in self?.acknowledge(id); self?.focus(id) })
        if s?.alert != nil {
            menu.addItem(ClosureMenuItem("Dismiss Alert") { [weak self] in self?.acknowledge(id) })
        }
        menu.addItem(ClosureMenuItem("Hide Until It Needs Me") { [weak self] in self?.hide(id) })
        menu.addItem(ClosureMenuItem("Remove") { [weak self] in self?.dismiss(id) })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Mini Settings…") { NotificationCenter.default.post(name: .openSettingsRequested, object: nil) })
        return menu
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

/// An NSMenuItem that runs a closure, so a menu can be built inline.
final class ClosureMenuItem: NSMenuItem {
    private let run: () -> Void

    init(_ title: String, _ run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { run() }
}
