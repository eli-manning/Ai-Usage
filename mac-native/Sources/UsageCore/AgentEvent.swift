import Foundation

/// What kind of work a tool call is. Picks the mini's pose and the word it
/// says, and is the same vocabulary for every provider — each CLI names its
/// tools differently (`Edit`, `apply_patch`, `edit_file`, `write_to_file`…),
/// so the mapping lives here rather than in four places in the UI.
public enum AgentActivity: String, Codable, Sendable, CaseIterable {
    case thinking, reading, editing, searching, browsing, running, testing,
         committing, delegating, planning, compacting, tool
}

/// One hook event from any provider's CLI, reduced to what the minis need.
///
/// The raw payloads differ per provider (Claude and Codex share a schema,
/// Cursor's is camelCase with `conversation_id`, Antigravity's carries no
/// event name at all), so `HookNormalizer` folds them into this.
public struct AgentEvent: Equatable, Sendable {
    public enum Kind: String, Sendable {
        /// A session opened. Spawns the mini without alerting.
        case sessionStart
        /// You sent a prompt.
        case prompt
        /// The model is thinking between tool calls.
        case thought
        case toolStart
        /// A tool finished. Providers that only report *after* a tool ran
        /// (Cursor, Antigravity) show their activity from this alone.
        case toolEnd
        case toolFailed
        case compact
        /// Waiting on you: a permission prompt or a question.
        case needsInput
        /// The turn finished and it's your move.
        case done
        /// The turn ended in an error.
        case failed
        /// You interrupted it. Back to idle, nothing to alert about.
        case interrupted
        case sessionEnd
    }

    public var provider: String
    public var sessionID: String
    public var kind: Kind
    public var activity: AgentActivity?
    /// The file, command or search being worked on — short, for a bubble.
    public var detail: String
    public var cwd: String

    public init(provider: String, sessionID: String, kind: Kind,
                activity: AgentActivity? = nil, detail: String = "", cwd: String = "") {
        self.provider = provider
        self.sessionID = sessionID
        self.kind = kind
        self.activity = activity
        self.detail = detail
        self.cwd = cwd
    }
}

/// Turns each provider's raw hook JSON into an `AgentEvent`.
public enum HookNormalizer {

    /// - Parameters:
    ///   - provider: which CLI sent it (`Provider.id`).
    ///   - event: the event name when the hook script had to pass it itself,
    ///     because the payload doesn't carry one (Antigravity).
    ///   - session: a session id from the hook's environment, for the same reason.
    ///   - json: the payload the CLI wrote to the hook's stdin.
    /// - Returns: nil for events with nothing to show (sub-agent chatter,
    ///   idle-prompt notifications, events this app doesn't use).
    public static func normalize(provider: String, event: String?, session: String?,
                                 json: [String: Any]) -> AgentEvent? {
        let name = (json["hook_event_name"] as? String) ?? (json["hookEventName"] as? String) ?? event ?? ""
        let sid = firstString(json, ["session_id", "conversation_id", "conversationId", "sessionId"])
            ?? session ?? ""
        let cwd = firstString(json, ["cwd"])
            ?? (json["workspace_roots"] as? [String])?.first
            ?? ""
        guard !name.isEmpty else { return nil }

        let tool = toolName(json)
        let input = toolInput(json)
        func ev(_ kind: AgentEvent.Kind, _ activity: AgentActivity? = nil, _ detail: String = "") -> AgentEvent {
            AgentEvent(provider: provider, sessionID: sid.isEmpty ? "default" : sid, kind: kind,
                       activity: activity, detail: detail, cwd: cwd)
        }

        switch provider {
        case "cursor":
            return cursor(name, json: json, tool: tool, input: input, ev)
        case "antigravity":
            return antigravity(name, tool: tool, input: input, ev)
        default:
            // Claude Code and Codex share event names and payload shape.
            // A sub-agent's own tool calls carry its agent_id: they'd make the
            // parent look busy with work it isn't doing itself, so skip them.
            if let agent = json["agent_id"] as? String, !agent.isEmpty,
               !["SubagentStart", "SubagentStop"].contains(name) { return nil }
            switch name {
            case "SessionStart": return ev(.sessionStart)
            case "UserPromptSubmit": return ev(.prompt)
            case "PreToolUse": return ev(.toolStart, activity(tool, input), detail(tool, input))
            case "PostToolUse": return ev(.toolEnd, activity(tool, input), detail(tool, input))
            case "PostToolUseFailure":
                if json["is_interrupt"] as? Bool == true { return ev(.interrupted) }
                return ev(.toolFailed, activity(tool, input), detail(tool, input))
            case "PermissionRequest": return ev(.needsInput, activity(tool, input), detail(tool, input))
            case "Notification":
                // Claude Code also notifies "waiting for your input" after it's
                // done, and for logins — the Stop event already covers the first.
                switch json["notification_type"] as? String ?? "" {
                case "permission_prompt", "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input":
                    return ev(.needsInput)
                default: return nil
                }
            case "SubagentStart": return ev(.toolStart, .delegating)
            case "PreCompact": return ev(.compact, .compacting)
            case "Stop": return ev(.done)
            case "StopFailure": return ev(.failed)
            case "Interrupt": return ev(.interrupted)
            case "SessionEnd": return ev(.sessionEnd)
            default: return nil
            }
        }
    }

