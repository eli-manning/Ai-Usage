import Foundation
import Combine

@MainActor
final class UsageService: ObservableObject {
    @Published var claude: ClaudeUsage = .empty
    @Published var antigravity: GeminiUsage?
    @Published var codex: CodexUsage?
    @Published var cursor: CursorUsage?
    @Published var providers: [String: ProviderStatus] = [:]
    @Published var isRefreshing = false
    /// When the current refresh cycle finished, independent of which
    /// provider(s) it actually had new data for — this backs the generic
    /// "Synced" filler wedge (`Bubble.syncedBubble`), which every provider's
    /// fan can use regardless of what real metrics it has.
    @Published var lastRefreshed: Date?

    private var timer: Timer?
    private let scriptPath: String
    private let antigravityScriptPath: String
    private let codexScriptPath: String
    private let cursorScriptPath: String

    init() {
        // scripts/*.js sit next to the executable in dev (swift run resolves
        // relative to the package root's working directory).
        scriptPath = Self.resolveScriptPath("fetch-usage.js")
        antigravityScriptPath = Self.resolveScriptPath("fetch-antigravity-usage.js")
        codexScriptPath = Self.resolveScriptPath("fetch-codex-usage.js")
        cursorScriptPath = Self.resolveScriptPath("fetch-cursor-usage.js")
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    private static func resolveScriptPath(_ name: String) -> String {
        let candidates = [
            FileManager.default.currentDirectoryPath + "/scripts/" + name,
            Bundle.main.bundlePath + "/Contents/Resources/scripts/" + name,
        ]
        return candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) ?? candidates[0]
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        async let usage = fetchClaudeUsage()
        async let detected = detectProviders()
        let (usageResult, providerResult) = await (usage, detected)

        applyClaudeUsage(usageResult)
        var newProviders = providerResult

        // Claude's own status, refined from the same `which`-based
        // baseline (installed/notInstalled) `detectProviders` already
        // gave it: real session/weekly data means actually signed in; an
        // auth-type error means the CLI is there but not signed in; any
        // other error while otherwise detected as installed surfaces as a
        // real error rather than silently staying on the stale baseline.
        // Claude's own ring/pill don't currently consult this (see
        // `Provider.all`'s comment on it), but it keeps the status honest
        // for the day something does, or for a machine where `claude`
        // genuinely isn't installed/signed in yet.
        if claude.session != nil || claude.weekly != nil {
            newProviders["claude"] = ProviderStatus(state: .loggedIn)
        } else if claude.errorType == "auth" {
            newProviders["claude"] = ProviderStatus(state: .installed)
        } else if let err = claude.error, newProviders["claude"]?.state == .installed {
            newProviders["claude"] = ProviderStatus(state: .error(err))
        }

        // Only the CLI itself can tell us whether it's actually signed in
        // and what the real quota is — `which agy`/`which codex` just prove
        // the binary exists, so these run after detection and only for
        // whichever ones detection found installed, in parallel with each
        // other since neither depends on the other. Snapshotting the two
        // flags into `let`s first (rather than reading `newProviders`
        // straight from inside the `async let` initializers) is what keeps
        // this out of Swift 6's "mutable var captured by concurrent code"
        // error — `newProviders` itself gets mutated below.
        let antigravityInstalled = newProviders["antigravity"]?.state == .installed
        let codexInstalled = newProviders["codex"]?.state == .installed
        let cursorInstalled = newProviders["cursor"]?.state == .installed
        async let antigravityResult: GeminiUsage? = antigravityInstalled
            ? await withRetryOnError(fetchAntigravityUsage, errorOf: { $0.error }) : nil
        async let codexResult: CodexUsage? = codexInstalled
            ? await withRetryOnError(fetchCodexUsage, errorOf: { $0.error }) : nil
        async let cursorResult: CursorUsage? = cursorInstalled
            ? await withRetryOnError(fetchCursorUsage, errorOf: { $0.error }) : nil
        let (agyResult, codexRes, cursorRes) = await (antigravityResult, codexResult, cursorResult)

        if let result = agyResult {
            if let err = result.error {
                // A transient failure (agy hiccuped, the PTY drive timed
                // out) shouldn't blank out wedges that were showing real
                // percentages a moment ago — keep `antigravity` as-is
                // and just surface the error in provider state. Same
                // reasoning as `applyClaudeUsage` below.
                newProviders["antigravity"] = ProviderStatus(state: .error(err))
            } else if result.signedIn == false {
                antigravity = result
                newProviders["antigravity"] = ProviderStatus(state: .installed)
            } else {
                antigravity = result
                newProviders["antigravity"] = ProviderStatus(state: .loggedIn)
            }
        }
        if let result = codexRes {
            if let err = result.error {
                newProviders["codex"] = ProviderStatus(state: .error(err))
            } else if result.signedIn == false {
                codex = result
                newProviders["codex"] = ProviderStatus(state: .installed)
            } else {
                codex = result
                newProviders["codex"] = ProviderStatus(state: .loggedIn)
            }
        }
        if let result = cursorRes {
            if let err = result.error {
                newProviders["cursor"] = ProviderStatus(state: .error(err))
            } else if result.signedIn == false {
                cursor = result
                newProviders["cursor"] = ProviderStatus(state: .installed)
            } else {
                cursor = result
                newProviders["cursor"] = ProviderStatus(state: .loggedIn)
            }
        }
        providers = newProviders
        lastRefreshed = Date()
    }

