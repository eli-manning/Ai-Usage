import Darwin
import Foundation
import UsageCore

// Drives one provider CLI in a PTY and writes whatever it rendered to stdout.
// The 1:1 replacement for os-menu's pty-wrapper.py / agy-pty-wrapper.py /
// codex-pty-wrapper.py / cursor-pty-wrapper.py, with the same output contract:
// raw captured bytes on stdout, parsing left to the caller.
//
//   ptydrive claude <path-to-claude> [/usage|/stats]
//   ptydrive antigravity <path-to-agy>
//   ptydrive codex <path-to-codex>
//   ptydrive cursor <path-to-cursor-agent>
//
// This lives in its own executable rather than inside the app because the
// spawn path here wants a single-threaded, predictable process — see the
// comment on PTYSession.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("ptydrive: \(message)\n".utf8))
    exit(2)
}

let args = CommandLine.arguments
guard args.count >= 3 else {
    fail("usage: ptydrive <provider> <binary-path> [command]")
}

let provider = args[1]
let binaryPath = args[2]
let command: String? = args.count > 3 ? args[3] : nil

guard let spec = PTYSession.spec(for: provider, command: command) else {
    fail("unknown provider '\(provider)'")
}

guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
    fail("not executable: \(binaryPath)")
}

// TERM=dumb and FORCE_COLOR=0 are essential for consistent parsing — they cut
// the TUI down to plain positioned text instead of a full colour repaint.
// CLAUDE_CODE_DISABLE_ANIMATIONS strips the spinner frames that otherwise keep
// the screen "busy" and defeat idle detection.
var env = ProcessInfo.processInfo.environment
env["TERM"] = "dumb"
env["FORCE_COLOR"] = "0"
env["CLAUDE_CODE_DISABLE_ANIMATIONS"] = "true"
env["PATH"] = CLILocator.augmentedPATH(env["PATH"])

// A SIGTERM from the parent (its own watchdog firing) should still print
// whatever was captured rather than dying silently — matching the Python
// wrappers, which turned SIGTERM into a normal exception so their
// try/finally still ran. The capture loop's own cleanup handles the child.
signal(SIGTERM) { _ in exit(0) }

do {
    let output = try PTYSession.run(binaryPath: binaryPath, spec: spec, environment: env)
    FileHandle.standardOutput.write(Data(output.utf8))
} catch {
    fail(String(describing: error))
}
