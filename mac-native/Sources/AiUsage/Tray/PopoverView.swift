import SwiftUI
import UsageCore

/// The status-item panel — the native replacement for `popup.html`.
///
/// Structure is unchanged from the web original: header, provider switcher,
/// then whichever body the selected provider's state calls for, with the
/// history chart and all-time stats behind a "Show details" disclosure so the
/// resting panel is just the gauges.
struct PopoverView: View {
    @ObservedObject var usage: UsageService

    @State private var selected: String = Settings.shared.selectedProvider
    @State private var chartMode: ChartMode = .weekly
    @State private var detailsOpen = false
    /// Drives the relative "updated 3m ago" label without re-fetching.
    @State private var tick = Date()

    var onOpenSettings: () -> Void
    var onClose: () -> Void

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var provider: Provider {
        Provider.byID(selected) ?? Provider.all[0]
    }
    private var accent: Color { provider.color }

    /// Providers switched off in Settings don't get a tab at all. If the
    /// selected one was just switched off, fall back to the first enabled one
    /// rather than showing a dead tab.
    private var visibleProviders: [Provider] {
        Provider.all.filter { Settings.shared.isEnabled($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.border)
            switcher
            Divider().overlay(Theme.border)
            body(for: provider)
        }
        .frame(width: 320)
        .background(Theme.bg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .strokeBorder(Theme.border, lineWidth: 1))
        .onReceive(clock) { tick = $0 }
        .onAppear(perform: normaliseSelection)
        .onChange(of: usage.settingsRevision) { _ in normaliseSelection() }
    }

