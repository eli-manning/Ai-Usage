import Darwin
import Foundation

/// Drives a provider CLI inside a real pseudo-terminal and captures what it
/// renders — the native replacement for os-menu's four `*-pty-wrapper.py`
/// scripts.
///
/// These CLIs render a TUI and need a real terminal to produce normal output;
/// there is also no natural "process exited" signal for a TUI, so completion
/// is decided by idle detection (the screen going quiet) plus, for the
/// interactive drivers, a marker proving the panel we asked for actually
/// painted.
///
/// ## Why this runs in its own executable
/// The child is created with `posix_spawn` + `POSIX_SPAWN_SETSID` rather than
/// `fork`, which Swift refuses to expose at all. That turns out to be the
/// better primitive anyway: the child becomes its own session and process
/// group leader, so `killpg` below reaches every subprocess it spawned (a
/// sandboxed helper, an MCP server) instead of orphaning them to init.
///
/// The controlling terminal is acquired the BSD way — the child `open()`s the
/// slave *without* `O_NOCTTY` after `setsid`, which makes it the session's
/// controlling tty. The parent holds its own slave fd open across the spawn
/// purely so the window size stamped on the device sticks; drop it too early
/// and the child comes up 0×0 and truncates its own output.
public final class PTYSession {

    /// Per-provider driving rules. The Python wrappers were four near-copies
    /// differing only in these constants and which command they typed; this is
    /// that difference, extracted.
    public struct DriveSpec {
        /// Extra argv beyond the binary path itself.
        public var arguments: [String] = []

        /// Passed as `claude /usage`-style argv. Claude Code is the only CLI
        /// here that honours a slash command given as an argument; the others
        /// treat it as a literal chat prompt and answer it with fabricated
        /// prose, so they have to be driven by typing instead.
        public var argvCommand: String?

        /// Typed into the running TUI once `readyMarker` shows up.
        public var typedCommand: String?
        /// First appears once the CLI's ready prompt is up.
        public var readyMarker: String?
        /// Only present once the panel we asked for has actually rendered.
        public var panelMarker: String?

        /// Hard cap on the whole capture.
        public var totalTimeout: TimeInterval = 20
        /// No new bytes for this long ⇒ screen considered settled.
        public var idleQuiet: TimeInterval = 0.8
        /// Ignore idle detection until at least this much has elapsed, so a
        /// startup animation's first pause doesn't read as "done".
        public var minElapsed: TimeInterval = 1.0

        /// Claude writes a small fixed terminal-setup preamble (mode-set
        /// escapes, a device-attributes query, ~60–90 bytes) before it ever
        /// draws its first real frame, and occasionally pauses noticeably
        /// longer than `idleQuiet` between the two. With no byte floor, idle
        /// detection reads that pause as "screen settled" and kills the
        /// process right there, capturing nothing but the preamble. Given a
        /// longer leash instead, those runs render normally within ~2s — so
        /// don't let idle detection conclude "done" until real content has
        /// actually arrived. `totalTimeout` still bounds a genuinely hung CLI.
        public var minBytesForIdleDone = 0

        /// After the command is typed, wait this long before pressing Enter.
        public var enterDelayAfterCommand: TimeInterval = 1.0

        /// A cold session can have a real network round-trip between the
        /// command executing and the panel painting — `idleQuiet` of terminal
        /// silence can land right in that gap (server latency, not idleness),
        /// grabbing a screen before the panel rendered. Requiring
        /// `panelMarker` guards that, and this bounds the wait so a
        /// changed/missing marker can't hang the capture forever.
        public var panelFallbackTimeout: TimeInterval = 10

        /// First-run onboarding (colour scheme, workspace trust, a
        /// live-generated tutorial preview) blocks the ready prompt — nudge
        /// through it with Enter, capped so a stuck or offline sign-in can't
        /// spin forever. Zero disables the nudge entirely.
        public var wizardNudgeTimeout: TimeInterval = 0
        public var wizardNudgeInterval: TimeInterval = 1.2

        /// Auto-answer a prompt containing this substring by pressing Enter.
        /// Claude's directory-trust prompt has ANSI sequences between its
        /// words, so this matches a single word rather than the full phrase.
        public var autoAnswerMarker: String?

        public init() {}
    }

    // MARK: - Built-in specs
    //
    // Constants lifted verbatim from the tray app's hardened wrappers; see
    // mac-native/README.md for the file-by-file provenance.

