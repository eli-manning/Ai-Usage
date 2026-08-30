import Foundation

/// App-wide notifications.
///
/// These exist so a deeply-nested view (a notch wedge, say) can ask for a
/// window without every layer between it and `AppDelegate` having to carry a
/// closure for it. Anything a view can request of the app as a whole belongs
/// here; anything it can request of its own shell stays a closure.
extension Notification.Name {
    /// Posted when a view wants the Settings window opened.
    static let openSettingsRequested = Notification.Name("com.eli.aiusage.openSettings")

    /// Posted when a view wants the setup wizard shown.
    static let openWizardRequested = Notification.Name("com.eli.aiusage.openWizard")

    // `panelShouldCollapse` is declared by PanelController, which owns the
    // behaviour it drives — left there rather than hoisted here.
}
