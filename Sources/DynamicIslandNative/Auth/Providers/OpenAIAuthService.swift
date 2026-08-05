import Foundation

/// Browser OAuth compatible with ChatGPT subscription usage, using the same
/// public PKCE client and loopback redirect as the official Codex CLI.
final class OpenAIAuthService: OAuthProviderService {
    let provider: OAuthProvider = .chatGPT

    private let issuer = "https://auth.openai.com"
    private let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private let scope = "openid profile email offline_access api.connectors.read api.connectors.invoke"
    private let port: UInt16 = 1455
    private let callbackPath = "/auth/callback"

    var flowKind: OAuthFlowKind { .automaticLoopback(port: port, path: callbackPath) }

    func makeAuthorizationRequest() throws -> (url: URL, context: OAuthFlowContext) {
        let pkce = OAuthPKCE.generate()
        let state = OAuthPKCE.randomURLSafeString(byteCount: 24)
        let redirectURI = "http://localhost:\(port)\(callbackPath)"
        var components = URLComponents(string: "\(issuer)/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: pkce.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "state", value: state),
        ]
        return (components.url!, OAuthFlowContext(pkce: pkce, state: state, redirectURI: redirectURI))
    }

    func awaitAutomaticCallback(
        context: OAuthFlowContext,
        onListenerReady: @escaping @Sendable () -> Void
    ) async throws -> AuthSession {
        let result = try await LoopbackOAuthServer().waitForCallback(
            port: port,
            path: callbackPath,
            expectedState: context.state,
            onReady: onListenerReady
        )
        let json = try await OAuthHTTP.postForm(
            url: URL(string: "\(issuer)/oauth/token")!,
            form: [
                "grant_type": "authorization_code",
                "code": result.code,
                "redirect_uri": context.redirectURI,
                "client_id": clientID,
                "code_verifier": context.pkce.codeVerifier,
            ]
        )
        return try makeSession(from: json)
    }

    func completeManualCode(_ rawCode: String, context: OAuthFlowContext) async throws -> AuthSession {
        fatalError("ChatGPT uses the automatic loopback flow")
    }

    func refresh(_ session: AuthSession) async throws -> AuthSession {
        guard let refreshToken = session.refreshToken else { return session }
        let json = try await OAuthHTTP.postForm(
            url: URL(string: "\(issuer)/oauth/token")!,
            form: [
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": clientID,
            ]
        )
        return try makeSession(from: json, previous: session)
    }

    private func makeSession(from json: [String: Any], previous: AuthSession? = nil) throws -> AuthSession {
        guard let accessToken = json["access_token"] as? String else { throw OAuthHTTPError.malformedResponse }
        let idToken = json["id_token"] as? String
        let email = idToken.flatMap(JWTDecoding.payload(from:))?["email"] as? String
        let expiresIn = json["expires_in"] as? Double
        return AuthSession(
            provider: .chatGPT,
            accessToken: accessToken,
            refreshToken: (json["refresh_token"] as? String) ?? previous?.refreshToken,
            idToken: idToken ?? previous?.idToken,
            expiresAt: expiresIn.map { Date().addingTimeInterval($0) },
            accountEmail: email ?? previous?.accountEmail,
            obtainedAt: Date()
        )
    }
}
