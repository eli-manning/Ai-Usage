import Foundation

/// Runs the `ptydrive` helper for one provider and parses what comes back.
///
/// This is the layer that replaces `runClaudeCommand` / `runAgyCommand` /
/// `runCodexCommand` / `runCursorCommand` in os-menu's `main.js`. The timeout
/// ladder is carried over intact, because the numbers relate to each other:
/// the helper's own internal cap must expire *before* the watchdog here kills
/// it, so the helper's graceful path — which prints whatever it captured —
/// gets to run instead of being killed mid-capture.
public enum UsageFetcher {

    /// Watchdog per provider, in seconds. Each sits above the corresponding
    /// `PTYSession.DriveSpec.totalTimeout` with room to spare.
    private static func watchdog(for provider: String) -> TimeInterval {
        switch provider {
        case "claude": return 23        // spec cap 20
        case "antigravity": return 62   // spec cap 55
        case "codex": return 28         // spec cap 20
        case "cursor": return 32        // spec cap 25
        default: return 30
        }
    }

    /// Where the helper binary lives. In a packaged `.app` it sits next to the
    /// executable in `Contents/MacOS`; under `swift run` it's beside the app
    /// binary in the build directory. Both are just "next to me", which keeps
    /// this a one-liner in either case — with a couple of explicit fallbacks
    /// for a build laid out differently.
    public static var helperURL: URL? {
        let fm = FileManager.default
        var candidates: [URL] = []

        let exe = Bundle.main.executableURL?.resolvingSymlinksInPath()
        if let dir = exe?.deletingLastPathComponent() {
            candidates.append(dir.appendingPathComponent("ptydrive"))
        }
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("ptydrive"))
        }
        // `swift test` and other hosts where Bundle.main isn't the app.
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        candidates.append(cwd.appendingPathComponent(".build/debug/ptydrive"))
        candidates.append(cwd.appendingPathComponent(".build/release/ptydrive"))

        return candidates.first { fm.isExecutableFile(atPath: $0.path) }
    }

    public enum FetchError: Error, CustomStringConvertible {
        case helperMissing
        case binaryMissing(String)
        case launchFailed(String)
        case timedOut

        public var description: String {
            switch self {
            case .helperMissing:
                return "The ptydrive helper is missing from this build."
            case .binaryMissing(let bin):
                return "Couldn't find \(bin) on your PATH."
            case .launchFailed(let msg):
                return "Process error: \(msg)"
            case .timedOut:
                return "Timed out."
            }
        }
    }

    /// Drives `provider` and returns the raw captured screen.
    ///
    /// Blocking by design — callers run it off the main actor. The watchdog
    /// terminates the helper rather than abandoning it, so a slow CLI can't
    /// leave a PTY subtree running after we've stopped caring about it.
    public static func capture(provider: String, command: String? = nil) throws -> String {
        guard let helper = helperURL else { throw FetchError.helperMissing }
        guard let providerMeta = Provider.byID(provider) else {
            throw FetchError.binaryMissing(provider)
        }
        guard let binary = CLILocator.find(providerMeta.binary) else {
            throw FetchError.binaryMissing(providerMeta.binary)
        }

        let process = Process()
        process.executableURL = helper
        process.arguments = [provider, binary] + (command.map { [$0] } ?? [])
        process.environment = CLILocator.augmentedEnvironment()

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            throw FetchError.launchFailed(error.localizedDescription)
        }

        // Read on a background queue so a helper that fills the 64KB pipe
        // buffer can't deadlock against our own wait.
        var captured = Data()
        let readQueue = DispatchQueue(label: "com.eli.aiusage.fetch.read")
        let readDone = DispatchSemaphore(value: 0)
        readQueue.async {
            captured = outPipe.fileHandleForReading.readDataToEndOfFile()
            readDone.signal()
        }

        let deadline = Date().addingTimeInterval(watchdog(for: provider))
        while process.isRunning && Date() < deadline {
            usleep(50_000)
        }
        if process.isRunning {
            // SIGTERM, not SIGKILL: the helper catches it and still prints its
            // buffer, and its own cleanup reaps the CLI's process group.
            process.terminate()
            // Give it a moment to flush before we give up on the pipe.
            let hardDeadline = Date().addingTimeInterval(3)
            while process.isRunning && Date() < hardDeadline { usleep(50_000) }
        }

        _ = readDone.wait(timeout: .now() + 5)
        errPipe.fileHandleForReading.closeFile()

        return String(decoding: captured, as: UTF8.self)
    }

    // MARK: - Typed fetches

    /// Fetches `/usage` then `/stats` and merges them.
    ///
    /// Sequential, not parallel: running two `claude` PTYs at once risks both
    /// racing the same directory-trust prompt. If `/usage` fails outright,
    /// `/stats` is skipped since it's the less critical of the two.
    public static func fetchClaude() -> ClaudeUsage {
        var usage = withRetryOnError({ () -> ClaudeUsage in
            do {
                let raw = try capture(provider: "claude", command: "/usage")
                var parsed = UsageParser.parseUsage(raw)
                if !parsed.hasAnyData {
                    let classified = UsageParser.classifyNoDataError(raw)
                    parsed.error = classified.error
                    parsed.errorType = classified.errorType
                }
                return parsed
            } catch {
                var failed = ClaudeUsage()
                failed.error = String(describing: error)
                return failed
            }
        }, errorOf: { $0.error })

        // A hard failure on /usage means there's nothing to enrich.
        if usage.error != nil && usage.session == nil && usage.weekly == nil {
            return usage
        }

        let stats = withRetryOnError({ () -> Stats? in
            (try? capture(provider: "claude", command: "/stats")).flatMap(UsageParser.parseStats)
        }, errorOf: { _ in nil })

        usage.stats = stats
        if usage.hasAnyData { usage.lastUpdated = Date() }
        return usage
    }

    public static func fetchAntigravity() -> GeminiUsage {
        withRetryOnError({ () -> GeminiUsage in
            do { return ProviderParsers.parseAgy(try capture(provider: "antigravity")) }
            catch { return GeminiUsage(error: String(describing: error)) }
        }, errorOf: { $0.error })
    }

    public static func fetchCodex() -> CodexUsage {
        withRetryOnError({ () -> CodexUsage in
            do { return ProviderParsers.parseCodex(try capture(provider: "codex")) }
            catch { return CodexUsage(error: String(describing: error)) }
        }, errorOf: { $0.error })
    }

    public static func fetchCursor() -> CursorUsage {
        withRetryOnError({ () -> CursorUsage in
            do { return ProviderParsers.parseCursor(try capture(provider: "cursor")) }
            catch { return CursorUsage(error: String(describing: error)) }
        }, errorOf: { $0.error })
    }

    /// The PTY-driven providers time their own input off idle-detection
    /// heuristics against a real interactive CLI — a slow machine, a cold-start
    /// network round-trip, or a redraw landing at the wrong moment can race
    /// that into a genuine parse/timeout error even though the CLI is
    /// installed and signed in fine. That's different from "not installed" /
    /// "not signed in", which come back with no error at all and are never
    /// retried here; only a real error gets one automatic second attempt
    /// before it's believed.
    static func withRetryOnError<T>(_ fetch: () -> T, errorOf: (T) -> String?) -> T {
        let first = fetch()
        guard errorOf(first) != nil else { return first }
        let second = fetch()
        return errorOf(second) == nil ? second : first
    }
}
