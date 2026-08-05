import Combine
import Foundation

/// One shared account-backed usage store for both visual styles. Provider
/// OAuth sessions live in `AuthStore`; this object only fetches/normalizes
/// quota data and publishes the existing UI-facing shapes.
@MainActor
final class UsageService: ObservableObject {
    @Published var claude: ClaudeUsage = .empty
    @Published var antigravity: GeminiUsage?
    @Published var codex: CodexUsage?
    @Published var cursor: CursorUsage?
    @Published var providers: [String: ProviderStatus] = [:]
    @Published var accountEmails: [String: String] = [:]
    @Published var isRefreshing = false
    @Published var lastRefreshed: Date?

    private let authStore: AuthStore
    private var timer: Timer?

    init(authStore: AuthStore) {
        self.authStore = authStore
        providers = [
            "claude": ProviderStatus(state: .installed),
            "codex": ProviderStatus(state: .installed),
            "antigravity": ProviderStatus(state: .unsupported(Self.geminiUnavailableMessage)),
            // Cursor has no supported consumer OAuth/subscription-usage API.
            "cursor": ProviderStatus(state: .unsupported("Cursor does not provide supported consumer subscription OAuth.")),
        ]
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        accountEmails = Dictionary(uniqueKeysWithValues: OAuthProvider.allCases.compactMap { provider in
            authStore.accountEmail(for: provider).map { (provider.rawValue, $0) }
        })

        async let claudeResult = fetchClaude()
        async let chatGPTResult = fetchChatGPT()
        let (newClaude, newChatGPT) = await (claudeResult, chatGPTResult)

        applyClaude(newClaude)
        applyChatGPT(newChatGPT)
        antigravity = nil
        providers["antigravity"] = ProviderStatus(state: .unsupported(Self.geminiUnavailableMessage))
        providers["cursor"] = ProviderStatus(state: .unsupported("Cursor does not provide supported consumer subscription OAuth."))
        lastRefreshed = Date()
    }

    private func fetchClaude() async -> AccountFetch<ClaudeUsage> {
        guard let session = await authStore.validSession(for: .claude) else { return .disconnected }
        do { return .value(try await OAuthUsageClient.fetchClaude(session: session)) }
        catch { return .failure(error.localizedDescription) }
    }

    private func fetchChatGPT() async -> AccountFetch<CodexUsage> {
        guard let session = await authStore.validSession(for: .chatGPT) else { return .disconnected }
        do { return .value(try await OAuthUsageClient.fetchChatGPT(session: session)) }
        catch { return .failure(error.localizedDescription) }
    }

    private func applyClaude(_ result: AccountFetch<ClaudeUsage>) {
        switch result {
        case .disconnected:
            claude = .empty
            providers["claude"] = ProviderStatus(state: .installed)
        case .failure(let message):
            claude.error = message
            providers["claude"] = ProviderStatus(state: .error(message))
        case .value(let value):
            claude = value
            providers["claude"] = ProviderStatus(state: .loggedIn)
        }
    }

    private func applyChatGPT(_ result: AccountFetch<CodexUsage>) {
        switch result {
        case .disconnected:
            codex = nil
            providers["codex"] = ProviderStatus(state: .installed)
        case .failure(let message):
            providers["codex"] = ProviderStatus(state: .error(message))
        case .value(let value):
            codex = value
            providers["codex"] = ProviderStatus(state: .loggedIn)
        }
    }

    private static let geminiUnavailableMessage =
        "Google retired Gemini CLI OAuth for individual accounts; supported third-party Antigravity OAuth isn't available."
}

private enum AccountFetch<Value> {
    case disconnected
    case value(Value)
    case failure(String)
}
