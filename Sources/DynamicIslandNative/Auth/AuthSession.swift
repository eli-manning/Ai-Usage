import Foundation

struct AuthSession: Codable, Equatable {
    let provider: OAuthProvider
    var accessToken: String
    var refreshToken: String?
    var idToken: String?
    var expiresAt: Date?
    var accountEmail: String?
    var obtainedAt: Date

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date().addingTimeInterval(60)
    }
}
