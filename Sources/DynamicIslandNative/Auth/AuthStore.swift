import AppKit
import Foundation

struct PendingManualAuth: Identifiable {
    let provider: OAuthProvider
    let authURL: URL
    let context: OAuthFlowContext
    var id: OAuthProvider { provider }
}

@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var sessions: [OAuthProvider: AuthSession] = [:]
    @Published var pendingManualAuth: PendingManualAuth?
    @Published private(set) var connectingProviders: Set<OAuthProvider> = []
    @Published var lastError: String?

    var onChange: (() -> Void)?
    var onManualAuthRequested: (() -> Void)?

    private let keychain = KeychainStore(service: "com.ryanstoffel.aiusage.auth")
    private let services: [OAuthProvider: OAuthProviderService] = [
        .claude: ClaudeAuthService(),
        .chatGPT: OpenAIAuthService(),
        .gemini: GoogleAuthService(),
    ]

    init() {
        loadPersistedSessions()
    }

    func isConnected(_ provider: OAuthProvider) -> Bool { sessions[provider] != nil }
    func accountEmail(for provider: OAuthProvider) -> String? { sessions[provider]?.accountEmail }
    func isConnecting(_ provider: OAuthProvider) -> Bool { connectingProviders.contains(provider) }

    func connect(_ provider: OAuthProvider) {
        guard provider != .gemini else {
            lastError = "Google retired individual Gemini CLI OAuth; supported third-party Antigravity OAuth isn't available."
            return
        }
        guard let service = services[provider], !connectingProviders.contains(provider) else { return }
        lastError = nil

        let request: (url: URL, context: OAuthFlowContext)
        do {
            request = try service.makeAuthorizationRequest()
        } catch {
            lastError = error.localizedDescription
            return
        }

        connectingProviders.insert(provider)
        switch service.flowKind {
        case .automaticLoopback:
            Task {
                do {
                    let session = try await service.awaitAutomaticCallback(
                        context: request.context,
                        onListenerReady: { NSWorkspace.shared.open(request.url) }
                    )
                    self.store(session)
                } catch {
                    self.lastError = error.localizedDescription
                }
                self.connectingProviders.remove(provider)
            }
        case .manualCodePaste:
            pendingManualAuth = PendingManualAuth(provider: provider, authURL: request.url, context: request.context)
            connectingProviders.remove(provider)
            onManualAuthRequested?()
            NSWorkspace.shared.open(request.url)
        }
    }

    func submitManualCode(_ code: String) {
        guard let pending = pendingManualAuth,
              let service = services[pending.provider],
              !connectingProviders.contains(pending.provider) else { return }
        lastError = nil
        connectingProviders.insert(pending.provider)
        Task {
            do {
                let session = try await service.completeManualCode(code, context: pending.context)
                self.store(session)
                self.pendingManualAuth = nil
            } catch {
                self.lastError = error.localizedDescription
            }
            self.connectingProviders.remove(pending.provider)
        }
    }

    func cancelManualAuth() { pendingManualAuth = nil }

    func disconnect(_ provider: OAuthProvider) {
        sessions[provider] = nil
        keychain.delete(account: provider.rawValue)
        onChange?()
    }

    func validSession(for provider: OAuthProvider) async -> AuthSession? {
        guard let session = sessions[provider] else { return nil }
        guard session.isExpired else { return session }
        guard let service = services[provider] else { return nil }
        do {
            let refreshed = try await service.refresh(session)
            guard !refreshed.isExpired, sessions[provider] == session else { return nil }
            store(refreshed, notifyChange: false)
            return refreshed
        } catch {
            lastError = "Couldn't refresh \(provider.displayName): \(error.localizedDescription)"
            return nil
        }
    }

    private func store(_ session: AuthSession, notifyChange: Bool = true) {
        sessions[session.provider] = session
        if let data = try? JSONEncoder().encode(session) {
            try? keychain.save(data, account: session.provider.rawValue)
        }
        if notifyChange { onChange?() }
    }

    private func loadPersistedSessions() {
        for provider in OAuthProvider.allCases {
            guard let data = keychain.load(account: provider.rawValue),
                  let session = try? JSONDecoder().decode(AuthSession.self, from: data) else { continue }
            sessions[provider] = session
        }
    }
}
