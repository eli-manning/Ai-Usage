import Foundation
import JavaScriptCore

/// Connects each provider's CLI to the minis by adding a hook to its config,
/// or takes it back out.
///
/// Every provider gets the same tiny shell script, copied into its own config
/// folder (no spaces in those paths, so it works whether or not the CLI runs
/// hooks through a shell). The script hands the event to `HookServer` on
/// 127.0.0.1 in the background and exits at once, so it never slows down or
/// fails the CLI. Configs are backed up before every write, and everything
/// else in them is kept, in the same order.
public enum HookInstaller {

    /// The port `HookServer` listens on. Mochi uses 47833, so both can run.
    public static let port: UInt16 = 47834

    /// Overridable so tests can point it at a temporary folder.
    public static var home = FileManager.default.homeDirectoryForCurrentUser

    public struct Target {
        public let provider: String
        /// The config file the hook goes into.
        public var config: URL { HookInstaller.home.appendingPathComponent(relativeConfig) }
        let relativeConfig: String
        /// Hook event names to register.
        let events: [String]
        /// Events that take a tool-name matcher (Antigravity requires one).
        let matcherEvents: [String]
        /// How the config file is laid out — see `configureJS`.
        let format: String
        /// Something the user still has to do after connecting, if anything.
        public let followUp: String?

        var script: URL { config.deletingLastPathComponent().appendingPathComponent("hooks/aiusage-minis.sh") }
        var backup: URL { config.appendingPathExtension("aiusage-backup") }
    }

