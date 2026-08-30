import AppKit
import Foundation

/// Hands a command off to a real Terminal window.
///
/// These CLIs' install and auth flows are interactive — a background process
/// can't drive an OAuth handoff or a package manager's confirmation prompt — so
/// the only honest thing to do is put the user in front of a real shell with
/// the command already typed.
enum TerminalLauncher {

    /// Commands come exclusively from `Provider`'s own static table, never from
    /// anything a user or a CLI typed, which is what makes the AppleScript
    /// string interpolation below safe. Quotes and backslashes are still
    /// escaped so a command containing them (Cursor's PATH-append one-liner
    /// does) survives the round trip intact.
    static func run(_ command: String) {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
            tell application "Terminal"
                activate
                do script "\(escaped)"
            end tell
            """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }
}
