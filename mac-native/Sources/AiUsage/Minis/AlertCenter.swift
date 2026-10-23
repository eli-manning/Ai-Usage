import AppKit
import UserNotifications
import UsageCore

/// Sounds and notifications for minis that need you.
///
/// An alert doesn't fade on its own: its sound plays again every
/// `repeatSeconds` and its notification stays in Notification Center until
/// you answer in that session, click the mini, or click or dismiss the
/// notification. Banners still slide away after a few seconds unless macOS is
/// set to show this app's notifications as Alerts — Settings says so.
@MainActor
final class AlertCenter: NSObject, UNUserNotificationCenterDelegate {

    /// You clicked (`focus: true`) or dismissed a notification.
    var onResponse: ((_ sessionID: String, _ focus: Bool) -> Void)?

    private var lastPlayed = Date.distantPast
    private var sound: NSSound?

    /// UNUserNotificationCenter needs a real app bundle; `swift run` has none
    /// and would crash asking for it.
    private let canNotify = Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    private var authorized = false
    private static let category = "minis.alert"

    func start() {
        guard canNotify else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // customDismissAction: tells us when you swipe it away, which counts as having looked.
        let category = UNNotificationCategory(identifier: Self.category, actions: [], intentIdentifiers: [],
                                              options: [.customDismissAction])
        center.setNotificationCategories([category])
        center.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            Task { @MainActor in self.authorized = ok }
        }
    }

    /// A new alert: sound now, and a notification.
    func raise(_ s: AgentSession, config: MinisConfig) {
        guard let kind = s.alert, config.alerts(kind) else { return }
        play(config.sound(kind), volume: config.volume)
        lastPlayed = Date()
        guard config.notifications, canNotify else { return }
        let content = UNMutableNotificationContent()
        let name = Provider.byID(s.provider)?.name ?? s.provider
        switch kind {
        case .done: content.title = "\(name) finished"
        case .needsInput: content.title = "\(name) needs your input"
        case .failed: content.title = "\(name) stopped with an error"
        }
        content.body = [s.project, s.alertDetail].filter { !$0.isEmpty }.joined(separator: " — ")
        content.categoryIdentifier = Self.category
        content.userInfo = ["session": s.id]
        content.interruptionLevel = kind == .done ? .active : .timeSensitive
        // No sound here: this class plays it, so one setting controls both.
        let request = UNNotificationRequest(identifier: s.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// The alert came down: take its notification back out.
    func clear(_ sessionID: String) {
        guard canNotify else { return }
        let c = UNUserNotificationCenter.current()
        c.removeDeliveredNotifications(withIdentifiers: [sessionID])
        c.removePendingNotificationRequests(withIdentifiers: [sessionID])
    }

    /// Called every second with whatever is still waiting on you. Repeats the
    /// sound of the oldest unanswered alert, one sound per interval in total.
    func tick(waiting: [AgentSession], config: MinisConfig) {
        guard config.repeatSeconds > 0,
              let oldest = waiting.first(where: { $0.alert.map(config.alerts) ?? false }),
              let kind = oldest.alert,
              Date().timeIntervalSince(lastPlayed) >= config.repeatSeconds else { return }
        play(config.sound(kind), volume: config.volume)
        lastPlayed = Date()
    }

    func play(_ name: String, volume: Double) {
        guard name != "None", let s = NSSound(named: NSSound.Name(name))?.copy() as? NSSound else { return }
        s.volume = Float(volume)
        sound?.stop()
        sound = s
        s.play()
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show it even though this app is "active" (a menu-bar app often is).
        completionHandler([.banner, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["session"] as? String ?? ""
        let focus = response.actionIdentifier == UNNotificationDefaultActionIdentifier
        Task { @MainActor in self.onResponse?(id, focus) }
        completionHandler()
    }
}