    public static let targets: [String: Target] = [
        "claude": Target(
            provider: "claude",
            relativeConfig: ".claude/settings.json",
            events: ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
                     "PermissionRequest", "Notification", "Stop", "StopFailure", "SubagentStart", "PreCompact"],
            matcherEvents: [], format: "claude",
            followUp: "Restart running Claude Code sessions to pick it up."),
        "codex": Target(
            provider: "codex",
            relativeConfig: ".codex/hooks.json",
            events: ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest",
                     "PreCompact", "Stop", "Interrupt"],
            matcherEvents: [], format: "codex",
            followUp: "Codex runs new hooks only after you approve them: open Codex and type /hooks."),
        // Cursor's before* hooks gate the action and block it on unexpected
        // output, so only the after-the-fact events are used: nothing here can
        // ever stop Cursor doing something.
        "cursor": Target(
            provider: "cursor",
            relativeConfig: ".cursor/hooks.json",
            events: ["sessionStart", "sessionEnd", "beforeSubmitPrompt", "afterAgentThought", "postToolUse",
                     "postToolUseFailure", "afterShellExecution", "afterFileEdit", "afterMCPExecution", "preCompact", "stop"],
            matcherEvents: [], format: "cursor",
            followUp: "Restart Cursor or cursor-agent to pick it up."),
        // Same reasoning: PreToolUse decides whether a tool may run, so it's
        // left alone. Antigravity's payload names neither the event nor the
        // session, so the script passes both along itself.
        "antigravity": Target(
            provider: "antigravity",
            relativeConfig: ".gemini/antigravity-cli/hooks.json",
            events: ["PreInvocation", "PostToolUse", "Stop"],
            matcherEvents: ["PostToolUse"], format: "antigravity",
            followUp: "Restart agy to pick it up. Antigravity reports less than the others: no permission prompts."),
    ]

    public static func isInstalled(_ provider: String) -> Bool {
        guard let t = targets[provider], let text = try? String(contentsOf: t.config, encoding: .utf8) else { return false }
        return text.contains("aiusage-minis.sh")
    }

    /// Whether the CLI has a config folder at all — i.e. it's been run here.
    public static func canInstall(_ provider: String) -> Bool {
        guard let t = targets[provider] else { return false }
        return FileManager.default.fileExists(atPath: t.config.deletingLastPathComponent().path)
    }

    public static func setInstalled(_ provider: String, _ on: Bool) throws {
        guard let t = targets[provider] else { return }
        let fm = FileManager.default
        let text = (try? String(contentsOf: t.config, encoding: .utf8)) ?? ""
        if on { try writeScript(t) }

        // Done in JavaScript so the file keeps its key order and formatting.
        let ctx = JSContext()!
        ctx.evaluateScript(configureJS)
        let command = t.script.path + " " + provider
        let r = ctx.objectForKeyedSubscript("configure")
            .call(withArguments: [text, on, t.format, t.events, command, t.matcherEvents])
        if let err = ctx.exception?.toString() ?? r?.objectForKeyedSubscript("error")?.toString(), err != "undefined" {
            throw NSError(domain: "AiUsage", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "\(t.config.lastPathComponent): \(err)"])
        }
        guard let out = r?.objectForKeyedSubscript("text")?.toString() else { return }

        try fm.createDirectory(at: t.config.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: t.config.path) {
            try? fm.removeItem(at: t.backup)
            try fm.copyItem(at: t.config, to: t.backup)
        }
        try out.write(to: t.config, atomically: true, encoding: .utf8)
        if !on { try? fm.removeItem(at: t.script) }
    }

    /// Rewrites the scripts of every connected provider, so an app update's
    /// script changes reach hooks that were connected by an older version.
    public static func refreshScripts() {
        for t in targets.values where isInstalled(t.provider) { try? writeScript(t) }
    }

    private static func writeScript(_ t: Target) throws {
        let script = """
        #!/bin/sh
        # AI Usage minis: hands this \(t.provider) hook event to AI Usage, on this Mac only.
        # Runs the hand-off in the background and exits at once: it never slows down or fails the CLI.
        provider="$1"; event="$2"
        body=$(cat)
        # Codex requires JSON from a Stop hook; Antigravity from every hook. An empty object changes nothing.
        case "$provider:$event" in
          codex:Stop|antigravity:*) printf '{}' ;;
        esac
        [ -n "$AIUSAGE_PROBE" ] && exit 0   # AI Usage itself reading usage: not a session anyone is working in
        printf '%s' "$body" | /usr/bin/curl -s -m 2 -o /dev/null -H 'X-AiUsage: 1' -H "X-Pid: $PPID" \\
          -H "X-Event: $event" -H "X-Session: ${ANTIGRAVITY_CONVERSATION_ID:-}" -H 'Content-Type: application/json' \\
          --data-binary @- "http://127.0.0.1:\(port)/hook/$provider" >/dev/null 2>&1 &
        exit 0

        """
        let fm = FileManager.default
        try fm.createDirectory(at: t.script.deletingLastPathComponent(), withIntermediateDirectories: true)
        try script.write(to: t.script, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: t.script.path)
    }

    /// Formats:
    ///  - claude / codex: `{hooks: {Event: [{matcher?, hooks: [{type, command}]}]}}`
    ///  - cursor:         `{version: 1, hooks: {event: [{command}]}}`
    ///  - antigravity:    `{<group>: {Event: [{matcher?, hooks: [{type, command}]}]}}`
    private static let configureJS = #"""
    function configure(text, on, fmt, events, command, matcherEvents) {
      var s = text.trim() ? JSON.parse(text) : {};
      if (!s || typeof s !== 'object' || Array.isArray(s)) return { error: 'must be a JSON object.' };
      var mine = function (h) { return h && typeof h.command === 'string' && h.command.indexOf('aiusage-minis.sh') !== -1; };
      var handler = function (ev) {
        var h = { type: 'command', command: command + ' ' + ev };
        if (fmt === 'claude') h.async = true;
        if (fmt === 'codex' || fmt === 'antigravity') h.timeout = 3;
        return h;
      };
      if (fmt === 'antigravity') {
        delete s['aiusage-minis'];
        if (on) {
          var group = {};
          events.forEach(function (ev) {
            var g = { hooks: [handler(ev)] };
            if (matcherEvents.indexOf(ev) !== -1) g = { matcher: '*', hooks: g.hooks };
            group[ev] = [g];
          });
          s['aiusage-minis'] = group;
        }
        return { text: JSON.stringify(s, null, 2) + '\n' };
      }
      if (fmt === 'cursor' && on && s.version == null) s.version = 1;
      var hooks = s.hooks && typeof s.hooks === 'object' ? s.hooks : {};
      Object.keys(hooks).forEach(function (ev) {
        if (!Array.isArray(hooks[ev])) return;
        var kept = hooks[ev].filter(function (e) { return !mine(e); }).map(function (g) {
          return Array.isArray(g.hooks) ? Object.assign({}, g, { hooks: g.hooks.filter(function (h) { return !mine(h); }) }) : g;
        }).filter(function (g) { return !Array.isArray(g.hooks) || g.hooks.length; });
        if (kept.length) hooks[ev] = kept; else delete hooks[ev];
      });
      if (on) events.forEach(function (ev) {
        var entry = fmt === 'cursor' ? { command: command + ' ' + ev } : { hooks: [handler(ev)] };
        hooks[ev] = (hooks[ev] || []).concat([entry]);
      });
      if (Object.keys(hooks).length) s.hooks = hooks; else delete s.hooks;
      if (fmt === 'cursor' && !s.hooks && Object.keys(s).length === 1 && s.version === 1) return { text: '{}\n' };
      return { text: JSON.stringify(s, null, 2) + '\n' };
    }
    """#
}