    public static func spec(for provider: String, command: String? = nil) -> DriveSpec? {
        switch provider {
        case "claude":
            var s = DriveSpec()
            s.argvCommand = command ?? "/usage"
            s.totalTimeout = 20
            s.idleQuiet = 0.8
            s.minElapsed = 1.0
            s.minBytesForIdleDone = 300
            s.autoAnswerMarker = "safety"
            return s

        case "antigravity", "agy":
            var s = DriveSpec()
            s.typedCommand = "/usage"
            s.readyMarker = "for shortcuts"
            s.panelMarker = "GEMINI MODELS"
            s.idleQuiet = 1.0
            s.totalTimeout = 55
            s.panelFallbackTimeout = 10
            s.wizardNudgeTimeout = 35
            return s

        case "codex":
            var s = DriveSpec()
            s.typedCommand = "/status"
            s.readyMarker = "to change"
            s.panelMarker = "Account:"
            s.idleQuiet = 1.0
            s.totalTimeout = 20
            s.panelFallbackTimeout = 10
            return s

        case "cursor":
            var s = DriveSpec()
            s.arguments = ["--trust"]
            s.typedCommand = "/usage"
            s.readyMarker = "Auto"
            s.panelMarker = "Esc to close"
            s.idleQuiet = 1.2
            s.totalTimeout = 25
            s.panelFallbackTimeout = 10
            return s

        default:
            return nil
        }
    }

    // MARK: - Running

    public enum RunError: Error, CustomStringConvertible {
        case ptyUnavailable(String)
        case spawnFailed(Int32)

        public var description: String {
            switch self {
            case .ptyUnavailable(let step): return "Could not allocate a pseudo-terminal (\(step))."
            case .spawnFailed(let code): return "Could not launch the CLI (errno \(code))."
            }
        }
    }

