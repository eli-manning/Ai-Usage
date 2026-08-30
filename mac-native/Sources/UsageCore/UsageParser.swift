import Foundation

/// Parses cleaned Claude Code TUI output (from `/usage` and `/stats`) into
/// structured data — a direct port of `os-menu/usage-parser.js`.
///
/// Claude Code's TUI positions text with absolute cursor moves (column jumps
/// for two-column layouts, e.g. "Favorite model: X    Total tokens: Y")
/// rather than literal spaces. `AnsiGrid.toLines` replays those moves against
/// a virtual grid so the reconstructed lines keep their intended spacing,
/// which the patterns below rely on to split label/value pairs.
public enum UsageParser {

    public static func toCleanLines(_ raw: String) -> [String] {
        AnsiGrid.toLines(raw)
            .map { AnsiGrid.stripBoxChars($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - /usage

    private enum Section {
        case sessionGauge, weeklyGauge, creditsGauge, skills, mcp
    }

    /// `/^(.+?)\s{2,}(\d+)%$/`
    private static let tableRowRe = Pattern(#"^(.+?)\s{2,}(\d+)%$"#)
    /// `/(\d+)%\s*used/i`
    private static let pctUsedRe = Pattern(#"(\d+)%\s*used"#, options: .caseInsensitive)
    /// `/^\$([\d,.]+)\s*\/\s*\$([\d,.]+)\s*spent\s*·\s*Resets\s+(.+)/i`
    private static let creditsRe = Pattern(
        #"^\$([\d,.]+)\s*/\s*\$([\d,.]+)\s*spent\s*·\s*Resets\s+(.+)"#,
        options: .caseInsensitive)

    public static func parseUsage(_ raw: String) -> ClaudeUsage {
        var result = ClaudeUsage()
        var section: Section?

        // The "Session" block up top (Total cost/duration/code changes/Usage
        // by model) describes the one-shot `claude /usage` process we spawn to
        // read this screen, not the user's real terminal session — it's always
        // ~zero and not worth parsing or showing.
        for line in toCleanLines(raw) {
            if line == "Current session" { section = .sessionGauge; continue }
            if line.hasPrefix("Current week") { section = .weeklyGauge; continue }
            if line == "Usage credits" {
                section = .creditsGauge
                if result.credits == nil { result.credits = Credits() }
                continue
            }
            if Pattern(#"^Skills\s+% of usage$"#).matches(line) {
                section = .skills
                result.skills = []
                continue
            }
            if Pattern(#"^MCP servers\s+% of usage$"#).matches(line) {
                section = .mcp
                result.mcpServers = []
                continue
            }

            if let m = pctUsedRe.firstMatch(line), let pct = Int(m[1] ?? "") {
                switch section {
                case .sessionGauge: result.session = pct
                case .weeklyGauge: result.weekly = pct
                case .creditsGauge: result.credits?.pct = pct
                default: break
                }
                continue
            }

            if section == .sessionGauge, Pattern(#"^Resets\s"#, options: .caseInsensitive).matches(line) {
                result.sessionReset = Pattern(#"^Resets\s*"#, options: .caseInsensitive)
                    .replacingFirst(in: line, with: "")
                    .trimmingCharacters(in: .whitespaces)
                continue
            }
            if section == .weeklyGauge {
                if Pattern(#"^Resets\s"#, options: .caseInsensitive).matches(line) {
                    result.weeklyReset = Pattern(#"^Resets\s*"#, options: .caseInsensitive)
                        .replacingFirst(in: line, with: "")
                        .trimmingCharacters(in: .whitespaces)
                    continue
                }
                if Pattern(#"promo"#, options: .caseInsensitive).matches(line) {
                    result.weeklyPromo = line.trimmingCharacters(in: .whitespaces)
                    continue
                }
            }
            if section == .creditsGauge, let m = creditsRe.firstMatch(line) {
                result.credits?.spent = Double((m[1] ?? "").replacingOccurrences(of: ",", with: ""))
                result.credits?.total = Double((m[2] ?? "").replacingOccurrences(of: ",", with: ""))
                result.credits?.reset = (m[3] ?? "").trimmingCharacters(in: .whitespaces)
                continue
            }

            if section == .skills || section == .mcp,
               let m = tableRowRe.firstMatch(line),
               let pct = Int(m[2] ?? "") {
                let entry = NamedPct(
                    name: (m[1] ?? "").trimmingCharacters(in: .whitespaces), pct: pct)
                if section == .skills { result.skills?.append(entry) }
                else { result.mcpServers?.append(entry) }
                continue
            }
        }

        return result
    }

    // MARK: - /stats

    private static let favoriteRe = Pattern(#"^Favorite model:\s*(.+?)\s{2,}Total tokens:\s*(.+)$"#)
    private static let sessionsRe = Pattern(#"^Sessions:\s*(\d+)\s{2,}Longest session:\s*(.+)$"#)
    private static let activeDaysRe = Pattern(#"^Active days:\s*(\d+)/(\d+)\s{2,}Longest streak:\s*(.+)$"#)
    private static let mostActiveRe = Pattern(#"^Most active day:\s*(.+?)\s{2,}Current streak:\s*(.+)$"#)

    /// Returns `nil` for `stats` when nothing matched at all, matching the JS
    /// original's lazily-created `result.stats`.
    public static func parseStats(_ raw: String) -> Stats? {
        var stats = Stats()
        var expectFunFact = false

        for line in toCleanLines(raw) {
            if let m = favoriteRe.firstMatch(line) {
                stats.favoriteModel = (m[1] ?? "").trimmingCharacters(in: .whitespaces)
                stats.totalTokens = (m[2] ?? "").trimmingCharacters(in: .whitespaces)
                continue
            }
            if let m = sessionsRe.firstMatch(line) {
                stats.sessions = Int(m[1] ?? "")
                stats.longestSession = (m[2] ?? "").trimmingCharacters(in: .whitespaces)
                continue
            }
            if let m = activeDaysRe.firstMatch(line) {
                stats.activeDays = Int(m[1] ?? "")
                stats.totalDays = Int(m[2] ?? "")
                stats.longestStreak = (m[3] ?? "").trimmingCharacters(in: .whitespaces)
                continue
            }
            if let m = mostActiveRe.firstMatch(line) {
                stats.mostActiveDay = (m[1] ?? "").trimmingCharacters(in: .whitespaces)
                stats.currentStreak = (m[2] ?? "").trimmingCharacters(in: .whitespaces)
                expectFunFact = true
                continue
            }
            // The trivia line after "Most active day" rotates between templates
            // ("You've used ~Nx more tokens than X", "Your longest session is
            // ~Nx longer than a X", etc.) — rather than chase each wording,
            // just take whatever line comes next, stopping at the footer hint.
            if expectFunFact {
                expectFunFact = false
                if !Pattern(#"^[↓↑]"#).matches(line) {
                    stats.funFact = line.trimmingCharacters(in: .whitespaces)
                }
                continue
            }
        }

        return stats.isEmpty ? nil : stats
    }

    /// Called when a PTY run produced no parseable session/weekly/stats data
    /// at all. A logged-out `claude` doesn't jump straight to a "please log
    /// in" message — it shows the first-run onboarding wizard (theme picker,
    /// "Let's get started") first, and our idle-based capture gets stuck there
    /// (it's an interactive menu, nothing advances without a keypress we don't
    /// send) well before reaching a screen whose text actually contains
    /// "login". So the wizard screen itself is the signal: legitimately
    /// authenticated sessions never see it, since Claude Code only shows
    /// onboarding once.
    public static func classifyNoDataError(_ accumulatedOutput: String) -> (error: String, errorType: String?) {
        // Must check the reconstructed (grid-rendered) text, not the raw ANSI —
        // the raw string still has escape codes sitting between letters
        // ("Welcome\u{1b}[9Gto\u{1b}[12GClaude..."), so a substring search
        // against it never matches even when the rendered text is perfectly
        // readable. Also strip all punctuation, not just whitespace: the
        // wizard's "Let's get started" keeps its apostrophe after
        // whitespace-only stripping, which alone breaks a naive
        // "letsgetstarted" match.
        let clean = toCleanLines(accumulatedOutput).joined(separator: " ")
        let normalized = clean.lowercased().filter { $0.isLetter && $0.isASCII || $0.isNumber }

        let needsSetup = normalized.contains("letsgetstarted")
            || normalized.contains("welcometoclaudecode")
            || normalized.contains("choosethetextstyle")
            || normalized.contains("selectloginmethod")
        let isAuthError = needsSetup
            || Pattern(#"\blogin\b"#, options: .caseInsensitive).matches(clean)
            || Pattern(#"authenticated"#, options: .caseInsensitive).matches(clean)

        if isAuthError {
            return ("Not logged in — run \"claude\" in a terminal to log in.", "auth")
        }
        return ("Could not find usage data in output.", nil)
    }
}
