import Foundation

/// Browser OAuth compatible with Gemini subscription quota, using Google's
/// installed-application PKCE flow and the same Code Assist scopes as Gemini
/// CLI. Credentials are loaded from local app configuration rather than
/// committed to source.
final class GoogleAuthService: OAuthProviderService {
    let provider: OAuthProvider = .gemini

    private let scope = "https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/userinfo.profile"
    private let port: UInt16 = 8765
    private let callbackPath = "/oauth2callback"

    var flowKind: OAuthFlowKind { .automaticLoopback(port: port, path: callbackPath) }

    func makeAuthorizationRequest() throws -> (url: URL, context: OAuthFlowContext) {
        let credentials = try GoogleOAuthConfiguration.load()
        let pkce = OAuthPKCE.generate()
        let state = OAuthPKCE.randomURLSafeString(byteCount: 24)
        let redirectURI = "http://127.0.0.1:\(port)\(callbackPath)"
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: credentials.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
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
        let credentials = try GoogleOAuthConfiguration.load()
        let result = try await LoopbackOAuthServer().waitForCallback(
            port: port,
            path: callbackPath,
            expectedState: context.state,
            onReady: onListenerReady
        )
        let json = try await OAuthHTTP.postForm(
            url: URL(string: "https://oauth2.googleapis.com/token")!,
            form: [
                "grant_type": "authorization_code",
                "code": result.code,
                "redirect_uri": context.redirectURI,
                "client_id": credentials.clientID,
                "client_secret": credentials.clientSecret,
                "code_verifier": context.pkce.codeVerifier,
            ]
        )
        return await enrichingEmail(try makeSession(from: json))
    }

    func completeManualCode(_ rawCode: String, context: OAuthFlowContext) async throws -> AuthSession {
        fatalError("Gemini uses the automatic loopback flow")
    }

    func refresh(_ session: AuthSession) async throws -> AuthSession {
        guard let refreshToken = session.refreshToken else { return session }
        let credentials = try GoogleOAuthConfiguration.load()
        let json = try await OAuthHTTP.postForm(
            url: URL(string: "https://oauth2.googleapis.com/token")!,
            form: [
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": credentials.clientID,
                "client_secret": credentials.clientSecret,
            ]
        )
        return await enrichingEmail(try makeSession(from: json, previous: session))
    }

    private func makeSession(from json: [String: Any], previous: AuthSession? = nil) throws -> AuthSession {
        guard let accessToken = json["access_token"] as? String else { throw OAuthHTTPError.malformedResponse }
        let expiresIn = json["expires_in"] as? Double
        return AuthSession(
            provider: .gemini,
            accessToken: accessToken,
            refreshToken: (json["refresh_token"] as? String) ?? previous?.refreshToken,
            idToken: (json["id_token"] as? String) ?? previous?.idToken,
            expiresAt: expiresIn.map { Date().addingTimeInterval($0) },
            accountEmail: previous?.accountEmail,
            obtainedAt: Date()
        )
    }

    private func enrichingEmail(_ session: AuthSession) async -> AuthSession {
        var session = session
        if let json = try? await OAuthHTTP.getJSON(
            url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!,
            bearerToken: session.accessToken
        ) {
            session.accountEmail = json["email"] as? String
        }
        return session
    }
}
