import XCTest
@testable import UsageCore

/// The hook payloads each provider sends, and the alert rules the minis follow:
/// an alert goes up when a turn finishes or a session needs you, and stays up
/// until you respond in that session or acknowledge it.
final class AgentSessionTests: XCTestCase {

    private func norm(_ provider: String, _ json: [String: Any], event: String? = nil, session: String? = nil) -> AgentEvent? {
        HookNormalizer.normalize(provider: provider, event: event, session: session, json: json)
    }

    // MARK: - Normalising

    func testClaudeToolCall() throws {
        let e = try XCTUnwrap(norm("claude", [
            "hook_event_name": "PreToolUse", "session_id": "s1", "cwd": "/Users/me/app",
            "tool_name": "Edit", "tool_input": ["file_path": "/Users/me/app/Sources/App.swift"],
        ]))
        XCTAssertEqual(e.kind, .toolStart)
        XCTAssertEqual(e.activity, .editing)
        XCTAssertEqual(e.detail, "App.swift")
        XCTAssertEqual(e.sessionID, "s1")
        XCTAssertEqual(e.cwd, "/Users/me/app")
    }

    func testClaudeIdlePromptNotificationIsIgnored() {
        XCTAssertNil(norm("claude", ["hook_event_name": "Notification", "session_id": "s1", "notification_type": "idle_prompt"]))
        XCTAssertEqual(norm("claude", ["hook_event_name": "Notification", "session_id": "s1",
                                       "notification_type": "permission_prompt"])?.kind, .needsInput)
    }

    func testSubagentToolCallsAreSkipped() {
        XCTAssertNil(norm("claude", ["hook_event_name": "PreToolUse", "session_id": "s1", "agent_id": "a1",
                                     "tool_name": "Read", "tool_input": [:]]))
    }

    func testCodexShellArgvAndCommit() throws {
        let e = try XCTUnwrap(norm("codex", [
            "hook_event_name": "PreToolUse", "session_id": "c1", "tool_name": "shell",
            "tool_input": ["command": ["bash", "-lc", "git commit -m wip"]],
        ]))
        XCTAssertEqual(e.activity, .committing)
        XCTAssertEqual(e.detail, "git commit -m wip")
    }

    func testCodexApplyPatchNamesTheFile() throws {
        let e = try XCTUnwrap(norm("codex", [
            "hook_event_name": "PostToolUse", "session_id": "c1", "tool_name": "apply_patch",
            "tool_input": ["input": "*** Begin Patch\n*** Update File: src/main.rs\n@@"],
        ]))
        XCTAssertEqual(e.activity, .editing)
        XCTAssertEqual(e.detail, "main.rs")
    }

    func testCursorUsesConversationIdAndWorkspaceRoot() throws {
        let e = try XCTUnwrap(norm("cursor", [
            "hook_event_name": "afterFileEdit", "conversation_id": "k1",
            "workspace_roots": ["/Users/me/site"], "file_path": "/Users/me/site/index.ts",
        ]))
        XCTAssertEqual(e.sessionID, "k1")
        XCTAssertEqual(e.cwd, "/Users/me/site")
        XCTAssertEqual(e.kind, .toolEnd)
        XCTAssertEqual(e.activity, .editing)
        XCTAssertEqual(e.detail, "index.ts")
    }

    func testCursorStopStatuses() {
        XCTAssertEqual(norm("cursor", ["hook_event_name": "stop", "conversation_id": "k", "status": "completed"])?.kind, .done)
        XCTAssertEqual(norm("cursor", ["hook_event_name": "stop", "conversation_id": "k", "status": "error"])?.kind, .failed)
        XCTAssertEqual(norm("cursor", ["hook_event_name": "stop", "conversation_id": "k", "status": "aborted"])?.kind, .interrupted)
    }

    func testAntigravityTakesEventAndSessionFromTheScript() throws {
        let e = try XCTUnwrap(norm("antigravity", ["toolCall": ["name": "run_command", "args": ["CommandLine": "npm test"]]],
                                   event: "PostToolUse", session: "g1"))
        XCTAssertEqual(e.sessionID, "g1")
        XCTAssertEqual(e.activity, .testing)
    }

    // MARK: - Alerts

