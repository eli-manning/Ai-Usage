import Combine
import Foundation

/// The single owner of every fetch.
///
/// Both shells — the status item and the notch panel — observe this same
/// instance. That's the whole reason the native rebuild can drop the stdio
/// helper protocol the Electron-hosted design needed: there is one process,
/// one refresh loop, and no second copy of the data to drift.
///
/// The published surface is deliberately unchanged from the notch app's
/// original `UsageService`, so the existing ring/wedge views compile against it
/// untouched.
@MainActor
public final class UsageService: ObservableObject {

    @Published public private(set) var claude: ClaudeUsage = .empty
    @Published public private(set) var antigravity: GeminiUsage?
    @Published public private(set) var codex: CodexUsage?
    @Published public private(set) var cursor: CursorUsage?
    @Published public private(set) var providers: [String: ProviderStatus] = [:]
    @Published public private(set) var isRefreshing = false

    /// When the current refresh cycle finished, independent of which
    /// provider(s) it actually had new data for — this backs the generic
    /// "Synced" filler wedge, which every provider's fan can use regardless of
    /// what real metrics it has.
    @Published public private(set) var lastRefreshed: Date?

    /// Bumped whenever settings change in a way the shells should redraw for.
    @Published public private(set) var settingsRevision = 0

    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?

    public static let pollInterval: TimeInterval = 5 * 60

    public init() {
        // Nothing is `.checking` until we say so — an empty dictionary is what
        // lets a shell tell "haven't looked yet" apart from "looked, and it's
        // not installed".
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    deinit { timer?.invalidate() }

    // MARK: - Refresh

    /// Runs one full cycle: Claude and the other three, concurrently.
    ///
    /// Re-entrancy is guarded rather than queued — a manual refresh landing
    /// while the 5-minute poll is already in flight would otherwise spawn a
    /// second concurrent PTY drive contending over the same CLI session and
    /// auth state, which was a real contributor to intermittent
    /// "Could not find quota panel" failures.
    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer {
            isRefreshing = false
            lastRefreshed = Date()
        }

        async let claudeResult = Self.fetchClaudeOffMain(enabled: Settings.shared.isEnabled("claude"))
        async let otherResults = Self.fetchOthersOffMain()

        let (claudeValue, others) = await (claudeResult, otherResults)

        applyClaude(claudeValue)
        applyOthers(others)
    }

    /// Refreshes exactly one provider — used when a provider is switched back
    /// on in Settings, so it starts reporting immediately rather than waiting
    /// out the rest of the poll interval.
    public func refreshProvider(_ id: String) async {
        guard Settings.shared.isEnabled(id) else { return }
        switch id {
        case "claude":
            let value = await Self.fetchClaudeOffMain(enabled: true)
            applyClaude(value)
        default:
            var partial = OtherResults()
            switch id {
            case "antigravity":
                partial.antigravity = await Self.run { UsageFetcher.fetchAntigravity() }
            case "codex":
                partial.codex = await Self.run { UsageFetcher.fetchCodex() }
            case "cursor":
                partial.cursor = await Self.run { UsageFetcher.fetchCursor() }
            default: break
            }
            partial.detected = Self.detect()
            applyOthers(partial)
        }
        lastRefreshed = Date()
    }

    // MARK: - Detection

    /// Detection only proves the binary exists — it says nothing about whether
    /// the user is actually signed in, so `.installed` (not `.loggedIn`) is the
    /// most any of these can claim without actually driving the CLI.
    nonisolated private static func detect() -> [String: ProviderStatus] {
        var result: [String: ProviderStatus] = [:]
        for provider in Provider.all {
            guard Settings.shared.isEnabled(provider.id) else {
                result[provider.id] = ProviderStatus(state: .disabled)
                continue
            }
            let installed = CLILocator.isInstalled(provider.binary)
            result[provider.id] = ProviderStatus(
                state: installed ? .installed : .notInstalled,
                message: installed ? nil : provider.hint)
        }
        return result
    }

    // MARK: - Off-main fetch plumbing
    //
    // Every fetch blocks on a subprocess for tens of seconds, so none of it may
    // touch the main actor. These hop to a utility queue and hop back with a
    // plain value.

    private struct OtherResults: Sendable {
        var detected: [String: ProviderStatus] = [:]
        var antigravity: GeminiUsage?
        var codex: CodexUsage?
        var cursor: CursorUsage?
    }

