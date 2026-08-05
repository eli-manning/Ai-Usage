import Foundation

struct GoogleOAuthConfiguration: Decodable {
    let clientID: String
    let clientSecret: String

    enum ConfigurationError: Error, LocalizedError {
        case missing

        var errorDescription: String? {
            "Gemini OAuth isn't configured. Add google-oauth.json to ~/Library/Application Support/AiUsage/."
        }
    }

    static func load() throws -> GoogleOAuthConfiguration {
        let environment = ProcessInfo.processInfo.environment
        if let clientID = environment["AI_USAGE_GOOGLE_CLIENT_ID"],
           let clientSecret = environment["AI_USAGE_GOOGLE_CLIENT_SECRET"],
           !clientID.isEmpty, !clientSecret.isEmpty {
            return GoogleOAuthConfiguration(clientID: clientID, clientSecret: clientSecret)
        }

        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AiUsage/google-oauth.json")
        guard let data = try? Data(contentsOf: url),
              let configuration = try? JSONDecoder().decode(GoogleOAuthConfiguration.self, from: data),
              !configuration.clientID.isEmpty, !configuration.clientSecret.isEmpty else {
            throw ConfigurationError.missing
        }
        return configuration
    }
}
