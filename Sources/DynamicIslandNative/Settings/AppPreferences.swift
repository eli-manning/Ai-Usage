import Foundation

/// The two visual styles the app can render its usage data as. Both read
/// from the same `UsageService` instance — this only picks how it's drawn.
enum AppStyle: String, CaseIterable, Identifiable, Codable {
    /// The original radial wedge fan hanging beneath a hub over the notch.
    case fan
    /// A compact pill living in the notch that expands into a card,
    /// modeled directly on the `notch-limits` app.
    case pill

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fan: return "Fan"
        case .pill: return "Pill"
        }
    }

    var summary: String {
        switch self {
        case .fan: return "A radial wedge fan hangs beneath a hub icon over the notch. Hover to expand, click the hub to refresh."
        case .pill: return "A compact pill sits in the notch and expands into a card listing every provider, styled after notch-limits."
        }
    }
}

/// Lightweight `UserDefaults`-backed settings, published so SwiftUI views
/// can bind directly to them.
@MainActor
final class AppPreferences: ObservableObject {
    private enum Keys {
        static let style = "appStyle"
    }

    private let defaults: UserDefaults

    @Published var style: AppStyle {
        didSet { defaults.set(style.rawValue, forKey: Keys.style) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Keys.style).flatMap(AppStyle.init(rawValue:))
        self.style = stored ?? .fan
    }
}