    private static func cursor(_ name: String, json: [String: Any], tool: String, input: [String: Any],
                               _ ev: (AgentEvent.Kind, AgentActivity?, String) -> AgentEvent) -> AgentEvent? {
        switch name {
        case "sessionStart": return ev(.sessionStart, nil, "")
        case "beforeSubmitPrompt": return ev(.prompt, nil, "")
        case "afterAgentThought", "afterAgentResponse": return ev(.thought, .thinking, "")
        case "preToolUse": return ev(.toolStart, activity(tool, input), detail(tool, input))
        case "postToolUse": return ev(.toolEnd, activity(tool, input), detail(tool, input))
        case "afterShellExecution":
            let cmd = json["command"] as? String ?? ""
            return ev(.toolEnd, commandActivity(cmd), short(cmd, 44))
        case "afterFileEdit":
            let f = json["file_path"] as? String ?? ""
            return ev(.toolEnd, .editing, (f as NSString).lastPathComponent)
        case "afterMCPExecution": return ev(.toolEnd, .tool, short(tool, 40))
        case "postToolUseFailure":
            if json["is_interrupt"] as? Bool == true { return ev(.interrupted, nil, "") }
            return ev(.toolFailed, activity(tool, input), detail(tool, input))
        case "subagentStart": return ev(.toolStart, .delegating, "")
        case "preCompact": return ev(.compact, .compacting, "")
        case "stop":
            switch json["status"] as? String ?? "completed" {
            case "error": return ev(.failed, nil, "")
            case "aborted": return ev(.interrupted, nil, "")
            default: return ev(.done, nil, "")
            }
        case "sessionEnd": return ev(.sessionEnd, nil, "")
        default: return nil
        }
    }

    private static func antigravity(_ name: String, tool: String, input: [String: Any],
                                    _ ev: (AgentEvent.Kind, AgentActivity?, String) -> AgentEvent) -> AgentEvent? {
        switch name {
        case "PreInvocation", "PostInvocation": return ev(.thought, .thinking, "")
        case "PreToolUse": return ev(.toolStart, activity(tool, input), detail(tool, input))
        case "PostToolUse": return ev(.toolEnd, activity(tool, input), detail(tool, input))
        case "Stop": return ev(.done, nil, "")
        default: return nil
        }
    }

    // MARK: - Tools

    static func toolName(_ json: [String: Any]) -> String {
        if let t = firstString(json, ["tool_name", "toolName"]) { return t }
        if let call = json["toolCall"] as? [String: Any] ?? json["tool_call"] as? [String: Any] {
            return firstString(call, ["name", "toolName", "tool_name"]) ?? ""
        }
        return ""
    }

