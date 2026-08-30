import Foundation

/// Which shell is on screen. macOS-only concept, but stored unconditionally so
/// the value survives round-tripping on a machine that can't render one of them.
public enum DisplayMode: String, Codable, CaseIterable {
    case tray
    case notch

    public var title: String {
        switch self {
        case .tray: return "Menu bar"
        case .notch: return "Notch"
        }
    }

    public var detail: String {
        switch self {
        case .tray: return "A status item with a click-to-open panel."
        case .notch: return "A pill fused to the notch that expands into a radial fan."
        }
    }
}

/// Plain-JSON settings in Application Support, the same approach os-menu takes
/// (`userData/settings.json`) — this app has no need for a heavier store.
///
/// Deliberately not `UserDefaults`: the file is meant to be readable and
/// hand-editable while debugging, and a corrupt or missing file falls back to
/// defaults rather than failing to launch.
public final class Settings: @unchecked Sendable {

    public static let shared = Settings()

    private struct Payload: Codable {
        var providerEnabled: [String: Bool]?
        var displayMode: String?
        var launchAtLogin: Bool?
        var setupComplete: Bool?
        var selectedProvider: String?
    }

    private let queue = DispatchQueue(label: "com.eli.aiusage.settings")
    private var payload = Payload()

    public static let defaultProviderEnabled: [String: Bool] =
        Dictionary(uniqueKeysWithValues: Provider.ids.map { ($0, true) })

    private init() { load() }

    // MARK: - Location

    public static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("AiUsage", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var fileURL: URL {
        supportDirectory.appendingPathComponent("settings.json")
    }

    // MARK: - Load / save

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let decoded = try? JSONDecoder().decode(Payload.self, from: data) else {
            // Missing or corrupt — keep defaults rather than refusing to start.
            return
        }
        payload = decoded
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    // MARK: - Accessors

    public var providerEnabled: [String: Bool] {
        get {
            queue.sync {
                Self.defaultProviderEnabled.merging(payload.providerEnabled ?? [:]) { _, new in new }
            }
        }
        set {
            queue.sync { payload.providerEnabled = newValue; persist() }
        }
    }

    public func isEnabled(_ id: String) -> Bool {
        providerEnabled[id] ?? true
    }

    public func setEnabled(_ id: String, _ enabled: Bool) {
        var current = providerEnabled
        current[id] = enabled
        providerEnabled = current
    }

    /// The order in `Provider.all` doubles as the fallback order whenever the
    /// selected provider turns out to be switched off.
    public func firstEnabledProvider() -> String {
        Provider.ids.first { isEnabled($0) } ?? "claude"
    }

    public var displayMode: DisplayMode {
        get { queue.sync { DisplayMode(rawValue: payload.displayMode ?? "") ?? .tray } }
        set { queue.sync { payload.displayMode = newValue.rawValue; persist() } }
    }

    public var launchAtLogin: Bool {
        get { queue.sync { payload.launchAtLogin ?? false } }
        set { queue.sync { payload.launchAtLogin = newValue; persist() } }
    }

    public var setupComplete: Bool {
        get { queue.sync { payload.setupComplete ?? false } }
        set { queue.sync { payload.setupComplete = newValue; persist() } }
    }

    /// Which provider's tab/badge is showing. Persisted so the app reopens on
    /// whatever you were last looking at.
    public var selectedProvider: String {
        get { queue.sync { payload.selectedProvider ?? "claude" } }
        set { queue.sync { payload.selectedProvider = newValue; persist() } }
    }
}
