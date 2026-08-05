import Foundation

/// One usage window rendered as a meter bar in the pill style (Session,
/// Weekly, a Codex/Cursor limit row, ...).
struct PillUsagePeriod: Identifiable {
    var id: String
    var label: String
    /// 0...1, clamped by the meter itself. `nil` when there's no number yet.
    var fractionUsed: Double?
    var resetText: String?
}

enum PillFetchState: Equatable {
    case checking
    case notConnected
    case installed
    case loaded
    case failed(String)
}

struct PillProviderSnapshot: Identifiable {
    var id: String { provider.id }
    var provider: Provider
    var state: PillFetchState
    /// Populated by the OAuth account store once this provider is
    /// connected. Kept separate from status/hint copy so the identity
    /// column can remain exactly "provider name + email".
    var accountEmail: String? = nil
    var periods: [PillUsagePeriod]

    var worstFraction: Double? { periods.compactMap(\.fractionUsed).max() }
}

/// Reshapes `UsageService`'s own published data into the pill style's own
/// shape. This is deliberately just a *read* of the same data the fan style
/// already reads via `Bubble.swift` — there is no separate fetch, store, or
/// polling loop here, so both styles are always looking at the same numbers
/// at the same time.
@MainActor
enum PillUsageAdapter {
    static func snapshots(from usage: UsageService) -> [PillProviderSnapshot] {
        Provider.all.map { provider in
            let status = usage.providers[provider.id] ?? ProviderStatus(state: .checking)
            switch provider.id {
            case "claude":
                return claudeSnapshot(provider, usage.claude)
            case "antigravity":
                return antigravitySnapshot(provider, usage.antigravity, status)
            case "codex":
                return codexSnapshot(provider, usage.codex, status)
            case "cursor":
                return cursorSnapshot(provider, usage.cursor, status)
            default:
                return PillProviderSnapshot(provider: provider, state: fetchState(for: status), periods: [])
            }
        }
    }

    private static func fetchState(for status: ProviderStatus) -> PillFetchState {
        switch status.state {
        case .checking: return .checking
        case .notInstalled: return .notConnected
        case .installed: return .installed
        case .loggedIn: return .loaded
        case .error(let message): return .failed(message)
        }
    }

    /// Claude has no separate `ProviderStatus` gate in the fan style either
    /// (see `RingView.outerBubbles`) — its own fields already say whether
    /// there's real data, an auth problem, or a plain fetch error.
    private static func claudeSnapshot(_ provider: Provider, _ claude: ClaudeUsage) -> PillProviderSnapshot {
        var periods: [PillUsagePeriod] = []
        if let session = claude.session {
            periods.append(PillUsagePeriod(
                id: "session", label: "Session", fractionUsed: Double(session) / 100,
                resetText: claude.sessionReset.map { "Resets \(Format.reset($0) ?? "")" }
            ))
        }
        if let weekly = claude.weekly {
            periods.append(PillUsagePeriod(
                id: "weekly", label: "Weekly", fractionUsed: Double(weekly) / 100,
                resetText: claude.weeklyReset.map { "Resets \(Format.reset($0) ?? "")" }
            ))
        }
        if let credits = claude.credits, let pct = credits.pct {
            periods.append(PillUsagePeriod(id: "credits", label: "Credits", fractionUsed: Double(pct) / 100, resetText: nil))
        }

        guard periods.isEmpty else {
            return PillProviderSnapshot(provider: provider, state: .loaded, periods: periods)
        }
        if claude.errorType == "auth" {
            return PillProviderSnapshot(provider: provider, state: .installed, periods: [])
        }
        if let error = claude.error {
            return PillProviderSnapshot(provider: provider, state: .failed(error), periods: [])
        }
        return PillProviderSnapshot(provider: provider, state: .checking, periods: [])
    }

    private static func antigravitySnapshot(_ provider: Provider, _ g: GeminiUsage?, _ status: ProviderStatus) -> PillProviderSnapshot {
        guard status.state == .loggedIn, let g else {
            return PillProviderSnapshot(provider: provider, state: fetchState(for: status), periods: [])
        }
        var periods: [PillUsagePeriod] = []
        if let pct = g.fiveHourPct {
            periods.append(PillUsagePeriod(id: "fiveHour", label: "5 Hour", fractionUsed: Double(pct) / 100, resetText: g.fiveHourReset))
        }
        if let pct = g.weeklyPct {
            periods.append(PillUsagePeriod(id: "weekly", label: "Weekly", fractionUsed: Double(pct) / 100, resetText: g.weeklyReset))
        }
        return PillProviderSnapshot(provider: provider, state: periods.isEmpty ? .checking : .loaded, periods: periods)
    }

    private static func codexSnapshot(_ provider: Provider, _ c: CodexUsage?, _ status: ProviderStatus) -> PillProviderSnapshot {
        guard status.state == .loggedIn, let c, let limits = c.limits, !limits.isEmpty else {
            return PillProviderSnapshot(provider: provider, state: fetchState(for: status), periods: [])
        }
        let periods = limits.map { limit in
            PillUsagePeriod(
                id: limit.name,
                label: limit.name.replacingOccurrences(of: " limit", with: "", options: .caseInsensitive),
                fractionUsed: Double(limit.pctUsed) / 100,
                resetText: limit.reset.map { "Resets \($0)" }
            )
        }
        return PillProviderSnapshot(provider: provider, state: .loaded, periods: periods)
    }

    private static func cursorSnapshot(_ provider: Provider, _ c: CursorUsage?, _ status: ProviderStatus) -> PillProviderSnapshot {
        guard status.state == .loggedIn, let c, let rows = c.rows, !rows.isEmpty else {
            return PillProviderSnapshot(provider: provider, state: fetchState(for: status), periods: [])
        }
        let resetText = c.reset.map { "Resets \($0)" }
        let periods = rows.map { row in
            PillUsagePeriod(id: row.name, label: row.name, fractionUsed: Double(row.pctUsed) / 100, resetText: resetText)
        }
        return PillProviderSnapshot(provider: provider, state: .loaded, periods: periods)
    }
}
