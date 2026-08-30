import SwiftUI
import UsageCore

enum IconKind {
    case svg(String)   // real brand mark path data
    case symbol(String) // SF Symbol name
}

/// A single ring bubble — either a provider (top level) or one of a
/// provider's own metrics (after drilling in). Same shape either way so the
/// ring/wedge code doesn't need to know which kind it's drawing.
struct Bubble: Identifiable {
    var id: String
    var label: String
    var color: Color
    var icon: IconKind
    var pct: Int?     // drives the border progress arc; nil = no arc
    var big: String   // headline value shown in the hub when selected
    var sub: String?  // reset time / spend / hint, shown in the hub

    /// `antigravity`/`codex` are `UsageService`'s cached last-known quota —
    /// kept around independent of whichever provider is currently
    /// active/shown, so switching over to it (or just glancing at its
    /// provider-picker wedge) shows real numbers immediately instead of a
    /// blank state while a fresh fetch runs.
    static func providers(claude: ClaudeUsage, providerStatus: [String: ProviderStatus], antigravity: GeminiUsage?, codex: CodexUsage?, cursor: CursorUsage?) -> [Bubble] {
        Provider.all.map { p in
            if p.id == "claude" {
                return Bubble(id: p.id, label: p.name, color: p.color, icon: .svg(p.icon),
                              pct: claude.session,
                              big: claude.session != nil ? "\(claude.session!)%" : "—",
                              sub: claude.errorType == "offline" ? "Offline" : nil)
            }
            let status = providerStatus[p.id] ?? ProviderStatus(state: .checking)
            if p.id == "antigravity", status.state == .loggedIn, let g = antigravity {
                // Same "right now" convention as Claude's session figure —
                // the 5-hour window is Antigravity's rolling short-term
                // quota, falling back to weekly if that's all that parsed.
                let pct = g.fiveHourPct ?? g.weeklyPct
                return Bubble(id: p.id, label: p.name, color: p.color, icon: .svg(p.icon),
                              pct: pct, big: pct != nil ? "\(pct!)%" : "—", sub: nil)
            }
            if p.id == "codex", status.state == .loggedIn, let c = codex {
                let pct = c.primaryPct
                return Bubble(id: p.id, label: p.name, color: p.color, icon: .svg(p.icon),
                              pct: pct, big: pct != nil ? "\(pct!)%" : "—", sub: nil)
            }
            if p.id == "cursor", status.state == .loggedIn, let cu = cursor {
                let pct = cu.primaryPct
                return Bubble(id: p.id, label: p.name, color: p.color, icon: .svg(p.icon),
                              pct: pct, big: pct != nil ? "\(pct!)%" : "—", sub: nil)
            }
            return Bubble(id: p.id, label: p.name, color: p.color, icon: .svg(p.icon),
                          pct: nil, big: "", sub: status.message(installHint: p.hint))
        }
    }

    static let claudeOrange = Color(hex: "CC785C")

    /// A generic, provider-agnostic filler wedge — "when did we last hear
    /// from this provider" is always known (`UsageService.lastRefreshed`),
    /// regardless of which real metrics a provider has or is missing. Used
    /// to top up an even-sized stat fan to an odd one (see `RingView`'s
    /// `outerBubbles`) rather than inventing a per-provider "extra" stat: an
    /// even count has no unambiguous center wedge to select/enlarge, and
    /// this is the one thing every provider can always supply, so it's the
    /// one filler this app ever needs. Low priority by design — it drops
    /// out again the moment the real count is already odd, since it's
    /// meta-info about the fetch, not a metric worth a permanent slot.
    static func syncedBubble(lastRefreshed: Date?, color: Color) -> Bubble {
        let ago = Format.ago(lastRefreshed)
        let big = ago == "just now" ? "Now" : ago.replacingOccurrences(of: " ago", with: "")
        return Bubble(id: "synced", label: "Synced", color: color, icon: .symbol("checkmark.circle"),
                      pct: nil, big: big, sub: "Last synced \(ago)")
    }

