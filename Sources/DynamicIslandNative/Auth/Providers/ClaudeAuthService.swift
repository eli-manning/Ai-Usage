import Foundation

/// Browser OAuth compatible with Claude Pro/Max subscription usage. The
/// hosted callback shows a code that the user pastes back into Settings.
final class ClaudeAuthService: OAuthProviderService {
    let provider: OAuthProvider = .claude

    private let authorizeEndpoint = "https://claude.ai/oauth/authorize"
    private let tokenEndpoint = "https://console.anthropic.com/v1/oauth/token"
    private let redirectURI = "https://console.anthropic.com/oauth/code/callback"
    private let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private let scope = "org:create_api_key user:profile user:inference"

    var flowKind: OAuthFlowKind { .manualCodePaste }

    func makeAuthorizationRequest() throws -> (url: URL, context: OAuthFlowContext) {
        let pkce = OAuthPKCE.generate()
        let state = pkce.codeVerifier
        var components = URLComponents(string: authorizeEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: pkce.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        return (components.url!, OAuthFlowContext(pkce: pkce, state: state, redirectURI: redirectURI))
    }

    func awaitAutomaticCallback(
        context: OAuthFlowContext,
        onListenerReady: @escaping @Sendable () -> Void
    ) async throws -> AuthSession {
        fatalError("Claude uses the manual code-paste flow")
    }

    func completeManualCode(_ rawCode: String, context: OAuthFlowContext) async throws -> AuthSession {
        let trimmed = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = trimmed.split(separator: "#").first.map(String.init) ?? trimmed
        let json = try await OAuthHTTP.postJSON(
            url: URL(string: tokenEndpoint)!,
            body: [
                "grant_type": "authorization_code",
                "code": code,
                "code_verifier": context.pkce.codeVerifier,
                "client_id": clientID,
                "redirect_uri": context.redirectURI,
                "state": context.state,
            ],
            extraHeaders: ["User-Agent": "AiUsage"]
        )
        return await enrichingEmail(try makeSession(from: json))
    }

    func refresh(_ session: AuthSession) async throws -> AuthSession {
        guard let refreshToken = session.refreshToken else { return session }
        let json = try await OAuthHTTP.postJSON(
            url: URL(string: tokenEndpoint)!,
            body: [
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": clientID,
            ],
            extraHeaders: ["User-Agent": "AiUsage"]
        )
        return await enrichingEmail(try makeSession(from: json, previous: session))
    }

    private func makeSession(from json: [String: Any], previous: AuthSession? = nil) throws -> AuthSession {
        guard let accessToken = json["access_token"] as? String else { throw OAuthHTTPError.malformedResponse }
        let expiresIn = json["expires_in"] as? Double
        return AuthSession(
            provider: .claude,
            accessToken: accessToken,
            refreshToken: (json["refresh_token"] as? String) ?? previous?.refreshToken,
            idToken: previous?.idToken,
            expiresAt: expiresIn.map { Date().addingTimeInterval($0) },
            accountEmail: previous?.accountEmail,
            obtainedAt: Date()
        )
    }

    private func enrichingEmail(_ session: AuthSession) async -> AuthSession {
        var session = session
        guard let json = try? await OAuthHTTP.getJSON(
            url: URL(string: "https://api.anthropic.com/api/oauth/profile")!,
            bearerToken: session.accessToken
        ) else { return session }
        session.accountEmail = (json["email"] as? String)
            ?? (json["account"] as? [String: Any])?["email"] as? String
        return session
    }
}
