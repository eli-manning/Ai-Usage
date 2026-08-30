import Foundation

/// Parsers for the three non-Claude provider panels, ported from
/// `parseAgyOutput` / `parseCodexOutput` / `parseCursorOutput` in
/// `os-menu/main.js`.
///
/// All three follow the same contract as their JS originals:
/// - `error == nil` and `signedIn == false` means "the CLI is there, the user
///   just isn't signed in" — never retried, surfaced as a sign-in prompt.
/// - `error != nil` means the drive or the parse genuinely failed — retried
///   once by `UsageService.withRetryOnError` before being believed.
public enum ProviderParsers {

    private static func cleanLines(_ raw: String) -> [String] {
        AnsiGrid.toLines(raw)
            .map { AnsiGrid.stripBoxChars($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Antigravity (`agy`)

    /// The quota panel's bar/percentage is how much is *remaining*, not used —
    /// e.g. "98.68%" full means almost nothing has been used. Every other
    /// provider's pct in this app means percent USED, so this inverts it.
    static func usedPctFromRemaining(_ remainingStr: String) -> Int? {
        guard let remaining = Double(remainingStr) else { return nil }
        return Int((100 - remaining).rounded())
    }

    /// agy's own duration text is always "<N>h <M>m" (e.g. "157h 4m") — never
    /// days, and never correctly pluralized. Re-express in days/hours (falling
    /// back to minutes for anything under an hour), singular/plural per unit.
    static func formatAgyDuration(_ str: String) -> String {
        let h = Pattern(#"(\d+)\s*h"#).firstMatch(str).flatMap { Int($0[1] ?? "") } ?? 0
        let m = Pattern(#"(\d+)\s*m"#).firstMatch(str).flatMap { Int($0[1] ?? "") } ?? 0
        let totalMinutes = h * 60 + m
        guard totalMinutes > 0 else { return str }

        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60
        func unit(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }

        var parts: [String] = []
        if days > 0 { parts.append(unit(days, "day")) }
        if hours > 0 { parts.append(unit(hours, "hour")) }
        if days == 0 && hours == 0 && minutes > 0 { parts.append(unit(minutes, "minute")) }
        return parts.isEmpty ? str : parts.joined(separator: " ")
    }

    private static let agySectionRe = Pattern(
        #"GEMINI MODELS([\s\S]*?)(?:CLAUDE AND GPT MODELS|$)"#)
    private static let agyEmailRe = Pattern(#"[\w.+-]+@[\w-]+\.[\w.-]+"#)
    private static let agyNotSignedInRe = Pattern(#"currently not signed in"#)
    private static let agyWeeklyRe = Pattern(
        #"Weekly Limit[\s\S]*?([\d.]+)%\s*\n\s*(?:([\d.]+)% remaining(?:\s*·\s*Refreshes in ([^\n]+))?|Quota available)"#)
    private static let agyFiveHourRe = Pattern(
        #"Five Hour Limit[\s\S]*?([\d.]+)%\s*\n\s*(?:([\d.]+)% remaining(?:\s*·\s*Refreshes in ([^\n]+))?|Quota available)"#)

    public static func parseAgy(_ raw: String) -> GeminiUsage {
        let lines = cleanLines(raw)
        let text = lines.joined(separator: "\n")

        guard let sectionMatch = agySectionRe.firstMatch(text), let section = sectionMatch[1] else {
            // "not signed in" also flashes during the normal startup handshake
            // (the banner shows it, then it silently signs in from a cached
            // token), so only trust it once we know the quota panel never
            // showed up at all — if an account email did show, sign-in actually
            // succeeded and the panel parse itself just failed.
            let sawAccount = agyEmailRe.matches(text)
            if !sawAccount && agyNotSignedInRe.matches(raw) {
                return GeminiUsage(signedIn: false)
            }
            return GeminiUsage(signedIn: true, error: "Could not find quota panel.")
        }

        // "100% remaining · Refreshes in 157h 4m" — the "Refreshes in …"
        // clause is only present once some quota has actually been consumed; a
        // completely untouched limit just reads "Quota available" with nothing
        // to count down.
        let weeklyMatch = agyWeeklyRe.firstMatch(section)
        let fiveHourMatch = agyFiveHourRe.firstMatch(section)

        let weeklyPct = weeklyMatch.flatMap { usedPctFromRemaining($0[2] ?? $0[1] ?? "") }
        let fiveHourPct = fiveHourMatch.flatMap { usedPctFromRemaining($0[2] ?? $0[1] ?? "") }
        let weeklyReset = weeklyMatch?[3].map {
            "Refreshes in " + formatAgyDuration($0.trimmingCharacters(in: .whitespaces))
        }
        let fiveHourReset = fiveHourMatch?[3].map {
            "Refreshes in " + formatAgyDuration($0.trimmingCharacters(in: .whitespaces))
        }

        return GeminiUsage(
            signedIn: true,
            weeklyPct: weeklyPct,
            fiveHourPct: fiveHourPct,
            weeklyReset: weeklyReset,
            fiveHourReset: fiveHourReset,
            error: weeklyPct == nil && fiveHourPct == nil ? "Could not parse quota." : nil)
    }

    // MARK: - Codex

    /// "Monthly limit:        [] 99% left (resets 20:27 on 30 Aug)" — Free
    /// plans show only a monthly limit; paid plans may add a rolling 5-hour
    /// and/or weekly one, so this scans every "<label>: [...] NN% left" row
    /// rather than assuming a fixed set.
    private static let codexLimitRe = Pattern(
        #"^(.+?limit):\s*\[.*?\]\s*(\d+)%\s*left(?:\s*\(resets\s+([^)]+)\))?$"#,
        options: .caseInsensitive)
    private static let codexAccountRe = Pattern(#"^Account:\s*(\S+)\s*\(([^)]+)\)"#)
    private static let codexSignInRe = Pattern(#"sign in|log ?in"#, options: .caseInsensitive)

    public static func parseCodex(_ raw: String) -> CodexUsage {
        let lines = cleanLines(raw)
        let account = lines.compactMap { codexAccountRe.firstMatch($0) }.first

        guard let account else {
            // A logged-out `codex` blocks on its own sign-in flow (ChatGPT
            // OAuth or an API-key prompt) instead of ever reaching /status, so
            // it can't be driven interactively — same as a logged-out `agy`.
            if codexSignInRe.matches(raw) {
                return CodexUsage(signedIn: false, limits: [])
            }
            return CodexUsage(signedIn: true, limits: [], error: "Could not find status panel.")
        }

        var limits: [CodexLimit] = []
        for line in lines {
            guard let m = codexLimitRe.firstMatch(line), let left = Int(m[2] ?? "") else { continue }
            limits.append(CodexLimit(
                name: (m[1] ?? "").trimmingCharacters(in: .whitespaces),
                pctUsed: 100 - left,
                reset: m[3]?.trimmingCharacters(in: .whitespaces)))
        }

        return CodexUsage(
            signedIn: true,
            plan: (account[2] ?? "").trimmingCharacters(in: .whitespaces),
            limits: limits,
            error: limits.isEmpty ? "Could not parse quota." : nil)
    }

    // MARK: - Cursor

    /// "Usage • Free                        Resets Sep 1" — the plan tier and
    /// the one reset date that applies to every category row below it. Row
    /// shape is "<category>   <optional current-value column>   NN% used" —
    /// which categories exist isn't a documented fixed set (Free shows
    /// Included/Auto/API), so this scans generically.
    private static let cursorHeaderRe = Pattern(#"^Usage\s*[•·]\s*(.+?)\s{2,}Resets\s+(.+)$"#)
    private static let cursorRowRe = Pattern(
        #"^([A-Za-z][\w/ -]*?)\s{2,}.*?(\d+)%\s*used\s*$"#, options: .caseInsensitive)
    private static let cursorSignInRe = Pattern(
        #"sign in|log ?in|not authenticated"#, options: .caseInsensitive)

    public static func parseCursor(_ raw: String) -> CursorUsage {
        let lines = cleanLines(raw)
        let header = lines.compactMap { cursorHeaderRe.firstMatch($0) }.first

        guard let header else {
            if cursorSignInRe.matches(raw) {
                return CursorUsage(signedIn: false, rows: [])
            }
            return CursorUsage(signedIn: true, rows: [], error: "Could not find usage panel.")
        }

        var rows: [CursorUsageRow] = []
        for line in lines {
            guard let m = cursorRowRe.firstMatch(line), let pct = Int(m[2] ?? "") else { continue }
            rows.append(CursorUsageRow(
                name: (m[1] ?? "").trimmingCharacters(in: .whitespaces), pctUsed: pct))
        }

        return CursorUsage(
            signedIn: true,
            plan: (header[1] ?? "").trimmingCharacters(in: .whitespaces),
            reset: (header[2] ?? "").trimmingCharacters(in: .whitespaces),
            rows: rows,
            error: rows.isEmpty ? "Could not parse quota." : nil)
    }
}