    static func toolInput(_ json: [String: Any]) -> [String: Any] {
        if let i = json["tool_input"] as? [String: Any] { return i }
        // Cursor sends MCP tool input as a JSON string.
        if let s = json["tool_input"] as? String, let d = s.data(using: .utf8),
           let i = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] { return i }
        if let call = json["toolCall"] as? [String: Any] ?? json["tool_call"] as? [String: Any] {
            return call["args"] as? [String: Any] ?? call["arguments"] as? [String: Any] ?? [:]
        }
        return [:]
    }

    /// The kind of work a tool call is, across every provider's tool names.
    public static func activity(_ tool: String, _ input: [String: Any]) -> AgentActivity {
        let t = tool.lowercased()
        if t.hasPrefix("mcp__") || t.hasPrefix("mcp_") { return .tool }
        switch t {
        case "read", "notebookread", "read_file", "view_file", "view_file_outline", "view_code_item", "cat":
            return .reading
        case "edit", "write", "multiedit", "notebookedit", "apply_patch", "edit_file", "write_file",
             "write_to_file", "replace_file_content", "multi_replace_file_content", "search_replace", "delete_file":
            return .editing
        case "grep", "glob", "ls", "list_dir", "grep_search", "codebase_search", "file_search",
             "find_by_name", "search", "list_files":
            return .searching
        case "websearch", "webfetch", "web_search", "search_web", "read_url_content", "fetch", "browser":
            return .browsing
        case "task", "agent", "spawn_agent", "subagent", "invoke_subagent":
            return .delegating
        case "todowrite", "taskcreate", "taskupdate", "update_plan", "todo_write":
            return .planning
        case "bash", "bashoutput", "shell", "local_shell", "exec_command", "run_command",
             "run_terminal_cmd", "run_terminal_command", "unified_exec", "terminal":
            return commandActivity(command(input))
        default:
            return .tool
        }
    }

    static func commandActivity(_ command: String) -> AgentActivity {
        if command.range(of: #"\bgit\s+(commit|push)\b"#, options: .regularExpression) != nil { return .committing }
        if command.range(of: #"\b(test|tests|jest|vitest|pytest|mocha|playwright|rspec|xcodebuild test|swift test|go test|cargo test)\b"#,
                         options: .regularExpression) != nil { return .testing }
        return .running
    }

    /// The command a shell tool is running. Codex passes argv as an array
    /// (`["bash", "-lc", "…"]`); Antigravity calls it `CommandLine`.
    static func command(_ input: [String: Any]) -> String {
        if let c = firstString(input, ["command", "cmd", "CommandLine", "commandLine"]) { return c }
        if let argv = (input["command"] ?? input["cmd"]) as? [String] { return argv.last ?? "" }
        return ""
    }

    /// The bit worth saying: a file name, a command, a search.
    public static func detail(_ tool: String, _ input: [String: Any]) -> String {
        if let f = firstString(input, ["file_path", "notebook_path", "path", "target_file", "TargetFile",
                                       "AbsolutePath", "filePath"]) {
            return (f as NSString).lastPathComponent
        }
        if let u = firstString(input, ["url", "Url"]) { return URL(string: u)?.host ?? short(u, 40) }
        if tool.lowercased() == "apply_patch", let p = input["input"] as? String ?? input["patch"] as? String,
           let m = p.range(of: #"\*\*\* (Update|Add|Delete) File: (\S+)"#, options: .regularExpression) {
            return (String(p[m]).components(separatedBy: " ").last.map { ($0 as NSString).lastPathComponent }) ?? ""
        }
        for key in ["description", "pattern", "query", "Query", "subject"] {
            if let s = input[key] as? String, !s.isEmpty { return short(s, 44) }
        }
        let cmd = command(input)
        if !cmd.isEmpty { return short(cmd, 44) }
        if tool.hasPrefix("mcp__") { return short(tool.components(separatedBy: "__").dropFirst().joined(separator: " "), 40) }
        return ""
    }

    static func short(_ s: String, _ n: Int) -> String {
        let t = s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return t.count > n ? String(t.prefix(n - 1)) + "…" : t
    }

    private static func firstString(_ d: [String: Any], _ keys: [String]) -> String? {
        for k in keys { if let s = d[k] as? String, !s.isEmpty { return s } }
        return nil
    }
}
