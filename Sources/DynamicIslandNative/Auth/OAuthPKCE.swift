import CryptoKit
import Foundation
import Security

struct PKCECodes {
    let codeVerifier: String
    let codeChallenge: String
}

enum OAuthPKCE {
    static func generate() -> PKCECodes {
        let verifier = randomURLSafeString(byteCount: 32)
        return PKCECodes(codeVerifier: verifier, codeChallenge: codeChallenge(for: verifier))
    }

    static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return base64URLEncode(Data(bytes))
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncode(Data(digest))
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
