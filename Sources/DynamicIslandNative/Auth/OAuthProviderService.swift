import Foundation

enum OAuthFlowKind {
    case automaticLoopback(port: UInt16, path: String)
    case manualCodePaste
}

struct OAuthFlowContext {
    let pkce: PKCECodes
    let state: String
    let redirectURI: String
}

protocol OAuthProviderService: AnyObject {
    var provider: OAuthProvider { get }
    var flowKind: OAuthFlowKind { get }

    func makeAuthorizationRequest() throws -> (url: URL, context: OAuthFlowContext)
    func awaitAutomaticCallback(
        context: OAuthFlowContext,
        onListenerReady: @escaping @Sendable () -> Void
    ) async throws -> AuthSession
    func completeManualCode(_ rawCode: String, context: OAuthFlowContext) async throws -> AuthSession
    func refresh(_ session: AuthSession) async throws -> AuthSession
}
