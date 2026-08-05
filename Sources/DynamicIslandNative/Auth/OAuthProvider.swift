import SwiftUI

/// Providers with an installation-free browser OAuth flow and a usable
/// subscription-quota endpoint. Cursor intentionally isn't here: its public
/// SDK supports manually minted API keys, not consumer-subscription OAuth or
/// the normal subscription usage meter.
enum OAuthProvider: String, CaseIterable, Identifiable, Codable {
    case claude
    case chatGPT = "codex"
    case gemini = "antigravity"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .chatGPT: return "ChatGPT"
        case .gemini: return "Gemini"
        }
    }

    var appProvider: Provider {
        Provider.all.first(where: { $0.id == rawValue })!
    }

    var brandColor: Color { appProvider.color }
    var icon: String { appProvider.icon }
}
