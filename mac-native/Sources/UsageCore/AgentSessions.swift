import Foundation

/// Why a mini is asking for you. Each one has its own sound.
public enum AlertKind: String, Codable, Sendable, CaseIterable {
    case done, needsInput, failed

    public var title: String {
        switch self {
        case .done: return "Finished"
        case .needsInput: return "Needs input"
        case .failed: return "Failed"
        }
    }
}

/// One running session of one provider's CLI — a terminal tab, an editor
/// panel, a desktop app chat. Each gets its own mini.
public struct AgentSession: Identifiable, Equatable, Sendable {
    public enum Phase: String, Sendable { case idle, working }

    public var id: String { Self.key(provider, sessionID) }
    public let provider: String
    public let sessionID: String
    public var cwd = ""
    /// The process that ran the hook, for finding the app the session lives in.
    public var pid: Int32 = 0
    public var phase = Phase.idle
    public var activity = AgentActivity.thinking
    public var detail = ""
    /// A tool that has finished still shows for a moment, so quick calls
    /// don't flicker straight back to "thinking".
    public var activityUntil = Date.distantPast
    public var toolsRunning = 0
    /// Waiting on you. Stays until you respond in the session or acknowledge it.
    public var alert: AlertKind?
    public var alertDetail = ""
    public var alertAt = Date.distantPast
    public let startedAt: Date
    public var lastEvent: Date

    public init(provider: String, sessionID: String, now: Date) {
        self.provider = provider
        self.sessionID = sessionID
        self.startedAt = now
        self.lastEvent = now
    }

    public static func key(_ provider: String, _ sessionID: String) -> String { provider + ":" + sessionID }

    public var project: String { cwd.isEmpty ? "" : (cwd as NSString).lastPathComponent }

    /// What the mini shows: an alert wins, then the current tool, then thinking.
    public func display(now: Date) -> (state: String, detail: String) {
        if let alert { return (alert.rawValue, alertDetail) }
        guard phase == .working else { return ("idle", "") }
        if toolsRunning > 0 || now < activityUntil { return (activity.rawValue, detail) }
        return (AgentActivity.thinking.rawValue, "")
    }
}

/// Every live session, and the rules for how hook events move them along.
///
/// Pure state — no timers, sounds or windows — so the alert rules ("stays
/// until you respond or look at it") are testable on their own.
public struct AgentSessionStore: Sendable {
    public private(set) var sessions: [String: AgentSession] = [:]

    public init() {}

    public enum Change: Equatable, Sendable {
        case none
        case updated
        case spawned
        case removed
        /// An alert went up — play it.
        case alerted(AlertKind)
        /// You responded in the session, so its alert came down.
        case answered
    }

    @discardableResult
    public mutating func apply(_ e: AgentEvent, pid: Int32 = 0, now: Date = Date()) -> Change {
        let key = AgentSession.key(e.provider, e.sessionID)
        if e.kind == .sessionEnd {
            return sessions.removeValue(forKey: key) == nil ? .none : .removed
        }
        let isNew = sessions[key] == nil
        var s = sessions[key] ?? AgentSession(provider: e.provider, sessionID: e.sessionID, now: now)
        s.lastEvent = now
        if !e.cwd.isEmpty { s.cwd = e.cwd }
        if s.pid == 0, pid > 0 { s.pid = pid }

        let hadAlert = s.alert != nil
        var change: Change = isNew ? .spawned : .updated

        switch e.kind {
        case .sessionStart:
            break
        case .prompt, .thought:
            s.phase = .working
            s.alert = nil
        case .toolStart:
            s.phase = .working
            s.alert = nil
            s.toolsRunning += 1
            s.activity = e.activity ?? .tool
            s.detail = e.detail
            s.activityUntil = .distantFuture
        case .toolEnd:
            s.phase = .working
            s.alert = nil
            s.toolsRunning = max(0, s.toolsRunning - 1)
            if let a = e.activity { s.activity = a; s.detail = e.detail }
            s.activityUntil = now.addingTimeInterval(3)
        case .toolFailed:
            s.phase = .working
            s.alert = nil
            s.toolsRunning = max(0, s.toolsRunning - 1)
            s.activityUntil = now.addingTimeInterval(3)
        case .compact:
            s.phase = .working
            s.activity = .compacting
            s.detail = ""
            s.activityUntil = now.addingTimeInterval(60)
        case .needsInput:
            s.alert = .needsInput
            s.alertDetail = e.detail
            s.alertAt = now
            change = .alerted(.needsInput)
        case .done, .failed:
            s.phase = .idle
            s.toolsRunning = 0
            s.activityUntil = .distantPast
            let kind: AlertKind = e.kind == .done ? .done : .failed
            s.alert = kind
            s.alertDetail = ""
            s.alertAt = now
            change = .alerted(kind)
        case .interrupted:
            s.phase = .idle
            s.toolsRunning = 0
            s.activityUntil = .distantPast
            s.alert = nil
        case .sessionEnd:
            break
        }

        if hadAlert && s.alert == nil, case .updated = change { change = .answered }
        sessions[key] = s
        return change
    }

    /// You looked at it: clicked the mini or the notification.
    @discardableResult
    public mutating func acknowledge(_ id: String) -> Bool {
        guard sessions[id]?.alert != nil else { return false }
        sessions[id]?.alert = nil
        return true
    }

    public mutating func remove(_ id: String) {
        sessions[id] = nil
    }

    /// Lets go of sessions that went quiet — a closed terminal never says
    /// goodbye — and of work that never reported finishing.
    /// - Returns: the ids that were removed.
    @discardableResult
    public mutating func prune(now: Date = Date(), idleTimeout: TimeInterval) -> [String] {
        var removed: [String] = []
        for (id, var s) in sessions {
            let quiet = now.timeIntervalSince(s.lastEvent)
            // An unanswered alert keeps its mini around: that's the point of it.
            if s.alert == nil, s.phase == .idle || quiet > 3 * 3600, quiet > idleTimeout {
                sessions[id] = nil
                removed.append(id)
                continue
            }
            if s.phase == .working, quiet > (s.toolsRunning > 0 ? 30 * 60 : 10 * 60) {
                s.phase = .idle
                s.toolsRunning = 0
                s.activityUntil = .distantPast
                sessions[id] = s
            }
        }
        return removed
    }

    public var alerting: [AgentSession] {
        sessions.values.filter { $0.alert != nil }.sorted { $0.alertAt < $1.alertAt }
    }

    /// Stable order for laying the minis out: by provider, then by age.
    public var ordered: [AgentSession] {
        let order = Provider.ids
        return sessions.values.sorted {
            let a = order.firstIndex(of: $0.provider) ?? 99, b = order.firstIndex(of: $1.provider) ?? 99
            return a != b ? a < b : $0.startedAt < $1.startedAt
        }
    }
}
