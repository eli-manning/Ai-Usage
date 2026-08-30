import Foundation

// The data layer, carried over from the notch app's own `UsageData.swift` so
// the existing ring/wedge views keep compiling against it unchanged. Shapes
// deliberately mirror os-menu's `combinedUsagePayload()` field for field —
// that equivalence is what the shared fixture corpus pins down.

public struct Credits: Codable, Equatable, Sendable {
    public var pct: Int?
    public var spent: Double?
    public var total: Double?
    public var reset: String?

    public init(pct: Int? = nil, spent: Double? = nil, total: Double? = nil, reset: String? = nil) {
        self.pct = pct; self.spent = spent; self.total = total; self.reset = reset
    }
}

public struct NamedPct: Codable, Identifiable, Equatable, Sendable {
    public var name: String
    public var pct: Int
    public var id: String { name }

    public init(name: String, pct: Int) { self.name = name; self.pct = pct }
}

public struct Stats: Codable, Equatable, Sendable {
    public var favoriteModel: String?
    public var totalTokens: String?
    public var sessions: Int?
    public var longestSession: String?
    public var activeDays: Int?
    public var totalDays: Int?
    public var longestStreak: String?
    public var mostActiveDay: String?
    public var currentStreak: String?
    public var funFact: String?

    public init() {}

    /// True once any field has been filled — mirrors the JS side's
    /// `result.stats = result.stats || {}` lazy-create, which leaves `stats`
    /// null entirely when nothing matched.
    public var isEmpty: Bool {
        favoriteModel == nil && totalTokens == nil && sessions == nil
            && longestSession == nil && activeDays == nil && totalDays == nil
            && longestStreak == nil && mostActiveDay == nil && currentStreak == nil
            && funFact == nil
    }
}

/// Model quota pulled from the Antigravity CLI's (`agy`) `/usage` panel.
/// `weeklyPct`/`fiveHourPct` are percent USED, already inverted from the
/// panel's own percent-REMAINING display to match every other provider's
/// `pct` convention in this app — see `ProviderParsers.parseAgy`.
public struct GeminiUsage: Codable, Equatable, Sendable {
    public var signedIn: Bool?
    public var weeklyPct: Int?
    public var fiveHourPct: Int?
    public var weeklyReset: String?
    public var fiveHourReset: String?
    public var error: String?
    public var lastUpdated: Date?

    public init(signedIn: Bool? = nil, weeklyPct: Int? = nil, fiveHourPct: Int? = nil,
                weeklyReset: String? = nil, fiveHourReset: String? = nil,
                error: String? = nil, lastUpdated: Date? = nil) {
        self.signedIn = signedIn; self.weeklyPct = weeklyPct; self.fiveHourPct = fiveHourPct
        self.weeklyReset = weeklyReset; self.fiveHourReset = fiveHourReset
        self.error = error; self.lastUpdated = lastUpdated
    }

    /// Same "right now" convention as Claude's session figure — the 5-hour
    /// window is Antigravity's rolling short-term quota, falling back to
    /// weekly if that's all that parsed.
    public var primaryPct: Int? { fiveHourPct ?? weeklyPct }
}

/// One row off the Codex CLI's `/status` panel (e.g. "Monthly limit: []
/// 99% left ..."). `name` is the row's own label verbatim — which limits
/// exist depends on the account's plan (Free shows just a monthly limit;
/// paid plans add a rolling 5-hour and/or weekly one) — so this is a list
/// rather than fixed fields, and `pctUsed` is already inverted from the
/// panel's percent-*left* display to match this app's `pct` convention.
public struct CodexLimit: Codable, Equatable, Identifiable, Sendable {
    public var name: String
    public var pctUsed: Int
    public var reset: String?
    public var id: String { name }

    public init(name: String, pctUsed: Int, reset: String? = nil) {
        self.name = name; self.pctUsed = pctUsed; self.reset = reset
    }
}

public struct CodexUsage: Codable, Equatable, Sendable {
    public var signedIn: Bool?
    public var plan: String?
    public var limits: [CodexLimit]?
    public var error: String?
    public var lastUpdated: Date?

    public init(signedIn: Bool? = nil, plan: String? = nil, limits: [CodexLimit]? = nil,
                error: String? = nil, lastUpdated: Date? = nil) {
        self.signedIn = signedIn; self.plan = plan; self.limits = limits
        self.error = error; self.lastUpdated = lastUpdated
    }

    /// The one figure that best represents "quota right now" — the same
    /// rolling-window-first preference every other provider's pill/picker
    /// badge uses (Claude's session, Antigravity's five-hour). Matched by
    /// name fragment rather than fixed fields since which limits exist
    /// depends on plan; Free accounts have no 5-hour/weekly row at all, so
    /// this falls all the way back to whichever single limit they do have.
    public var primaryPct: Int? {
        guard let limits, !limits.isEmpty else { return nil }
        let named: (String) -> CodexLimit? = { needle in
            limits.first { $0.name.lowercased().contains(needle) }
        }
        return (named("5h") ?? named("weekly") ?? limits.first)?.pctUsed
    }
}

