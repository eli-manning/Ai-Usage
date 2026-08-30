import XCTest
@testable import UsageCore

/// The contract between this Swift port and os-menu's JavaScript originals.
///
/// Every `.ansi` fixture is a real screen captured from a real CLI through the
/// real PTY driver. Every `.expected.json` beside it was produced by running
/// os-menu's own `usage-parser.js` / `main.js` parsers over that exact file —
/// not hand-written. So these tests assert the one thing that actually matters
/// after a rewrite: that the two implementations agree.
///
/// This is the guard rail for the one structural risk of going native on macOS
/// while Windows stays on Electron — the parsers are now duplicated in two
/// languages, and they are also the most volatile code in the project, since
/// any change to a CLI's TUI breaks them before anything else. The code stays
/// duplicated; this makes drift *detectable*.
///
/// To refresh after a deliberate parser change, see `make fixtures`.
final class ParserEquivalenceTests: XCTestCase {

    // MARK: - Fixture loading

    private func fixture(_ name: String) throws -> String {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil),
            "missing fixture \(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Decodes both sides to `Any` and compares as normalised JSON, so key
    /// order and `nil`-vs-absent don't produce false failures — the JS side
    /// emits explicit `null`s where Swift simply omits the key.
    private func assertMatchesExpectation<T: Encodable>(
        _ actual: T, _ expectedFixture: String,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let expectedRaw = try fixture(expectedFixture)
        let expected = try JSONSerialization.jsonObject(
            with: Data(expectedRaw.utf8), options: [.fragmentsAllowed])
        let actualData = try JSONEncoder().encode(actual)
        let actualObject = try JSONSerialization.jsonObject(
            with: actualData, options: [.fragmentsAllowed])

        let a = normalise(actualObject)
        let e = normalise(expected)
        XCTAssertEqual(
            describe(a), describe(e),
            "Swift parser disagrees with the JavaScript original", file: file, line: line)
    }

    /// Drops nulls and sorts keys so the two encoders' conventions line up.
    private func normalise(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (k, v) in dict where !(v is NSNull) {
                out[k] = normalise(v)
            }
            return out
        }
        if let array = value as? [Any] {
            return array.map(normalise)
        }
        // JSONSerialization gives back NSNumber for every numeric; compare via
        // a stable string form so 40 and 40.0 don't spuriously differ.
        if let number = value as? NSNumber {
            let d = number.doubleValue
            return d == d.rounded() && abs(d) < 1e15 ? String(Int(d)) : String(d)
        }
        return value
    }

    private func describe(_ value: Any) -> String {
        if let dict = value as? [String: Any] {
            return "{" + dict.keys.sorted().map { "\($0):\(describe(dict[$0]!))" }
                .joined(separator: ",") + "}"
        }
        if let array = value as? [Any] {
            return "[" + array.map(describe).joined(separator: ",") + "]"
        }
        return "\(value)"
    }

    // MARK: - Parser equivalence

    func testClaudeUsageMatchesJavaScript() throws {
        let parsed = UsageParser.parseUsage(try fixture("claude-usage.ansi"))
        try assertMatchesExpectation(parsed, "claude-usage.expected.json")
    }

    func testClaudeStatsMatchesJavaScript() throws {
        let parsed = UsageParser.parseStats(try fixture("claude-stats.ansi"))
        try assertMatchesExpectation(XCTUnwrap(parsed), "claude-stats.expected.json")
    }

    func testAntigravityMatchesJavaScript() throws {
        let parsed = ProviderParsers.parseAgy(try fixture("antigravity-usage.ansi"))
        try assertMatchesExpectation(parsed, "antigravity-usage.expected.json")
    }

    func testCursorMatchesJavaScript() throws {
        let parsed = ProviderParsers.parseCursor(try fixture("cursor-usage.ansi"))
        try assertMatchesExpectation(parsed, "cursor-usage.expected.json")
    }

    // MARK: - Spot checks on the real captures
    //
    // Equivalence alone would pass if *both* implementations broke the same
    // way, so a few values are also asserted outright.

    func testClaudeUsageExtractsRealValues() throws {
        let u = UsageParser.parseUsage(try fixture("claude-usage.ansi"))
        XCTAssertEqual(u.session, 69)
        XCTAssertEqual(u.weekly, 21)
        XCTAssertEqual(u.sessionReset, "10:30pm (America/Los_Angeles)")
        XCTAssertEqual(u.credits?.pct, 98)
        XCTAssertEqual(u.credits?.spent, 39.48)
        XCTAssertEqual(u.credits?.total, 40)
        XCTAssertEqual(u.mcpServers?.first?.name, "claude-in-chrome")
        XCTAssertTrue(u.hasAnyData)
    }

    func testCursorExtractsRealValues() throws {
        let c = ProviderParsers.parseCursor(try fixture("cursor-usage.ansi"))
        XCTAssertEqual(c.plan, "Free")
        XCTAssertEqual(c.reset, "Sep 1")
        XCTAssertEqual(c.rows?.map(\.name), ["Included", "Auto", "API"])
        XCTAssertNil(c.error)
        // "Included" is the row `primaryPct` is specified to prefer.
        XCTAssertEqual(c.primaryPct, 0)
    }
}

