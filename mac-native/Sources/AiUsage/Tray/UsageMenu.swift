import AppKit
import UsageCore

/// The usage dropdown: Mochi's panel (menu.html in a `BubblePanel`) with a tab per provider, its gauges, Claude's
/// history and details, and refresh, settings and quit. The menu bar icon opens it hanging from the menu bar; in
/// notch mode, right-clicking the notch opens it under the notch. One instance, shared by both shells.
@MainActor
final class UsageMenu {

    private let usage: UsageService
    private let onOpenSettings: () -> Void
    private lazy var panel = makePanel()
    private var chartMode: ChartMode = .session
    /// You picked another provider's tab.
    var onSelect: () -> Void = {}

    init(usage: UsageService, onOpenSettings: @escaping () -> Void) {
        self.usage = usage
        self.onOpenSettings = onOpenSettings
    }

    /// Opens with its tail on `x`, under `feet` (or over `top` if there's room there). Again closes it.
    func show(x: CGFloat, top: CGFloat, feet: CGFloat) { panel.show(x: x, top: top, feet: feet) }

    func update() { panel.update() }

    func close() { panel.close() }

    /// The selected provider, or the first still-enabled one if it was just switched off.
    static var selected: Provider {
        let s = Settings.shared.selectedProvider
        let id = Settings.shared.isEnabled(s) ? s : Settings.shared.firstEnabledProvider()
        return Provider.byID(id) ?? Provider.all[0]
    }

    private func makePanel() -> BubblePanel {
        let p = BubblePanel(page: "menu.html", level: .mainMenu + 4)   // over the notch's fan (.mainMenu + 3)
        p.state = { [weak self] in self?.state() ?? [:] }
        p.act = { [weak self] name, arg in self?.act(name, arg) }
        return p
    }

    private func act(_ name: String, _ arg: String?) {
        switch name {
        case "select":
            guard let arg, Provider.byID(arg) != nil else { return }
            Settings.shared.selectedProvider = arg
            onSelect()
        case "refresh":
            Task { await usage.refresh() }
        case "retry":
            if let arg { Task { await usage.refreshProvider(arg) } }
        case "install":
            guard let p = arg.flatMap(Provider.byID) else { return }
            if let command = p.installCommand { TerminalLauncher.run(command) }
            else if let url = p.installURL.flatMap(URL.init(string:)) { NSWorkspace.shared.open(url) }
        case "login":
            if let command = arg.flatMap(Provider.byID)?.loginCommand { TerminalLauncher.run(command) }
        case "chart":
            if let mode = arg.flatMap(ChartMode.init(rawValue:)) { chartMode = mode }
        case "settings":
            panel.close()
            onOpenSettings()
        case "quit":
            NSApp.terminate(nil)
        default:
            return
        }
        panel.update()
    }

    // MARK: - What the dropdown shows

    private func state() -> [String: Any] {
        let p = Self.selected
        var mood = p.name
        if usage.isRefreshing { mood = "checking..." } else if let at = usage.lastUpdated(p.id) { mood = "updated " + Format.ago(at) }
        return [
            "provider": p.id,
            "mood": mood,
            "refreshing": usage.isRefreshing,
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            "tabs": Provider.all.filter { Settings.shared.isEnabled($0.id) }.map { ["id": $0.id, "title": $0.name, "dot": dot($0.id)] },
            "body": body(for: p),
        ]
    }

    /// The little square on each tab: how that provider's usage is doing.
    private func dot(_ id: String) -> String {
        if case .error = usage.status(id).state { return "bad" }
        guard let pct = usage.primaryPct(id) else { return "" }
        return pct >= 90 ? "bad" : pct >= 70 ? "warn" : "ok"
    }

    private func gauge(_ label: String, _ pct: Int?, reset: String?, sub: String? = nil) -> [String: Any] {
        var g: [String: Any] = ["label": label.lowercased()]
        if let pct { g["pct"] = pct }
        if let r = Format.reset(reset) { g["reset"] = r.lowercased() }
        if let sub { g["sub"] = sub }
        return g
    }

    private func empty(_ title: String, hint: String? = nil, error: Bool = false,
                       action: (label: String, name: String, arg: String)? = nil) -> [String: Any] {
        var b: [String: Any] = ["kind": "empty", "title": title, "error": error]
        if let hint { b["hint"] = hint }
        if let action { b["action"] = ["label": action.label, "name": action.name, "arg": action.arg] }
        return b
    }