    func testDoneAlertStaysUntilYouRespond() {
        var store = AgentSessionStore()
        let now = Date()
        XCTAssertEqual(store.apply(AgentEvent(provider: "claude", sessionID: "s", kind: .prompt), now: now), .spawned)
        XCTAssertEqual(store.apply(AgentEvent(provider: "claude", sessionID: "s", kind: .done), now: now), .alerted(.done))
        // Time passing doesn't clear it, and pruning keeps an alerting session.
        XCTAssertTrue(store.prune(now: now.addingTimeInterval(24 * 3600), idleTimeout: 60).isEmpty)
        XCTAssertEqual(store.sessions["claude:s"]?.alert, .done)
        // Your next prompt does.
        XCTAssertEqual(store.apply(AgentEvent(provider: "claude", sessionID: "s", kind: .prompt), now: now), .answered)
        XCTAssertNil(store.sessions["claude:s"]?.alert)
    }

    func testAcknowledgeClearsOnlyThatSession() {
        var store = AgentSessionStore()
        store.apply(AgentEvent(provider: "codex", sessionID: "a", kind: .done))
        store.apply(AgentEvent(provider: "codex", sessionID: "b", kind: .needsInput))
        XCTAssertTrue(store.acknowledge("codex:a"))
        XCTAssertNil(store.sessions["codex:a"]?.alert)
        XCTAssertEqual(store.sessions["codex:b"]?.alert, .needsInput)
        XCTAssertFalse(store.acknowledge("codex:a"))
    }

    func testApprovingAPermissionClearsTheAlert() {
        var store = AgentSessionStore()
        store.apply(AgentEvent(provider: "claude", sessionID: "s", kind: .needsInput))
        XCTAssertEqual(store.apply(AgentEvent(provider: "claude", sessionID: "s", kind: .toolStart, activity: .running)), .answered)
    }

    func testIdleSessionsArePrunedAndEndedOnesRemoved() {
        var store = AgentSessionStore()
        let t0 = Date()
        store.apply(AgentEvent(provider: "cursor", sessionID: "x", kind: .sessionStart), now: t0)
        store.apply(AgentEvent(provider: "cursor", sessionID: "y", kind: .sessionStart), now: t0)
        XCTAssertEqual(store.prune(now: t0.addingTimeInterval(30), idleTimeout: 60), [])
        XCTAssertEqual(Set(store.prune(now: t0.addingTimeInterval(61), idleTimeout: 60)), ["cursor:x", "cursor:y"])
        store.apply(AgentEvent(provider: "cursor", sessionID: "z", kind: .sessionStart))
        XCTAssertEqual(store.apply(AgentEvent(provider: "cursor", sessionID: "z", kind: .sessionEnd)), .removed)
    }

    func testDisplayLingersOnAFinishedTool() {
        var store = AgentSessionStore()
        let t0 = Date()
        store.apply(AgentEvent(provider: "claude", sessionID: "s", kind: .toolEnd, activity: .reading, detail: "a.txt"), now: t0)
        let s = store.sessions["claude:s"]!
        XCTAssertEqual(s.display(now: t0.addingTimeInterval(1)).state, "reading")
        XCTAssertEqual(s.display(now: t0.addingTimeInterval(5)).state, "thinking")
    }

    func testTheMiniShowsWhatNeedsYouMost() {
        var store = AgentSessionStore()
        let t0 = Date()
        store.apply(AgentEvent(provider: "codex", sessionID: "busy", kind: .toolStart, activity: .editing), now: t0)
        store.apply(AgentEvent(provider: "claude", sessionID: "other", kind: .needsInput), now: t0)
        XCTAssertEqual(store.shown(for: "codex")?.sessionID, "busy")   // another provider's alert isn't its business
        store.apply(AgentEvent(provider: "codex", sessionID: "done", kind: .done), now: t0)
        store.apply(AgentEvent(provider: "codex", sessionID: "ask", kind: .needsInput), now: t0.addingTimeInterval(5))
        XCTAssertEqual(store.shown(for: "codex")?.sessionID, "ask")    // input beats a finish, even a newer one
        store.acknowledge("codex:ask")
        XCTAssertEqual(store.shown(for: "codex")?.sessionID, "done")
        store.acknowledge("codex:done")
        XCTAssertEqual(store.shown(for: "codex")?.sessionID, "busy")   // then whatever's working
        XCTAssertNil(store.shown(for: "cursor"))
    }

    func testConfigDecodesWithMissingKeys() throws {
        let c = try JSONDecoder().decode(MinisConfig.self, from: Data(#"{"speech":"detailed","provider":"nope"}"#.utf8))
        XCTAssertEqual(c.speech, .detailed)
        XCTAssertEqual(c.motion, .still)
        XCTAssertEqual(c.sound(.done), "Glass")
        XCTAssertEqual(c.provider, "claude")   // an unknown provider falls back to Claude
    }
}