/// Regression tests for the grid renderer itself, pinning the behaviours that
/// were actually wrong at some point rather than restating the implementation.
final class AnsiGridTests: XCTestCase {

    /// The bug that made the Cursor parser silently return "Could not find
    /// usage panel" while Claude's worked fine.
    ///
    /// Swift's `Character` is an extended grapheme cluster and CRLF is *one*
    /// cluster, so a `Character`-based renderer never sees a `\n` in CRLF
    /// output — the row never advances and the pair lands in the grid as
    /// printable text. Cursor's TUI emits CRLF; Claude's does not.
    func testCRLFAdvancesExactlyOneRow() {
        XCTAssertEqual(AnsiGrid.toLines("a\r\nb"), ["a", "b"])
        XCTAssertEqual(AnsiGrid.toLines("a\nb"), ["a", "b"])
        XCTAssertEqual(AnsiGrid.toLines("a\r\n\r\nb"), ["a", "", "b"])
    }

    /// Absolute cursor moves are the whole reason this renderer exists: a
    /// naive escape-stripper collapses the gap and joins the two columns.
    func testAbsoluteColumnMovePreservesGap() {
        let raw = "Favorite model: Sonnet 5\u{1b}[42GTotal tokens: 23.7m"
        let line = AnsiGrid.toLines(raw)[0]
        XCTAssertTrue(line.contains("Sonnet 5"))
        XCTAssertTrue(line.contains("Total tokens: 23.7m"))
        // Two or more spaces between the columns is exactly what the /stats
        // patterns key off (`\s{2,}`).
        XCTAssertTrue(line.contains("  "), "column gap was collapsed")
    }

    func testEraseInLineClearsOnlyThatRow() {
        // Write two rows, then erase the whole first one.
        let raw = "hello\r\nworld\u{1b}[1;1H\u{1b}[2K"
        XCTAssertEqual(AnsiGrid.toLines(raw), ["", "world"])
    }

    /// `ED` erases the screen but deliberately does *not* move the cursor —
    /// text written straight afterwards stays at the column it was already on.
    /// Verified against the JS original, which renders this identically.
    func testEraseDisplayClearsTextButNotTheCursor() {
        XCTAssertEqual(AnsiGrid.toLines("junk\u{1b}[2Jok"), ["    ok"])
        // Real TUIs pair it with an explicit home, which is what resets both.
        XCTAssertEqual(AnsiGrid.toLines("junk\u{1b}[2J\u{1b}[Hok"), ["ok"])
    }

    /// A CSI this parser doesn't recognise (`\u{1b}[>1u`) must fall through to
    /// the two-unit escape skip, leaving its tail as literal text — matching
    /// the JS original, whose regex fails the same way. Getting this wrong
    /// shifts every subsequent column.
    func testUnrecognisedCSILeavesTailAsText() {
        XCTAssertEqual(AnsiGrid.toLines("\u{1b}[>1uX"), [">1uX"])
    }

    func testOSCSequencesAreSkipped() {
        XCTAssertEqual(AnsiGrid.toLines("\u{1b}]0;window title\u{07}body"), ["body"])
        XCTAssertEqual(AnsiGrid.toLines("\u{1b}]11;?\u{1b}\\body"), ["body"])
    }

    func testPrivateModeTogglesHaveNoTextEffect() {
        XCTAssertEqual(AnsiGrid.toLines("\u{1b}[?25lvisible\u{1b}[?25h"), ["visible"])
    }

    func testTrailingWhitespaceIsTrimmedButLeadingIsNot() {
        // Leading space matters — the panel border strips to a leading space,
        // and `toCleanLines` is what trims it, not the renderer.
        XCTAssertEqual(AnsiGrid.toLines("\u{1b}[3Gx"), ["  x"])
    }

    func testStripBoxCharsLeavesContent() {
        XCTAssertEqual(AnsiGrid.stripBoxChars("│ Usage │"), " Usage ")
        XCTAssertEqual(AnsiGrid.stripBoxChars("░▒▓50%"), "50%")
    }
}

/// The unit conversions that sit between a panel's own wording and this app's
/// "percent used" convention.
final class ConversionTests: XCTestCase {

    /// Antigravity's panel reports percent *remaining*; every other provider
    /// in this app reports percent used.
    func testAgyRemainingIsInvertedToUsed() {
        XCTAssertEqual(ProviderParsers.usedPctFromRemaining("98.68"), 1)
        XCTAssertEqual(ProviderParsers.usedPctFromRemaining("100"), 0)
        XCTAssertEqual(ProviderParsers.usedPctFromRemaining("0"), 100)
        XCTAssertNil(ProviderParsers.usedPctFromRemaining("n/a"))
    }

    /// agy only ever prints "<N>h <M>m", never days, and never pluralises
    /// correctly.
    func testAgyDurationIsRewrittenInDaysAndHours() {
        XCTAssertEqual(ProviderParsers.formatAgyDuration("157h 4m"), "6 days 13 hours")
        XCTAssertEqual(ProviderParsers.formatAgyDuration("1h 0m"), "1 hour")
        XCTAssertEqual(ProviderParsers.formatAgyDuration("24h 0m"), "1 day")
        XCTAssertEqual(ProviderParsers.formatAgyDuration("0h 30m"), "30 minutes")
        XCTAssertEqual(ProviderParsers.formatAgyDuration("0h 1m"), "1 minute")
    }

