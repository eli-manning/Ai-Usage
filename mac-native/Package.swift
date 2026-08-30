// swift-tools-version: 5.10
import PackageDescription

// A fully native macOS build of the usage tracker — tray *and* notch in one
// process, with no Electron, no Node, and no python3. The fetch layer that
// os-menu ships as JS + Python wrappers is ported into `UsageCore` and
// `ptydrive` here; see mac-native/README.md for the porting ledger.
let package = Package(
    name: "AiUsage",
    platforms: [.macOS(.v13)],
    targets: [
        // Parsing, models, provider drivers and the refresh orchestration.
        // Deliberately free of AppKit/SwiftUI so the parsers can be unit
        // tested headlessly against the shared fixture corpus.
        .target(name: "UsageCore"),

        // The PTY driver, as its own tiny executable rather than code inside
        // the app. `fork()` in a process that has already started AppKit's
        // threads is not async-signal-safe; keeping the fork/exec in a
        // single-threaded helper sidesteps that entirely. This is the 1:1
        // replacement for os-menu's four *-pty-wrapper.py scripts.
        .executableTarget(name: "ptydrive", dependencies: ["UsageCore"]),

        // The app itself: status item, popover, notch panel, settings, wizard.
        .executableTarget(
            name: "AiUsage",
            dependencies: ["UsageCore"],
            resources: [.copy("Resources")]
        ),

        // Dev-only harness for diffing the ported parsers against the JS
        // originals. Never referenced by the app.
        .executableTarget(name: "parsecheck", dependencies: ["UsageCore"]),

        .testTarget(
            name: "UsageCoreTests",
            dependencies: ["UsageCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
