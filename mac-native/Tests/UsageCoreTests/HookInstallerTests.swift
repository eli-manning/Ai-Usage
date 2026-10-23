import XCTest
@testable import UsageCore

/// Connecting and disconnecting must leave everything else in each CLI's
/// config exactly as it was — other hooks, other settings, key order.
final class HookInstallerTests: XCTestCase {
    private var home: URL!
    private var realHome: URL!

    override func setUpWithError() throws {
        realHome = HookInstaller.home
        home = FileManager.default.temporaryDirectory.appendingPathComponent("hooks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        HookInstaller.home = home
    }

    override func tearDownWithError() throws {
        HookInstaller.home = realHome
        try? FileManager.default.removeItem(at: home)
    }

    private func write(_ path: String, _ text: String) throws {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func json(_ path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: home.appendingPathComponent(path))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testClaudeKeepsOtherHooksAndSettings() throws {
        let original = #"{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}"#
        try write(".claude/settings.json", original)
        XCTAssertFalse(HookInstaller.isInstalled("claude"))

        try HookInstaller.setInstalled("claude", true)
        XCTAssertTrue(HookInstaller.isInstalled("claude"))
        let on = try json(".claude/settings.json")
        XCTAssertEqual(on["model"] as? String, "opus")
        let stop = try XCTUnwrap((on["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])
        XCTAssertEqual(stop.count, 2)
        let mine = try XCTUnwrap((stop[1]["hooks"] as? [[String: Any]])?.first)
        XCTAssertEqual(mine["async"] as? Bool, true)
        XCTAssertTrue((mine["command"] as? String ?? "").hasSuffix("aiusage-minis.sh claude Stop"))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: home.appendingPathComponent(".claude/hooks/aiusage-minis.sh").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude/settings.json.aiusage-backup").path))

        // Connecting twice doesn't add a second copy.
        try HookInstaller.setInstalled("claude", true)
        XCTAssertEqual(((try json(".claude/settings.json"))["hooks"] as? [String: Any])?["Stop"].map { ($0 as! [Any]).count }, 2)

        try HookInstaller.setInstalled("claude", false)
        let off = try json(".claude/settings.json")
        XCTAssertEqual(off as NSDictionary, try JSONSerialization.jsonObject(with: Data(original.utf8)) as! NSDictionary)
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude/hooks/aiusage-minis.sh").path))
    }

    func testCursorIsFlatAndVersioned() throws {
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".cursor"), withIntermediateDirectories: true)
        XCTAssertTrue(HookInstaller.canInstall("cursor"))
        try HookInstaller.setInstalled("cursor", true)
        let on = try json(".cursor/hooks.json")
        XCTAssertEqual(on["version"] as? Int, 1)
        let stop = try XCTUnwrap((on["hooks"] as? [String: Any])?["stop"] as? [[String: Any]])
        XCTAssertTrue((stop[0]["command"] as? String ?? "").hasSuffix("aiusage-minis.sh cursor stop"))
        // Nothing that can gate an action.
        let events = Set((on["hooks"] as? [String: Any] ?? [:]).keys)
        XCTAssertTrue(events.isDisjoint(with: ["preToolUse", "beforeShellExecution", "beforeMCPExecution", "beforeReadFile", "subagentStart"]))
        try HookInstaller.setInstalled("cursor", false)
        XCTAssertFalse(HookInstaller.isInstalled("cursor"))
    }

    func testCodexAndAntigravityShapes() throws {
        try HookInstaller.setInstalled("codex", true)
        let codex = try json(".codex/hooks.json")
        let group = try XCTUnwrap(((codex["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])?.first)
        XCTAssertEqual((group["hooks"] as? [[String: Any]])?.first?["timeout"] as? Int, 3)

        try write(".gemini/antigravity-cli/hooks.json", #"{"mine":{"Stop":[]}}"#)
        try HookInstaller.setInstalled("antigravity", true)
        let agy = try json(".gemini/antigravity-cli/hooks.json")
        XCTAssertNotNil(agy["mine"])
        let ours = try XCTUnwrap(agy["aiusage-minis"] as? [String: Any])
        XCTAssertNil(ours["PreToolUse"], "PreToolUse decides whether a tool may run; leave it alone")
        XCTAssertEqual((ours["PostToolUse"] as? [[String: Any]])?.first?["matcher"] as? String, "*")
        try HookInstaller.setInstalled("antigravity", false)
        XCTAssertNil(try json(".gemini/antigravity-cli/hooks.json")["aiusage-minis"])
    }

    func testRefusesANonObjectConfig() throws {
        try write(".codex/hooks.json", "[1, 2]")
        XCTAssertThrowsError(try HookInstaller.setInstalled("codex", true))
        XCTAssertEqual(try String(contentsOf: home.appendingPathComponent(".codex/hooks.json"), encoding: .utf8), "[1, 2]")
    }
}
