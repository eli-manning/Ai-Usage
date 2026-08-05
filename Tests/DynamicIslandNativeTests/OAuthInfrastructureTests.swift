import Foundation
import Testing
@testable import DynamicIslandNative

struct OAuthInfrastructureTests {
    @Test func decodesJWTEmailClaim() throws {
        let header = Self.base64URL(#"{"alg":"none"}"#)
        let payload = Self.base64URL(#"{"email":"person@example.com"}"#)
        let claims = try #require(JWTDecoding.payload(from: "\(header).\(payload)."))
        #expect(claims["email"] as? String == "person@example.com")
    }

    @Test func oauthProviderIDsMatchSharedUsageProviderIDs() {
        #expect(OAuthProvider.claude.rawValue == "claude")
        #expect(OAuthProvider.chatGPT.rawValue == "codex")
        #expect(OAuthProvider.gemini.rawValue == "antigravity")
        #expect(OAuthProvider.allCases.allSatisfy { provider in
            Provider.all.contains(where: { $0.id == provider.rawValue })
        })
    }

    @Test func standardizesProviderResetDatesInLocalTime() throws {
        let date = try #require(ResetDateFormatting.parse("2026-08-09T05:05:06Z"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(ResetDateFormatting.parse("2026-08-04T12:00:00Z"))
        #expect(ResetDateFormatting.display(date, now: now, calendar: calendar) == "AUG 9, 5:05 AM")
    }

    @Test func authSessionExpiresWithRefreshLeeway() {
        let expiring = AuthSession(
            provider: .claude,
            accessToken: "token",
            refreshToken: nil,
            idToken: nil,
            expiresAt: Date().addingTimeInterval(30),
            accountEmail: "person@example.com",
            obtainedAt: Date()
        )
        #expect(expiring.isExpired)

        var valid = expiring
        valid.expiresAt = Date().addingTimeInterval(120)
        #expect(!valid.isExpired)
    }

    private static func base64URL(_ string: String) -> String {
        Data(string.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