    private func body(for p: Provider) -> [String: Any] {
        if !Settings.shared.isEnabled(p.id) {
            return empty("\(p.name.lowercased()) is turned off.", hint: "turn it back on in settings.",
                         action: ("open settings", "settings", ""))
        }
        if p.id == "claude" { return claudeBody() }
        let status = usage.status(p.id)
        switch status.state {
        case .loggedIn:
            let gauges = otherGauges(p.id)
            if gauges.isEmpty { return empty("fetching \(p.name.lowercased()) usage...") }
            var b: [String: Any] = ["kind": "gauges", "gauges": gauges]
            if let message = status.message { b["banner"] = message.lowercased() }
            return b
        case .checking:
            return empty("checking \(p.name.lowercased())...")
        case .notInstalled:
            let action: (String, String, String)? = p.installCommand != nil ? ("install", "install", p.id)
                : p.installURL != nil ? ("open docs", "install", p.id) : nil
            return empty("\(p.name.lowercased()) isn't installed.", hint: p.installCommand ?? p.hint, action: action)
        case .installed:
            return empty("\(p.name.lowercased()) is installed, but not signed in yet.", hint: p.hint.lowercased(),
                         action: p.loginCommand != nil ? ("log in", "login", p.id) : nil)
        case .error(let message):
            return empty(message, hint: "this usually clears on the next refresh.", error: true, action: ("retry", "retry", p.id))
        case .disabled:
            return empty("\(p.name.lowercased()) is turned off.", hint: "turn it back on in settings.",
                         action: ("open settings", "settings", ""))
        }
    }

    private func otherGauges(_ id: String) -> [[String: Any]] {
        switch id {
        case "antigravity":
            let g = usage.antigravity
            return [gauge("5 hour", g?.fiveHourPct, reset: g?.fiveHourReset), gauge("weekly", g?.weeklyPct, reset: g?.weeklyReset)]
        case "codex":
            return (usage.codex?.limits ?? []).map {
                gauge(Pattern(#"\s*limit$"#, options: .caseInsensitive).replacingFirst(in: $0.name, with: ""), $0.pctUsed, reset: $0.reset)
            }
        case "cursor":
            // Every row shares the one reset date Cursor prints once, unlike Codex where each limit has its own.
            let c = usage.cursor
            return (c?.rows ?? []).map { gauge($0.name, $0.pctUsed, reset: c?.reset) }
        default:
            return []
        }
    }

    private func claudeBody() -> [String: Any] {
        let d = usage.claude
        guard d.session != nil || d.weekly != nil else {
            // Nothing cached to fall back on: say why, in words written for this spot.
            switch d.errorType {
            case "offline": return empty("you're offline.", hint: "waiting for a connection...")
            case "auth": return empty("not logged in to claude code.", hint: "run claude in a terminal to log in.",
                                      action: ("log in", "login", "claude"))
            default:
                return d.error.map { empty($0, hint: Provider.all[0].installCommand, error: true, action: ("retry", "retry", "claude")) }
                    ?? empty("fetching usage...")
            }
        }
        var gauges = [gauge("session", d.session, reset: d.sessionReset), gauge("weekly", d.weekly, reset: d.weeklyReset)]
        if let c = d.credits, let pct = c.pct {
            gauges.append(gauge("credits", pct, reset: c.reset,
                                sub: c.spent.map { String(format: "$%.2f / $%.2f spent", $0, c.total ?? 0) }))
        }
        var details: [String: Any] = ["history": ["mode": chartMode.rawValue, "bars": history()]]
        if let promo = d.weeklyPromo { details["promo"] = promo.lowercased() }
        if let s = d.skills, !s.isEmpty { details["skills"] = s.map { ["name": $0.name, "pct": $0.pct] } }
        if let m = d.mcpServers, !m.isEmpty { details["mcp"] = m.map { ["name": $0.name, "pct": $0.pct] } }
        if let st = d.stats {
            details["stats"] = stats(st).map { [$0.0, $0.1] }
            if let fact = st.funFact { details["fact"] = fact }
        }
        var b: [String: Any] = ["kind": "gauges", "gauges": gauges, "details": details]
        if let error = d.error {
            b["banner"] = d.errorType == "offline" ? "offline: showing last known usage" : error.lowercased()
        }
        return b
    }

    private func stats(_ st: Stats) -> [(String, String)] {
        var out: [(String, String)] = []
        if let v = st.favoriteModel { out.append(("favorite model", v)) }
        if let v = st.totalTokens { out.append(("total tokens", v)) }
        if let v = st.sessions { out.append(("sessions", "\(v)")) }
        if let v = st.activeDays { out.append(("active days", "\(v)/\(st.totalDays ?? 0)")) }
        if let v = st.longestSession { out.append(("longest session", v)) }
        if let v = st.longestStreak { out.append(("longest streak", v)) }
        if let v = st.currentStreak { out.append(("current streak", v)) }
        if let v = st.mostActiveDay { out.append(("most active day", v)) }
        return out
    }

    /// The chart's 24 columns: the highest reading in each slice of the window, or nothing where there were none.
    private func history() -> [Any] {
        let now = Date(), window = chartMode.window, slice = window / 24
        var bars = [Int?](repeating: nil, count: 24)
        for p in HistoryStore.shared.points(within: window, now: now) {
            guard let v = chartMode.value(p) else { continue }
            let i = min(23, max(0, Int((window - now.timeIntervalSince(p.timestamp)) / slice)))
            bars[i] = max(bars[i] ?? 0, v)
        }
        return bars.map { $0.map { $0 as Any } ?? NSNull() }
    }
}