    /// Codex reports percent *left* per row; the model stores percent used.
    func testCodexLimitsAreInverted() {
        let raw = """
            Account: user@example.com (Plus)
            5h limit:        [####] 40% left (resets 20:27 on 30 Aug)
            Weekly limit:    [##  ] 90% left
            """
        let parsed = ProviderParsers.parseCodex(raw)
        XCTAssertEqual(parsed.plan, "Plus")
        XCTAssertEqual(parsed.limits?.count, 2)
        XCTAssertEqual(parsed.limits?[0].pctUsed, 60)
        XCTAssertEqual(parsed.limits?[0].reset, "20:27 on 30 Aug")
        XCTAssertEqual(parsed.limits?[1].pctUsed, 10)
        // The rolling 5-hour window wins over weekly.
        XCTAssertEqual(parsed.primaryPct, 60)
    }

    /// A Free plan has no 5h/weekly row at all, so `primaryPct` has to fall all
    /// the way back to whichever single limit does exist.
    func testCodexFreePlanFallsBackToItsOnlyLimit() {
        let raw = """
            Account: user@example.com (Free)
            Monthly limit:   [#   ] 99% left
            """
        XCTAssertEqual(ProviderParsers.parseCodex(raw).primaryPct, 1)
    }
}

/// The distinction that decides whether a failed fetch is retried, and whether
/// it is allowed to blank out data already on screen.
final class ErrorClassificationTests: XCTestCase {

    /// A logged-out `claude` shows first-run onboarding, not a "please log in"
    /// message — the idle-based capture gets stuck on that interactive menu
    /// long before reaching any screen containing the word "login". The wizard
    /// screen itself is therefore the signal.
    func testOnboardingScreenIsClassifiedAsAuth() {
        let wizard = "Welcome to Claude Code\r\nLet's get started\r\nChoose the text style"
        XCTAssertEqual(UsageParser.classifyNoDataError(wizard).errorType, "auth")
    }

    func testApostropheDoesNotDefeatTheWizardMatch() {
        // "Let's get started" survives whitespace-only stripping with its
        // apostrophe intact, which alone broke a naive match.
        XCTAssertEqual(UsageParser.classifyNoDataError("Let's get started").errorType, "auth")
    }

    func testUnrecognisedFailureIsNotClaimedToBeAuth() {
        let garbage = "some unrelated terminal noise"
        let result = UsageParser.classifyNoDataError(garbage)
        XCTAssertNil(result.errorType)
        XCTAssertEqual(result.error, "Could not find usage data in output.")
    }

    /// "not signed in" must come back with no error at all, so the retry logic
    /// leaves it alone — retrying a sign-in prompt just wastes 30 seconds.
    func testNotSignedInIsNotAnError() {
        let agy = ProviderParsers.parseAgy("You are currently not signed in")
        XCTAssertEqual(agy.signedIn, false)
        XCTAssertNil(agy.error)

        let cursor = ProviderParsers.parseCursor("Please sign in to continue")
        XCTAssertEqual(cursor.signedIn, false)
        XCTAssertNil(cursor.error)
    }

    /// A transient "not signed in" flashes during agy's normal startup
    /// handshake before a cached token silently signs in. If an account email
    /// showed up, sign-in actually succeeded and only the panel parse failed —
    /// which is a retryable error, not a sign-in prompt.
    func testAgyTrustsAnAccountEmailOverATransientNotSignedIn() {
        let raw = "currently not signed in\r\nuser@example.com\r\n"
        let parsed = ProviderParsers.parseAgy(raw)
        XCTAssertNotEqual(parsed.signedIn, false)
        XCTAssertNotNil(parsed.error)
    }

    /// Only a real error is retried; a sign-in prompt is believed first time.
    func testRetryOnlyFiresForRealErrors() {
        var attempts = 0
        let retried = UsageFetcher.withRetryOnError({ () -> GeminiUsage in
            attempts += 1
            return GeminiUsage(fiveHourPct: 12, error: attempts == 1 ? "Timed out." : nil)
        }, errorOf: { $0.error })
        XCTAssertEqual(attempts, 2)
        XCTAssertNil(retried.error)

        attempts = 0
        _ = UsageFetcher.withRetryOnError({ () -> GeminiUsage in
            attempts += 1
            return GeminiUsage(signedIn: false)
        }, errorOf: { $0.error })
        XCTAssertEqual(attempts, 1, "a sign-in prompt must not be retried")
    }
}

/// History collapsing — the rule that keeps a refresh burst from eating the
/// window's sample budget.
final class HistoryTests: XCTestCase {

    func testChartWindowsMatchTheirCycles() {
        XCTAssertEqual(ChartMode.session.window, 24 * 60 * 60)
        XCTAssertEqual(ChartMode.weekly.window, 7 * 24 * 60 * 60)
    }
}