/// One row off the Cursor CLI's `/usage` panel table (Category / Current /
/// Usage — e.g. "Included        0% used"). Which categories a plan shows
/// isn't a fixed, documented set (Free shows Included/Auto/API; other plans
/// may differ), so this is a list rather than fixed fields, same reasoning
/// as `CodexLimit`.
public struct CursorUsageRow: Codable, Equatable, Identifiable, Sendable {
    public var name: String
    public var pctUsed: Int
    public var id: String { name }

    public init(name: String, pctUsed: Int) { self.name = name; self.pctUsed = pctUsed }
}

public struct CursorUsage: Codable, Equatable, Sendable {
    public var signedIn: Bool?
    public var plan: String?
    /// The one reset date printed once in the panel's header — applies to
    /// every row, unlike Codex where each limit has its own.
    public var reset: String?
    public var rows: [CursorUsageRow]?
    public var error: String?
    public var lastUpdated: Date?

    public init(signedIn: Bool? = nil, plan: String? = nil, reset: String? = nil,
                rows: [CursorUsageRow]? = nil, error: String? = nil, lastUpdated: Date? = nil) {
        self.signedIn = signedIn; self.plan = plan; self.reset = reset
        self.rows = rows; self.error = error; self.lastUpdated = lastUpdated
    }

    /// Cursor's categories aren't a rolling-window/long-window pair, so this
    /// just prefers whichever row is literally named "Included" (the plan's
    /// own base quota) and falls back to the first row otherwise.
    public var primaryPct: Int? {
        guard let rows, !rows.isEmpty else { return nil }
        return (rows.first { $0.name.lowercased() == "included" } ?? rows.first)?.pctUsed
    }
}

public struct ClaudeUsage: Codable, Equatable, Sendable {
    public var session: Int?
    public var weekly: Int?
    public var sessionReset: String?
    public var weeklyReset: String?
    public var weeklyPromo: String?
    public var credits: Credits?
    public var skills: [NamedPct]?
    public var mcpServers: [NamedPct]?
    public var stats: Stats?
    public var error: String?
    /// "offline" | "auth" | nil (unclassified) — mirrors `usageData.errorType`.
    public var errorType: String?
    public var lastUpdated: Date?

    public init() {}

    public static let empty = ClaudeUsage()

    /// Whether this fetch produced anything worth showing. `runClaudeCommand`
    /// in os-menu spells this `Object.values(parsed).some(v => v != null)`.
    public var hasAnyData: Bool {
        session != nil || weekly != nil || sessionReset != nil || weeklyReset != nil
            || weeklyPromo != nil || credits != nil || skills != nil
            || mcpServers != nil || stats != nil
    }
}

/// Where a provider stands, from "never looked" to "actively failing." Kept
/// separate from `installed: Bool` so the UI can show a distinct message for
/// each rather than collapsing "not logged in" and "logged in but the fetch
/// broke" into the same generic hint.
public enum ProviderState: Codable, Equatable, Sendable {
    /// Detection hasn't run even once yet (app just launched, first
    /// `refresh()` still in flight) — deliberately distinct from
    /// `.notInstalled` so boot doesn't flash "not installed" for a provider
    /// that's actually installed and signed in, just not checked yet.
    case checking
    case notInstalled
    case installed       // binary detected, not signed in
    case loggedIn        // authenticated; usage data may still be pending
    case error(String)   // signed in (or was) but the last fetch failed
    case disabled        // switched off in Settings — never driven at all
}

public struct ProviderStatus: Codable, Equatable, Sendable {
    public var state: ProviderState
    /// Set alongside a still-`loggedIn` state when the latest fetch failed
    /// but last-known-good numbers are still cached — drives the stale
    /// banner rather than replacing the whole view with an error.
    public var message: String?

    public init(state: ProviderState, message: String? = nil) {
        self.state = state
        self.message = message
    }

    /// Hub copy for this state. `installHint` is the provider's own
    /// `Provider.hint` so the not-installed message stays provider-specific
    /// without every call site having to know it.
    public func message(installHint: String) -> String {
        if let message { return message }
        switch state {
        case .checking: return "Checking…"
        case .notInstalled: return "Not installed. \(installHint)"
        case .installed: return "Detected — not signed in yet."
        case .loggedIn: return "Signed in."
        case .error(let msg): return "Error: \(msg)"
        case .disabled: return "Turned off in Settings."
        }
    }

    /// Compact form for the collapsed pill, where there's only room for a
    /// word or two next to the badge.
    public var shortLabel: String {
        switch state {
        case .checking: return "…"
        case .notInstalled: return "n/a"
        case .installed: return "sign in"
        case .loggedIn: return "…"
        case .error: return "error"
        case .disabled: return "off"
        }
    }

    /// One-word action label for the status wedge — the full sentence lives
    /// in `message`, this is just what the button says.
    public var actionLabel: String {
        switch state {
        case .checking: return "Checking"
        case .notInstalled: return "Install"
        case .installed: return "Sign In"
        case .loggedIn: return "Refresh"
        case .error: return "Retry"
        case .disabled: return "Off"
        }
    }

    public var actionIcon: String {
        switch state {
        case .checking: return "ellipsis.circle"
        case .notInstalled: return "arrow.down.circle"
        case .installed: return "person.crop.circle.badge.questionmark"
        case .loggedIn: return "checkmark.circle"
        case .error: return "exclamationmark.triangle"
        case .disabled: return "moon.zzz"
        }
    }
}