    /// All of Claude's stat wedges, fanned at once — Session, Weekly,
    /// Credits, Skills, All-time, whichever have real clean data. No paging:
    /// the fan just grows/shrinks with however many are available. All share
    /// Claude's own brand color — the color identifies the *provider* these
    /// stats belong to, not the individual stat.
    static func claudeMetrics(_ c: ClaudeUsage) -> [Bubble] {
        var list: [Bubble] = []
        list.append(Bubble(id: "session", label: "Session", color: claudeOrange, icon: .symbol("bolt.fill"),
                            pct: c.session, big: c.session != nil ? "\(c.session!)%" : "—",
                            sub: c.sessionReset.map { "Resets \(Format.reset($0) ?? "")" }))
        list.append(Bubble(id: "weekly", label: "Weekly", color: claudeOrange, icon: .symbol("calendar"),
                            pct: c.weekly, big: c.weekly != nil ? "\(c.weekly!)%" : "—",
                            sub: c.weeklyReset.map { "Resets \(Format.reset($0) ?? "")" }))
        if let credits = c.credits, let pct = credits.pct {
            let sub = (credits.spent != nil && credits.total != nil)
                ? String(format: "$%.2f / $%.2f", credits.spent!, credits.total!) : nil
            list.append(Bubble(id: "credits", label: "Credits", color: claudeOrange, icon: .symbol("cylinder.fill"),
                                pct: pct, big: "\(pct)%", sub: sub))
        }
        if let skills = c.skills, !skills.isEmpty {
            let top = skills.max(by: { $0.pct < $1.pct })
            list.append(Bubble(id: "skills", label: "Skills", color: claudeOrange, icon: .symbol("pencil"),
                                pct: top?.pct, big: "\(skills.count)", sub: top.map { "Top: \($0.name) \($0.pct)%" }))
        }
        if let s = c.stats, (s.favoriteModel != nil || s.sessions != nil) {
            list.append(Bubble(id: "stats", label: "All-time", color: claudeOrange, icon: .symbol("clock.fill"),
                                pct: nil, big: s.sessions != nil ? "\(s.sessions!)" : "—",
                                sub: s.favoriteModel.map { "Favorite: \($0)" }))
        }
        return list
    }

    /// Antigravity's quota fan — just the two limits the `agy` CLI's own
    /// `/usage` panel reports (5-hour, weekly), both already converted from
    /// percent-remaining to percent-used. `color` is the caller's own
    /// `Provider.color` rather than a constant here, so this can't drift
    /// from `Provider.all`'s brand color the way a hardcoded hex would.
    static func antigravityMetrics(_ g: GeminiUsage, color: Color) -> [Bubble] {
        var list: [Bubble] = []
        if let pct = g.fiveHourPct {
            list.append(Bubble(id: "fiveHour", label: "5 Hour", color: color, icon: .symbol("clock.fill"),
                                pct: pct, big: "\(pct)%", sub: g.fiveHourReset))
        }
        if let pct = g.weeklyPct {
            list.append(Bubble(id: "weekly", label: "Weekly", color: color, icon: .symbol("calendar"),
                                pct: pct, big: "\(pct)%", sub: g.weeklyReset))
        }
        return list
    }

    /// Codex's quota fan — one wedge per row on its own `/status` panel.
    /// Which rows exist depends on the account's plan (Free shows only a
    /// monthly limit; paid plans add a rolling 5-hour and/or weekly one),
    /// so this maps whatever `codex.limits` actually came back rather than
    /// assuming a fixed set the way Antigravity's two fixed limits do.
    static func codexMetrics(_ c: CodexUsage, color: Color) -> [Bubble] {
        guard let limits = c.limits else { return [] }
        return limits.map { limit in
            let id = codexLimitID(limit.name)
            return Bubble(id: id, label: codexLimitLabel(limit.name), color: color,
                           icon: .symbol(id == "weekly" ? "calendar" : "clock.fill"),
                           pct: limit.pctUsed, big: "\(limit.pctUsed)%",
                           sub: limit.reset.map { "Resets \($0)" })
        }
    }

    /// A stable id for the fixed circular ordering in `RingView` — matched
    /// by content, not exact string, since the panel's own label wording
    /// ("Monthly limit", "5h limit", ...) isn't guaranteed byte-for-byte
    /// across CLI versions.
    private static func codexLimitID(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("5h") || lower.contains("5 h") { return "fiveHour" }
        if lower.contains("weekly") { return "weekly" }
        if lower.contains("monthly") { return "monthly" }
        return name
    }

    private static func codexLimitLabel(_ name: String) -> String {
        switch codexLimitID(name) {
        case "fiveHour": return "5 Hour"
        case "weekly": return "Weekly"
        case "monthly": return "Monthly"
        default: return name.replacingOccurrences(of: " limit", with: "", options: .caseInsensitive)
        }
    }

    /// Cursor's quota fan — one wedge per category row on its own /usage
    /// panel (Included/Auto/API on a Free plan; other plans may show
    /// different categories). All share the one reset date the panel
    /// prints once in its header, unlike Codex where each limit carries
    /// its own.
    static func cursorMetrics(_ c: CursorUsage, color: Color) -> [Bubble] {
        guard let rows = c.rows else { return [] }
        let sub = c.reset.map { "Resets \($0)" }
        return rows.map { row in
            Bubble(id: row.name.lowercased(), label: row.name, color: color,
                   icon: .symbol("gauge"),
                   pct: row.pctUsed, big: "\(row.pctUsed)%", sub: sub)
        }
    }
}