    /// Ports the same caching rule `os-menu/main.js`'s `applyUsageData` uses
    /// for the tray app: a fetch that came back as pure error (offline, CLI
    /// hiccup, timed out) shouldn't blank real percentages that were showing
    /// a moment ago — keep the last good `claude` on screen and just record
    /// the error alongside it. Only a fetch that actually returned data
    /// (session/weekly present) replaces it wholesale.
    private func applyClaudeUsage(_ data: ClaudeUsage?) {
        guard let data else { return }
        let isFailure = data.error != nil && data.session == nil && data.weekly == nil && data.stats == nil
        if isFailure {
            claude.error = data.error
            claude.errorType = data.errorType
            return
        }
        claude = data
    }

    /// The PTY-driven providers (Antigravity/Codex/Cursor) time their own
    /// input off idle-detection heuristics against a real interactive CLI —
    /// a slow machine, a cold-start network round-trip, or a redraw
    /// landing at the wrong moment can race that and come back with a
    /// genuine parse/timeout error even though the CLI itself is perfectly
    /// installed and signed in. That's a different situation from "not
    /// installed"/"not signed in", which come back with `error == nil` and
    /// are never retried here — only an actual `error` gets a second
    /// attempt, once, before it's surfaced as a real failure.
    private func withRetryOnError<T>(_ fetch: () async -> T?, errorOf: (T) -> String?) async -> T? {
        guard let first = await fetch() else { return nil }
        guard errorOf(first) != nil else { return first }
        return await fetch() ?? first
    }

    private func fetchAntigravityUsage() async -> GeminiUsage? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["node", antigravityScriptPath]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: try? JSONDecoder().decode(GeminiUsage.self, from: data))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    private func fetchCodexUsage() async -> CodexUsage? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["node", codexScriptPath]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: try? JSONDecoder().decode(CodexUsage.self, from: data))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    private func fetchCursorUsage() async -> CursorUsage? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["node", cursorScriptPath]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: try? JSONDecoder().decode(CursorUsage.self, from: data))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    private func fetchClaudeUsage() async -> ClaudeUsage? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["node", scriptPath]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .millisecondsSince1970
                if var parsed = try? decoder.decode(ClaudeUsage.self, from: data) {
                    if parsed.session != nil || parsed.weekly != nil {
                        parsed.lastUpdated = Date()
                    }
                    continuation.resume(returning: parsed)
                } else {
                    continuation.resume(returning: nil)
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    /// Detection comes straight off each `Provider`'s own `loginCommand` via
    /// `which` — no separate lookup table to keep in sync with `Provider.all`
    /// as providers are added. Claude included: it gets the same
    /// installed/notInstalled baseline as everyone else here, which
    /// `refresh()` then refines using the real fetch result the same way
    /// it already does for the others.
    private func detectProviders() async -> [String: ProviderStatus] {
        var result: [String: ProviderStatus] = [:]
        for provider in Provider.all {
            // `loginCommand` can be more than a bare binary name (Cursor's
            // is "cursor-agent login") — `which` needs just the binary, so
            // this takes the first token rather than assuming the whole
            // string names an executable.
            let bin = provider.loginCommand?.split(separator: " ").first.map(String.init)
            let installed = bin.map(Self.which) ?? false
            result[provider.id] = ProviderStatus(state: installed ? .installed : .notInstalled)
        }
        return result
    }

    /// A GUI-launched app's `Process` inherits a bare-bones PATH (roughly
    /// `/usr/bin:/bin:/usr/sbin:/sbin` plus whatever `/etc/paths.d` adds
    /// system-wide for Homebrew) — nothing a shell rc file adds only for
    /// interactive shells, like `~/.local/bin` (where `cursor-agent`/`agent`
    /// actually live), ever makes it in. Every spot that shells out to a
    /// CLI the user installed themselves needs this same augmentation.
    private static func augmentedEnv() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", NSHomeDirectory() + "/.local/bin"]
        env["PATH"] = extra.joined(separator: ":") + ":" + (env["PATH"] ?? "")
        return env
    }

    private static func which(_ bin: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", bin]
        process.environment = augmentedEnv()
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