    /// Runs `binaryPath` under `spec` and returns everything it rendered.
    /// Always returns whatever was captured, even on timeout — the parsers
    /// upstream are what decide whether a partial screen is usable.
    public static func run(binaryPath: String, spec: DriveSpec,
                           environment: [String: String]) throws -> String {

        // ── Allocate the PTY ────────────────────────────────────────────────
        let master = posix_openpt(O_RDWR | O_NOCTTY)
        guard master >= 0 else { throw RunError.ptyUnavailable("posix_openpt") }
        guard grantpt(master) == 0 else { close(master); throw RunError.ptyUnavailable("grantpt") }
        guard unlockpt(master) == 0 else { close(master); throw RunError.ptyUnavailable("unlockpt") }
        guard let namePtr = ptsname(master) else {
            close(master); throw RunError.ptyUnavailable("ptsname")
        }
        let slavePath = String(cString: namePtr)

        // The default 24×80 truncates content past row 24 — /stats runs well
        // past that. Grow the device so the TUI renders everything in one
        // frame. Held open across the spawn so the size sticks (see the type
        // comment); the child opens its own fd to acquire the ctty.
        let slave = open(slavePath, O_RDWR | O_NOCTTY)
        if slave >= 0 {
            var ws = winsize(ws_row: 60, ws_col: 200, ws_xpixel: 0, ws_ypixel: 0)
            _ = ioctl(slave, TIOCSWINSZ, &ws)
        }
        defer { if slave >= 0 { close(slave) } }

        // ── Spawn ───────────────────────────────────────────────────────────
        var fileActions = posix_spawn_file_actions_t(bitPattern: 0)
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        // No O_NOCTTY here: opening the slave in the fresh session is exactly
        // what makes it the controlling terminal.
        posix_spawn_file_actions_addopen(&fileActions, 0, slavePath, O_RDWR, 0)
        posix_spawn_file_actions_adddup2(&fileActions, 0, 1)
        posix_spawn_file_actions_adddup2(&fileActions, 0, 2)

        var attrs = posix_spawnattr_t(bitPattern: 0)
        posix_spawnattr_init(&attrs)
        defer { posix_spawnattr_destroy(&attrs) }
        // POSIX_SPAWN_SETSID — the child leads its own session and process
        // group, which is what makes killpg below able to reap its whole tree.
        posix_spawnattr_setflags(&attrs, Int16(0x0400))

        var argv: [String] = [binaryPath]
        argv.append(contentsOf: spec.arguments)
        if let cmd = spec.argvCommand { argv.append(cmd) }

        var cArgv: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) }
        cArgv.append(nil)
        var cEnv: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") }
        cEnv.append(nil)
        defer {
            for p in cArgv where p != nil { free(p) }
            for p in cEnv where p != nil { free(p) }
        }

        // Run from home so a CLI that records a per-directory trust decision
        // saves it somewhere stable instead of re-prompting every launch.
        let previousCWD = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(NSHomeDirectory())
        var pid: pid_t = 0
        let rc = posix_spawn(&pid, binaryPath, &fileActions, &attrs, &cArgv, &cEnv)
        FileManager.default.changeCurrentDirectoryPath(previousCWD)
        guard rc == 0 else { close(master); throw RunError.spawnFailed(rc) }

        // ── Drive and capture ───────────────────────────────────────────────
        var buffer = Data()
        let start = Date()
        var lastData = start
        var lastEnter = Date.distantPast
        var readySeenAt: Date?
        var typedCommand = false
        var commandSentAt: Date?
        var enterAfterCommandAt: Date?
        var autoAnswered = false

        // Markers are matched against the raw byte stream, exactly as the
        // Python wrappers did — the rendered-grid reconstruction happens later
        // in the parsers, and these markers were all chosen to survive the raw
        // form.
        func bufferContains(_ needle: String) -> Bool {
            guard let n = needle.data(using: .utf8) else { return false }
            return buffer.range(of: n) != nil
        }
        func writeToChild(_ s: String) {
            guard let d = s.data(using: .utf8) else { return }
            _ = d.withUnsafeBytes { raw in
                write(master, raw.baseAddress, raw.count)
            }
        }

        var readBuf = [UInt8](repeating: 0, count: 8192)

        while true {
            let now = Date()
            if now.timeIntervalSince(start) > spec.totalTimeout { break }

            var pfd = pollfd(fd: master, events: Int16(POLLIN), revents: 0)
            if poll(&pfd, 1, 100) > 0 && (pfd.revents & Int16(POLLIN)) != 0 {
                let n = read(master, &readBuf, readBuf.count)
                if n <= 0 { break }
                buffer.append(contentsOf: readBuf[0..<n])
                lastData = Date()

                if let marker = spec.autoAnswerMarker, !autoAnswered,
                   bufferContains(marker) || bufferContains(marker.lowercased()) {
                    autoAnswered = true
                    usleep(100_000)
                    writeToChild("\r")
                    // Don't let the trust prompt itself read as "settled".
                    lastData = Date()
                }
            }

            let tick = Date()
            let idleFor = tick.timeIntervalSince(lastData)
            let elapsed = tick.timeIntervalSince(start)

            // ── Interactive drive sequence ──────────────────────────────────
            if let readyMarker = spec.readyMarker {
                if readySeenAt == nil && bufferContains(readyMarker) {
                    readySeenAt = tick
                }

                if readySeenAt == nil, spec.wizardNudgeTimeout > 0,
                   idleFor > spec.idleQuiet,
                   tick.timeIntervalSince(lastEnter) > spec.wizardNudgeInterval,
                   elapsed < spec.wizardNudgeTimeout {
                    writeToChild("\r")
                    lastEnter = tick
                }

                if let readyAt = readySeenAt, !typedCommand, let cmd = spec.typedCommand,
                   idleFor > spec.idleQuiet, tick.timeIntervalSince(readyAt) > 0.3 {
                    writeToChild(cmd)
                    typedCommand = true
                    commandSentAt = tick
                    lastData = tick
                }

                if typedCommand, enterAfterCommandAt == nil, let sentAt = commandSentAt,
                   tick.timeIntervalSince(sentAt) > spec.enterDelayAfterCommand {
                    writeToChild("\r")
                    enterAfterCommandAt = tick
                }

                if let enteredAt = enterAfterCommandAt, idleFor > spec.idleQuiet {
                    let panelUp = spec.panelMarker.map { bufferContains($0) } ?? true
                    if panelUp || tick.timeIntervalSince(enteredAt) > spec.panelFallbackTimeout {
                        break
                    }
                }
            } else {
                // ── Plain idle detection (Claude) ───────────────────────────
                if elapsed > spec.minElapsed, idleFor > spec.idleQuiet,
                   buffer.count > spec.minBytesForIdleDone {
                    break
                }
            }

            // If the child already exited, stop reading.
            var status: Int32 = 0
            if waitpid(pid, &status, WNOHANG) != 0 { break }
        }

        close(master)
        killAndReap(pid)

        return String(decoding: buffer, as: UTF8.self)
    }

    /// Terminates the child's whole process group, escalating to SIGKILL.
    ///
    /// A fully-authenticated CLI can keep a background refresh loop alive that
    /// doesn't reliably exit on SIGTERM — whether it ignores the signal or
    /// hangs in its own shutdown path, a plain SIGTERM leaves it orphaned
    /// indefinitely (reparented to init, still holding live connections,
    /// observed days later). SIGKILL can't be caught, blocked or ignored, so
    /// escalate to it if SIGTERM hasn't reaped the group within a short grace.
    ///
    /// `killpg`, not `kill`: the child leads its own process group, so
    /// anything it spawned is in there too. Signalling just `pid` only ever
    /// killed the CLI's top-level process and orphaned the rest.
    private static func killAndReap(_ pid: pid_t) {
        // Once cleanup starts, a second external SIGTERM aimed at *us* must
        // not unwind this function before the escalation below — that was
        // silently orphaning children. Ignore it for the remainder of cleanup;
        // SIGKILL still applies regardless.
        let previous = signal(SIGTERM, SIG_IGN)
        defer { signal(SIGTERM, previous) }

        if killpg(pid, SIGTERM) != 0 {
            // Group already gone; still reap in case it's a zombie.
            var status: Int32 = 0
            _ = waitpid(pid, &status, WNOHANG)
            return
        }

        let deadline = Date().addingTimeInterval(2.0)
        while Date() < deadline {
            var status: Int32 = 0
            if waitpid(pid, &status, WNOHANG) != 0 { return }
            usleep(50_000)
        }

        _ = killpg(pid, SIGKILL)
        var status: Int32 = 0
        _ = waitpid(pid, &status, 0)
    }
}
