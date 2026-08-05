import AppKit

/// Real terminal handoff for a provider's install/login command — these
/// CLIs' install scripts and auth flows are interactive, so a background
/// `Process` can't drive them; every style that needs this shares the same
/// one-liner rather than each reimplementing it.
enum TerminalRunner {
    static func run(_ command: String) {
        let escaped = command.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application \"Terminal\"\nactivate\ndo script \"\(escaped)\"\nend tell"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        try? task.run()
    }
}

/// What tapping a provider's "not wired up yet" affordance does, shared by
/// every visual style (`RingView`'s status wedge, the pill style's
/// connect/sign-in buttons) so they can never drift apart on what
/// "Install"/"Sign In" actually runs.
enum ProviderActionHandler {
    static func handle(status: ProviderStatus, provider: Provider) {
        switch status.state {
        case .checking, .loggedIn:
            break
        case .notInstalled:
            if let command = provider.installCommand {
                TerminalRunner.run(command)
            } else if let urlString = provider.installURL, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        case .installed, .error:
            if let command = provider.loginCommand {
                TerminalRunner.run(command)
            }
        }
    }
}