    nonisolated private static func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: work())
            }
        }
    }

    nonisolated private static func fetchClaudeOffMain(enabled: Bool) async -> ClaudeUsage? {
        guard enabled else { return nil }
        return await run {
            guard Reachability.isOnline() else {
                var offline = ClaudeUsage()
                offline.error = "You're offline."
                offline.errorType = "offline"
                return offline
            }
            return UsageFetcher.fetchClaude()
        }
    }

    nonisolated private static func fetchOthersOffMain() async -> OtherResults {
        let detected = await run { detect() }
        var results = OtherResults()
        results.detected = detected

        // Only actually drive whichever CLIs detection found installed, and do
        // those in parallel with each other since none depends on the others.
        async let agy: GeminiUsage? = detected["antigravity"]?.state == .installed
            ? await run { UsageFetcher.fetchAntigravity() } : nil
        async let cdx: CodexUsage? = detected["codex"]?.state == .installed
            ? await run { UsageFetcher.fetchCodex() } : nil
        async let csr: CursorUsage? = detected["cursor"]?.state == .installed
            ? await run { UsageFetcher.fetchCursor() } : nil

        let (a, c, u) = await (agy, cdx, csr)
        results.antigravity = a
        results.codex = c
        results.cursor = u
        return results
    }

    // MARK: - Applying results

    /// A fetch that came back as pure error (offline, CLI hiccup, timed out)
    /// shouldn't blank real percentages that were showing a moment ago — keep
    /// the last good reading on screen and just record the error alongside it.
    /// Only a fetch that actually returned data replaces it wholesale.
    private func applyClaude(_ data: ClaudeUsage?) {
        guard let data else { return }

        let isFailure = data.error != nil && data.session == nil
            && data.weekly == nil && data.stats == nil
        if isFailure {
            claude.error = data.error
            claude.errorType = data.errorType
            // Claude's own status, refined from the `which`-based baseline:
            // an auth-type error means the CLI is there but not signed in.
            if data.errorType == "auth" {
                providers["claude"] = ProviderStatus(state: .installed)
            } else if providers["claude"]?.state == .installed, let err = data.error {
                providers["claude"] = ProviderStatus(state: .error(err), message: err)
            }
            return
        }

        claude = data
        if data.session != nil || data.weekly != nil {
            providers["claude"] = ProviderStatus(state: .loggedIn, message: data.error)
            HistoryStore.shared.record(session: data.session, weekly: data.weekly)
        }
    }

    private func applyOthers(_ results: OtherResults) {
        var status = providers.merging(results.detected) { _, new in new }

        if let result = results.antigravity {
            let hasCached = antigravity?.fiveHourPct != nil || antigravity?.weeklyPct != nil
            status["antigravity"] = Self.resolve(
                error: result.error, signedIn: result.signedIn, hasCachedData: hasCached)
            if result.error == nil, result.signedIn != false {
                var stored = result
                stored.lastUpdated = Date()
                antigravity = stored
            } else if result.error == nil {
                antigravity = result
            }
        }

        if let result = results.codex {
            let hasCached = !(codex?.limits?.isEmpty ?? true)
            status["codex"] = Self.resolve(
                error: result.error, signedIn: result.signedIn, hasCachedData: hasCached)
            if result.error == nil, result.signedIn != false {
                var stored = result
                stored.lastUpdated = Date()
                codex = stored
            } else if result.error == nil {
                codex = result
            }
        }

        if let result = results.cursor {
            let hasCached = !(cursor?.rows?.isEmpty ?? true)
            status["cursor"] = Self.resolve(
                error: result.error, signedIn: result.signedIn, hasCachedData: hasCached)
            if result.error == nil, result.signedIn != false {
                var stored = result
                stored.lastUpdated = Date()
                cursor = stored
            } else if result.error == nil {
                cursor = result
            }
        }

        providers = status
    }

    /// The shared rule for turning a fetch result into a status.
    ///
    /// A transient failure shouldn't drop a tab back to an error screen when
    /// real percentages are already cached — stay `.loggedIn` and carry the
    /// error as a `message`, which the shells render as a stale banner over
    /// otherwise-valid data.
    nonisolated private static func resolve(error: String?, signedIn: Bool?, hasCachedData: Bool) -> ProviderStatus {
        if let error {
            return hasCachedData
                ? ProviderStatus(state: .loggedIn, message: error)
                : ProviderStatus(state: .error(error), message: error)
        }
        if signedIn == false { return ProviderStatus(state: .installed) }
        return ProviderStatus(state: .loggedIn)
    }

    // MARK: - Settings changes

    /// Toggling a provider should take effect immediately rather than waiting
    /// up to five minutes for the next poll.
    public func setProviderEnabled(_ id: String, _ enabled: Bool) async {
        Settings.shared.setEnabled(id, enabled)
        settingsRevision += 1

        if enabled {
            await refreshProvider(id)
        } else {
            providers[id] = ProviderStatus(state: .disabled)
            switch id {
            case "antigravity": antigravity = nil
            case "codex": codex = nil
            case "cursor": cursor = nil
            case "claude": claude = .empty
            default: break
            }
        }
    }

    // MARK: - Convenience for the shells

    public func status(_ id: String) -> ProviderStatus {
        providers[id] ?? ProviderStatus(state: .checking)
    }

    /// The one figure that best represents "quota right now" for a provider,
    /// or `nil` when there isn't one to show yet.
    public func primaryPct(_ id: String) -> Int? {
        switch id {
        case "claude": return claude.session ?? claude.weekly
        case "antigravity": return status(id).state == .loggedIn ? antigravity?.primaryPct : nil
        case "codex": return status(id).state == .loggedIn ? codex?.primaryPct : nil
        case "cursor": return status(id).state == .loggedIn ? cursor?.primaryPct : nil
        default: return nil
        }
    }

    public func lastUpdated(_ id: String) -> Date? {
        switch id {
        case "claude": return claude.lastUpdated
        case "antigravity": return antigravity?.lastUpdated
        case "codex": return codex?.lastUpdated
        case "cursor": return cursor?.lastUpdated
        default: return nil
        }
    }
}
