import Foundation

/// How much a mini moves around on its own.
public enum MiniMotion: String, Codable, CaseIterable, Sendable {
    /// Stays exactly where it is.
    case still
    /// Paces a little within its own spot while the session works.
    case pace

    public var title: String {
        switch self {
        case .still: return "Stay put"
        case .pace: return "Pace while working"
        }
    }
}

/// What a mini says in its bubble.
public enum MiniSpeech: String, Codable, CaseIterable, Sendable {
    /// No bubble at all, except to ask for you.
    case alertsOnly
    /// A one-word status: "Editing", "Done".
    case status
    /// The status plus what it's on: "Editing App.swift".
    case detailed

    public var title: String {
        switch self {
        case .alertsOnly: return "Only when it needs you"
        case .status: return "Status"
        case .detailed: return "Status and file/command"
        }
    }
}

/// How much animation a mini plays.
public enum MiniAnimation: String, Codable, CaseIterable, Sendable {
    /// Props, particles and full poses.
    case full
    /// Poses and props, no particles, slower idle.
    case subtle
    /// Just the critter, no props or particles — a coloured status light with eyes.
    case minimal

    public var title: String {
        switch self {
        case .full: return "Full"
        case .subtle: return "Subtle"
        case .minimal: return "Minimal"
        }
    }
}

/// Which edge of the screen the minis line up along.
public enum MiniPlacement: String, Codable, CaseIterable, Sendable {
    case bottomRight, bottomLeft

    public var title: String {
        switch self {
        case .bottomRight: return "Bottom right"
        case .bottomLeft: return "Bottom left"
        }
    }
}

/// Everything configurable about the minis, saved inside `settings.json`.
///
/// Decoded key by key with defaults, so a settings file from before a key
/// existed (or with one hand-edited out) still loads.
public struct MinisConfig: Codable, Equatable, Sendable {
    public var enabled = true
    /// Per provider; a provider missing from the map is on.
    public var providers: [String: Bool] = [:]
    public var motion = MiniMotion.still
    public var speech = MiniSpeech.status
    public var animation = MiniAnimation.subtle
    public var placement = MiniPlacement.bottomRight
    /// Points per critter pixel.
    public var scale: Double = 2
    /// An idle session's mini goes away after this long without an event.
    public var idleMinutes: Double = 20

    public var alertOn: [String: Bool] = [:]
    public var sounds: [String: String] = [:]
    /// How often an unanswered alert sounds again. 0 plays it once.
    public var repeatSeconds: Double = 30
    public var volume: Double = 0.6
    public var notifications = true

    public init() {}

    public func providerOn(_ id: String) -> Bool { providers[id] ?? true }

    public func alerts(_ kind: AlertKind) -> Bool { alertOn[kind.rawValue] ?? true }

    public func sound(_ kind: AlertKind) -> String {
        sounds[kind.rawValue] ?? Self.defaultSounds[kind]!
    }

    public static let defaultSounds: [AlertKind: String] = [.done: "Glass", .needsInput: "Ping", .failed: "Basso"]

    /// The sounds macOS ships in /System/Library/Sounds, plus "None".
    public static let soundChoices = ["None", "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
                                      "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]

    private enum K: String, CodingKey {
        case enabled, providers, motion, speech, animation, placement, scale, idleMinutes,
             alertOn, sounds, repeatSeconds, volume, notifications
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        let d = MinisConfig()
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? d.enabled
        providers = (try? c.decode([String: Bool].self, forKey: .providers)) ?? d.providers
        motion = (try? c.decode(MiniMotion.self, forKey: .motion)) ?? d.motion
        speech = (try? c.decode(MiniSpeech.self, forKey: .speech)) ?? d.speech
        animation = (try? c.decode(MiniAnimation.self, forKey: .animation)) ?? d.animation
        placement = (try? c.decode(MiniPlacement.self, forKey: .placement)) ?? d.placement
        scale = (try? c.decode(Double.self, forKey: .scale)) ?? d.scale
        idleMinutes = (try? c.decode(Double.self, forKey: .idleMinutes)) ?? d.idleMinutes
        alertOn = (try? c.decode([String: Bool].self, forKey: .alertOn)) ?? d.alertOn
        sounds = (try? c.decode([String: String].self, forKey: .sounds)) ?? d.sounds
        repeatSeconds = (try? c.decode(Double.self, forKey: .repeatSeconds)) ?? d.repeatSeconds
        volume = (try? c.decode(Double.self, forKey: .volume)) ?? d.volume
        notifications = (try? c.decode(Bool.self, forKey: .notifications)) ?? d.notifications
    }
}