    private func normaliseSelection() {
        if !visibleProviders.contains(where: { $0.id == selected }) {
            selected = visibleProviders.first?.id ?? "claude"
            Settings.shared.selectedProvider = selected
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(provider.name) Usage")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(Theme.text)
                Text(freshnessLabel)
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            HStack(spacing: 4) {
                IconButton(systemName: "arrow.clockwise", spinning: usage.isRefreshing) {
                    Task { await usage.refresh() }
                }
                .help("Refresh")
                // No gear here on purpose — Settings lives on the status
                // item's right-click menu instead, so the header stays down
                // to the two things you actually do from the popover.
                IconButton(systemName: "xmark", action: onClose)
                    .help("Close")
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
    }

    private var freshnessLabel: String {
        _ = tick   // re-evaluate every second
        if let updated = usage.lastUpdated(selected) {
            return "updated " + Format.ago(updated)
        }
        return usage.isRefreshing ? "fetching…" : provider.name
    }

    // MARK: - Provider switcher

    private var switcher: some View {
        HStack(spacing: 4) {
            ForEach(visibleProviders) { p in
                Button {
                    guard selected != p.id else { return }
                    selected = p.id
                    Settings.shared.selectedProvider = p.id
                    detailsOpen = false
                } label: {
                    HStack(spacing: 5) {
                        BrandIconView(d: p.iconPath, size: 13, color: p.color)
                            .opacity(selected == p.id ? 1 : 0.55)
                        StatusDot(
                            color: dotColor(for: p),
                            // While a fetch is in flight every dot pulses in
                            // *that provider's own* brand colour rather than
                            // its resting usage-tier colour, so "which one is
                            // being pulled right now" reads per-tab instead of
                            // as one app-wide spinner.
                            pulsing: usage.isRefreshing)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selected == p.id ? Theme.surface : .clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(
                                        selected == p.id ? Theme.border : .clear, lineWidth: 1)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(p.name)
                .accessibilityLabel(p.name)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
    }

    private func dotColor(for p: Provider) -> Color {
        if usage.isRefreshing { return p.color }
        let status = usage.status(p.id)
        if case .error = status.state { return Theme.red }
        guard let pct = usage.primaryPct(p.id) else { return Color(hex: "555555") }
        return Theme.tier(pct, accent: p.color)
    }

    // MARK: - Body

    @ViewBuilder
    private func body(for p: Provider) -> some View {
        let status = usage.status(p.id)

        if !Settings.shared.isEnabled(p.id) {
            EmptyStateView(
                title: "\(p.name) is turned off.",
                hint: "Turn it back on in Settings.",
                action: ("Open Settings", onOpenSettings))
        } else if p.id == "claude" {
            claudeBody(status: status)
        } else {
            otherProviderBody(p, status: status)
        }
    }

    // MARK: Claude

    @ViewBuilder
    private func claudeBody(status: ProviderStatus) -> some View {
        let data = usage.claude

        if data.session == nil && data.weekly == nil {
            // Nothing cached to fall back on (first launch, or every attempt so
            // far failed). The message is tailored per errorType rather than
            // echoing the raw error string, which was written for the
            // stale-banner case and reads oddly here.
            EmptyStateView(
                title: emptyTitle(for: data),
                hint: emptyHint(for: data),
                isError: data.error != nil,
                action: emptyAction(for: data))
        } else {
            VStack(spacing: 0) {
                if let error = data.error {
                    StaleBanner(message: data.errorType == "offline"
                        ? "Offline — showing last known usage"
                        : error)
                }

                VStack(alignment: .leading, spacing: 13) {
                    StatGauge(label: "Session", pct: data.session,
                              reset: data.sessionReset, accent: accent)
                    StatGauge(label: "Weekly", pct: data.weekly,
                              reset: data.weeklyReset, accent: accent)
                    if let credits = data.credits, let pct = credits.pct {
                        StatGauge(
                            label: "Credits", pct: pct, reset: credits.reset,
                            sub: credits.spent.map { spent in
                                String(format: "$%.2f / $%.2f spent", spent, credits.total ?? 0)
                            },
                            accent: accent)
                    }
                }
                .padding(.horizontal, 13)
                .padding(.top, 13)
                .padding(.bottom, 11)

                Divider().overlay(Theme.border)
                detailsDisclosure

                if detailsOpen {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            historySection
                            if let promo = data.weeklyPromo {
                                Text(promo)
                                    .font(.system(size: 10))
                                    .foregroundStyle(accent)
                                    .padding(.top, 9)
                                    .padding(.bottom, 14)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            claudeDetails(data)
                        }
                        .padding(.horizontal, 13)
                        .padding(.bottom, 13)
                    }
                    .frame(maxHeight: 320)
                }
            }
        }
    }

    private func emptyTitle(for data: ClaudeUsage) -> String {
        switch data.errorType {
        case "offline": return "You're offline."
        case "auth": return "Not logged in to Claude Code."
        default: return data.error ?? "Fetching usage…"
        }
    }

    private func emptyHint(for data: ClaudeUsage) -> String? {
        switch data.errorType {
        case "offline": return "Waiting for a connection…"
        case "auth": return "Run `claude` in a terminal to log in."
        default: return data.error != nil ? Provider.all[0].installCommand : nil
        }
    }

    private func emptyAction(for data: ClaudeUsage) -> (String, () -> Void)? {
        guard data.errorType == "auth", let command = Provider.all[0].loginCommand else { return nil }
        return ("Log in", { TerminalLauncher.run(command) })
    }

    private var detailsDisclosure: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { detailsOpen.toggle() }
        } label: {
            HStack(spacing: 5) {
                Text(detailsOpen ? "HIDE DETAILS" : "SHOW DETAILS")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .rotationEffect(.degrees(detailsOpen ? 180 : 0))
            }
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("HISTORY")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(Theme.muted)
                Spacer()
                ChartModeToggle(mode: $chartMode)
            }
            HistoryChart(mode: chartMode, accent: accent)
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private func claudeDetails(_ data: ClaudeUsage) -> some View {
        if let skills = data.skills, !skills.isEmpty {
            DetailSection(title: "Skills") { NamedPctRows(entries: skills, accent: accent) }
        }
        if let mcp = data.mcpServers, !mcp.isEmpty {
            DetailSection(title: "MCP Servers") { NamedPctRows(entries: mcp, accent: accent) }
        }
        if let stats = data.stats {
            DetailSection(title: "All Time") {
                VStack(alignment: .leading, spacing: 8) {
                    StatChipGrid(chips: chips(from: stats))
                    if let fact = stats.funFact {
                        Text(fact)
                            .font(.system(size: 10.5))
                            .italic()
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func chips(from st: Stats) -> [(String, String)] {
        var out: [(String, String)] = []
        if let v = st.favoriteModel { out.append(("Favorite model", v)) }
        if let v = st.totalTokens { out.append(("Total tokens", v)) }
        if let v = st.sessions { out.append(("Sessions", "\(v)")) }
        if let v = st.activeDays { out.append(("Active days", "\(v)/\(st.totalDays ?? 0)")) }
        if let v = st.longestSession { out.append(("Longest session", v)) }
        if let v = st.longestStreak { out.append(("Longest streak", v)) }
        if let v = st.currentStreak { out.append(("Current streak", v)) }
        if let v = st.mostActiveDay { out.append(("Most active day", v)) }
        return out
    }

    // MARK: Other providers

    @ViewBuilder
    private func otherProviderBody(_ p: Provider, status: ProviderStatus) -> some View {
        if status.state == .loggedIn {
            VStack(spacing: 0) {
                if let message = status.message {
                    StaleBanner(message: message)
                }
                VStack(alignment: .leading, spacing: 13) {
                    ForEach(gauges(for: p), id: \.label) { g in
                        StatGauge(label: g.label, pct: g.pct, reset: g.reset, accent: accent)
                    }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 13)
            }
        } else {
            providerActionState(p, status: status)
        }
    }

    private struct Gauge { let label: String; let pct: Int?; let reset: String? }

    private func gauges(for p: Provider) -> [Gauge] {
        switch p.id {
        case "antigravity":
            let g = usage.antigravity
            return [
                Gauge(label: "5 Hour", pct: g?.fiveHourPct, reset: g?.fiveHourReset),
                Gauge(label: "Weekly", pct: g?.weeklyPct, reset: g?.weeklyReset),
            ]
        case "codex":
            return (usage.codex?.limits ?? []).map {
                Gauge(
                    label: Pattern(#"\s*limit$"#, options: .caseInsensitive)
                        .replacingFirst(in: $0.name, with: ""),
                    pct: $0.pctUsed,
                    reset: $0.reset.map { "Resets \($0)" })
            }
        case "cursor":
            // Every row shares the one reset date the panel prints once in its
            // header, unlike Codex where each limit carries its own.
            let c = usage.cursor
            return (c?.rows ?? []).map {
                Gauge(label: $0.name, pct: $0.pctUsed,
                      reset: c?.reset.map { "Resets \($0)" })
            }
        default:
            return []
        }
    }

    @ViewBuilder
    private func providerActionState(_ p: Provider, status: ProviderStatus) -> some View {
        switch status.state {
        case .checking:
            EmptyStateView(title: "Checking \(p.name)…")

        case .notInstalled:
            EmptyStateView(
                title: "\(p.name) isn't installed.",
                hint: p.installCommand ?? p.hint,
                action: installAction(p))

        case .installed:
            EmptyStateView(
                title: "\(p.name) is installed, but not signed in yet.",
                hint: p.hint,
                action: p.loginCommand.map { cmd in ("Log in", { TerminalLauncher.run(cmd) }) })

        case .error(let message):
            EmptyStateView(
                title: message,
                hint: "This usually clears on the next refresh.",
                isError: true,
                action: ("Retry", { Task { await usage.refreshProvider(p.id) } }))

        case .disabled:
            EmptyStateView(
                title: "\(p.name) is turned off.",
                hint: "Turn it back on in Settings.",
                action: ("Open Settings", onOpenSettings))

        case .loggedIn:
            EmptyStateView(title: "Fetching \(p.name) usage…")
        }
    }

    /// Prefers a real one-line install over handing the user a docs page.
    private func installAction(_ p: Provider) -> (String, () -> Void)? {
        if let command = p.installCommand {
            return ("Install", { TerminalLauncher.run(command) })
        }
        if let urlString = p.installURL, let url = URL(string: urlString) {
            return ("Open docs", { NSWorkspace.shared.open(url) })
        }
        return nil
    }
}

// MARK: - Small shared pieces

struct StatusDot: View {
    let color: Color
    var pulsing: Bool
    @State private var faded = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 5, height: 5)
            .opacity(pulsing && faded ? 0.3 : 1)
            .animation(
                pulsing
                    ? .easeInOut(duration: 0.55).repeatForever(autoreverses: true)
                    : .default,
                value: faded)
            .onAppear { faded = pulsing }
            .onChange(of: pulsing) { faded = $0 }
    }
}

struct IconButton: View {
    let systemName: String
    var spinning = false
    let action: () -> Void
    @State private var angle: Double = 0

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.muted)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Theme.border, lineWidth: 1))
                .rotationEffect(.degrees(spinning ? angle : 0))
        }
        .buttonStyle(.plain)
        .onChange(of: spinning) { isSpinning in
            if isSpinning {
                withAnimation(.linear(duration: 0.7).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            } else {
                angle = 0
            }
        }
    }
}

struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(Theme.muted)
            content
        }
        .padding(.top, 14)
    }
}

struct NamedPctRows: View {
    let entries: [NamedPct]
    let accent: Color

    var body: some View {
        VStack(spacing: 0) {
            ForEach(entries) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.name)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    Text("\(entry.pct)%")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(accent)
                }
                .padding(.vertical, 4)
                if entry.id != entries.last?.id {
                    Rectangle().fill(Theme.border).frame(height: 1)
                }
            }
        }
    }
}

struct StatChipGrid: View {
    let chips: [(String, String)]

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(chips, id: \.0) { label, value in
                VStack(alignment: .leading, spacing: 2) {
                    Text(label.uppercased())
                        .font(.system(size: 9))
                        .tracking(0.5)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                    Text(value)
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Theme.border, lineWidth: 1)))
            }
        }
    }
}
