import Foundation

/// Finds provider CLIs on disk, and fixes up the PATH they need to be found on.
public enum CLILocator {

    /// A GUI-launched app inherits a bare-bones PATH (roughly
    /// `/usr/bin:/bin:/usr/sbin:/sbin` plus whatever `/etc/paths.d` adds
    /// system-wide) — nothing a shell rc file adds only for *interactive*
    /// shells, like `~/.local/bin` where `cursor-agent` actually lives, ever
    /// makes it in. Without this, a CLI installed exactly the way its own
    /// installer's docs say to still reads as "not installed".
    public static let extraPaths: [String] = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        NSHomeDirectory() + "/.local/bin",
        NSHomeDirectory() + "/.npm-global/bin",
    ]

    public static func augmentedPATH(_ existing: String?) -> String {
        (extraPaths + [existing ?? ""]).filter { !$0.isEmpty }.joined(separator: ":")
    }

    public static func augmentedEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = augmentedPATH(env["PATH"])
        return env
    }

    /// Known install locations, checked when `which` comes up empty. Ordered
    /// most-likely-first per provider, mirroring `findClaudePath` /
    /// `findAgyPath` / `findCodexPath` / `findCursorPath` in os-menu.
    private static func fallbackPaths(for binary: String) -> [String] {
        let home = NSHomeDirectory()
        switch binary {
        case "claude":
            return ["/usr/local/bin/claude", "/usr/bin/claude",
                    "\(home)/.local/bin/claude", "\(home)/.npm-global/bin/claude",
                    "/opt/homebrew/bin/claude"]
        case "agy":
            return ["/opt/homebrew/bin/agy", "/usr/local/bin/agy", "/usr/bin/agy",
                    "\(home)/.local/bin/agy"]
        case "codex":
            return ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "/usr/bin/codex",
                    "\(home)/.local/bin/codex"]
        case "cursor-agent":
            return ["\(home)/.local/bin/cursor-agent", "/opt/homebrew/bin/cursor-agent",
                    "/usr/local/bin/cursor-agent"]
        default:
            return extraPaths.map { "\($0)/\(binary)" }
        }
    }

    /// Resolves a binary to a full path, or `nil` if it genuinely isn't there.
    /// Does the `which` lookup by hand rather than shelling out — one `stat`
    /// per candidate directory beats spawning a subprocess, and this runs on
    /// every refresh for every provider.
    public static func find(_ binary: String) -> String? {
        let fm = FileManager.default
        let pathDirs = augmentedPATH(ProcessInfo.processInfo.environment["PATH"])
            .split(separator: ":").map(String.init)

        for dir in pathDirs where !dir.isEmpty {
            let candidate = (dir as NSString).appendingPathComponent(binary)
            if fm.isExecutableFile(atPath: candidate) { return candidate }
        }
        for candidate in fallbackPaths(for: binary) {
            if fm.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    public static func isInstalled(_ binary: String) -> Bool {
        find(binary) != nil
    }
}
