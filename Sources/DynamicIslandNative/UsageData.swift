import Foundation

struct Credits: Codable {
    var pct: Int?
    var spent: Double?
    var total: Double?
    var reset: String?
}

struct NamedPct: Codable, Identifiable {
    var name: String
    var pct: Int
    var id: String { name }
}

struct Stats: Codable {
    var favoriteModel: String?
    var totalTokens: String?
    var sessions: Int?
    var longestSession: String?
    var activeDays: Int?
    var totalDays: Int?
    var longestStreak: String?
    var mostActiveDay: String?
    var currentStreak: String?
    var funFact: String?
}

/// Model quota pulled from the Antigravity CLI's (`agy`) `/usage` panel.
/// `weeklyPct`/`fiveHourPct` are percent USED, already inverted from the
/// panel's own percent-REMAINING display to match every other provider's
/// `pct` convention in this app — see fetch-antigravity-usage.js.
struct GeminiUsage: Codable {
    var signedIn: Bool?
    var weeklyPct: Int?
    var fiveHourPct: Int?
    var weeklyReset: String?
    var fiveHourReset: String?
    var error: String?
}

/// One row off the Codex CLI's `/status` panel (e.g. "Monthly limit: []
/// 99% left ..."). `name` is the row's own label verbatim — which limits
/// exist depends on the account's plan (Free shows just a monthly limit;
/// paid plans add a rolling 5-hour and/or weekly one) — so this is a list
/// rather than fixed fields, and `pctUsed` is already inverted from the
/// panel's percent-*left* display to match every other provider's `pct`
/// convention in this app. See fetch-codex-usage.js.
struct CodexLimit: Codable {
    var name: String
    var pctUsed: Int
    var reset: String?
}

struct CodexUsage: Codable {
    var signedIn: Bool?
    var plan: String?
    var limits: [CodexLimit]?
    var error: String?

    /// The one figure that best represents "quota right now" — the same
    /// rolling-window-first preference every other provider's pill/picker
    /// badge uses (Claude's session, Antigravity's five-hour). Matched by
    /// name fragment rather than fixed fields since which limits exist
    /// depends on plan; Free accounts have no 5-hour/weekly row at all, so
    /// this falls all the way back to whichever single limit they do have.
    var primaryPct: Int? {
        guard let limits, !limits.isEmpty else { return nil }
        let named: (String) -> CodexLimit? = { needle in limits.first { $0.name.lowercased().contains(needle) } }
        return (named("5h") ?? named("weekly") ?? limits.first)?.pctUsed
    }
}

/// One row off the Cursor CLI's `/usage` panel table (Category / Current /
/// Usage — e.g. "Included        0% used"). Which categories a plan shows
/// isn't a fixed, documented set (Free shows Included/Auto/API; other plans
/// may differ), so this is a list rather than fixed fields, same reasoning
/// as `CodexLimit`. See fetch-cursor-usage.js.
struct CursorUsageRow: Codable {
    var name: String
    var pctUsed: Int
}

struct CursorUsage: Codable {
    var signedIn: Bool?
    var plan: String?
    /// The one reset date printed once in the panel's header — applies to
    /// every row, unlike Codex where each limit has its own.
    var reset: String?
    var rows: [CursorUsageRow]?
    var error: String?

    /// The one figure that best represents "quota right now" — same
    /// rolling-window-first spirit as `CodexUsage.primaryPct`, but Cursor's
    /// categories aren't a rolling-window/long-window pair, so this just
    /// prefers whichever row is literally named "Included" (the plan's own
    /// base quota) and falls back to the first row otherwise.
    var primaryPct: Int? {
        guard let rows, !rows.isEmpty else { return nil }
        return (rows.first { $0.name.lowercased() == "included" } ?? rows.first)?.pctUsed
    }
}

struct ClaudeUsage: Codable {
    var session: Int?
    var weekly: Int?
    var sessionReset: String?
    var weeklyReset: String?
    var weeklyPromo: String?
    var credits: Credits?
    var skills: [NamedPct]?
    var mcpServers: [NamedPct]?
    var stats: Stats?
    var error: String?
    var errorType: String?
    var lastUpdated: Date?

    static let empty = ClaudeUsage()
}

/// Connection/fetch state for an account-backed provider.
enum ProviderState: Codable, Equatable {
    case checking
    case installed      // account can be connected in Settings
    case loggedIn        // authenticated; usage data may still be pending
    case unsupported(String)
    case error(String)   // signed in (or was) but the last fetch failed
}

struct ProviderStatus: Codable {
    var state: ProviderState

    func message(installHint _: String) -> String {
        switch state {
        case .checking: return "Checking…"
        case .installed: return "Connect this account in Settings."
        case .loggedIn: return "Connected."
        case .unsupported(let msg): return msg
        case .error(let msg): return "Error: \(msg)"
        }
    }

    /// Compact form for the collapsed pill, where there's only room for a
    /// word or two next to the badge.
    var shortLabel: String {
        switch state {
        case .checking: return "…"
        case .installed: return "sign in"
        case .loggedIn: return "…"
        case .unsupported: return "n/a"
        case .error: return "error"
        }
    }

    /// One-word action label for the status wedge — the full sentence
    /// lives in the tooltip (`message`), this is just what the button says.
    var actionLabel: String {
        switch state {
        case .checking: return "Checking"
        case .installed: return "Sign In"
        case .loggedIn: return "Connected"
        case .unsupported: return "Unavailable"
        case .error: return "Retry"
        }
    }

    var actionIcon: String {
        switch state {
        case .checking: return "ellipsis.circle"
        case .installed: return "person.crop.circle.badge.questionmark"
        case .loggedIn: return "checkmark.circle"
        case .unsupported: return "nosign"
        case .error: return "exclamationmark.triangle"
        }
    }
}
