import AppKit

// Explicit `main.swift` rather than `@main` on the delegate: the app has no
// storyboard and no `NSApplicationMain` Info.plist key when run straight out of
// SwiftPM, so the run loop is started by hand here. That also means `swift run`
// launches a fully working app during development without a bundle.
//
// `MainActor.assumeIsolated` is the honest spelling of what is already true —
// top-level code in main.swift runs on the main thread before any concurrency
// exists — and it's what lets the main-actor-isolated delegate be constructed
// here without an await.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // The delegate is only weakly held by NSApplication; without this the sole
    // strong reference dies at the end of this scope and every callback stops.
    withExtendedLifetime(delegate) {
        app.run()
    }
}
