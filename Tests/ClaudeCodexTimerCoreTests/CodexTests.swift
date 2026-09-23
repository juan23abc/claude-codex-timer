import XCTest
@testable import ClaudeCodexTimerCore

final class CodexTests: XCTestCase {
    private var paths: AppPaths!
    private let events = """
    {"type":"thread.started","thread_id":"test-thread"}
    {"type":"turn.started"}
    {"type":"item.completed","item":{"id":"reply","type":"agent_message","text":"pong"}}
    {"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":1}}
    """
    override func setUpWithError() throws {
        paths = AppPaths(home: FileManager.default.temporaryDirectory.appendingPathComponent("Codex timer's tests \(UUID().uuidString)"))
        try paths.prepare()
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: paths.home) }

    func testCodexNeedsCompletedTurnExactPongAndZeroExit() {
        let data = Data(events.utf8)
        XCTAssertEqual(CodexEventParser.parse(data, exitStatus: 0), .success)
        XCTAssertEqual(CodexEventParser.parse(data, exitStatus: nil), .waiting)
        assertFailure(CodexEventParser.parse(data, exitStatus: 1))
        assertFailure(CodexEventParser.parse(Data(events.replacingOccurrences(of: "pong", with: "hello").utf8), exitStatus: 0))
        assertFailure(CodexEventParser.parse(Data(events.components(separatedBy: "\n").dropLast().joined(separator: "\n").utf8), exitStatus: 0))
    }
    func testCodexFailureAfterReplyDoesNotPass() {
        let data = Data((events + "\n{\"type\":\"turn.failed\",\"error\":{\"message\":\"Usage limit reached\"}}").utf8)
        XCTAssertEqual(CodexEventParser.parse(data, exitStatus: 0), .failure("Usage limit reached"))
    }
    func testCodexIgnoresDiagnosticsAndRejectsUnframedOutput() {
        XCTAssertEqual(CodexEventParser.parse(Data(("log warning\n" + events).utf8), exitStatus: 0), .success)
        assertFailure(CodexEventParser.parse(Data("pong\n{\"type\":\"item.completed\"".utf8), exitStatus: 0))
        assertFailure(CodexEventParser.parse(Data(events.replacingOccurrences(of: "thread.started", with: "unrelated").utf8), exitStatus: 0))
    }
    func testOldSettingsAndHistoryRemainClaudeOnly() throws {
        let settings = try JSONDecoder().decode(TimerSettings.self, from: Data("{\"hour\":7,\"minute\":0,\"claudePath\":\"/test/claude\"}".utf8))
        XCTAssertEqual(settings.providers, [.claude])
        XCTAssertEqual(settings.codexPath, "")
        let record = RunRecord(outcome: .failed, detail: "Existing result", source: "scheduled")
        var dictionary = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as! [String: Any]
        dictionary.removeValue(forKey: "provider")
        let legacyRecord = try JSONDecoder().decode(RunRecord.self, from: JSONSerialization.data(withJSONObject: dictionary))
        XCTAssertEqual(legacyRecord.provider, .claude)
        XCTAssertEqual(legacyRecord.detail, record.detail)
    }
    func testBothProviderSettingsRoundTripAndValidation() throws {
        let settings = TimerSettings(codexPath: "/custom/codex", providers: [.claude, .codex])
        try settings.save(paths: paths)
        XCTAssertEqual(try TimerSettings.load(paths: paths), settings)
        XCTAssertThrowsError(try TimerSettings(providers: []).validate())
        XCTAssertThrowsError(try TimerSettings(providers: [.codex, .codex]).validate())
    }
    func testCodexCommandUsesRestrictedAutomationAndSavedAuthentication() {
        let args = CodexCommand.arguments(paths: paths)
        XCTAssertEqual(args.first, "exec")
        for required in ["--json", "--ephemeral", "--ignore-user-config", "read-only", "approval_policy=\"never\"", "features.hooks=false", "features.shell_tool=false", "features.apps=false", "features.plugins=false", "features.multi_agent=false", "web_search=\"disabled\"", "project_doc_max_bytes=0"] {
            XCTAssertTrue(args.contains(required), required)
        }
        XCTAssertFalse(args.contains("--dangerously-bypass-approvals-and-sandbox"))
        let env = ClaudeCommand.environment(paths: paths, executable: "/fake/codex")
        XCTAssertNil(env["OPENAI_API_KEY"])
        XCTAssertNil(env["CODEX_API_KEY"])
    }
    func testCodexPipeIntegrationRecordsProviderAndCleansUp() throws {
        try installFake(output: events, exit: 0)
        let result = try PingRunner.run(paths: paths, timeout: 4, provider: .codex)
        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.provider, .codex)
        XCTAssertEqual(try RunHistory.load(paths: paths).first?.provider, .codex)
        XCTAssertFalse(RunLock.isRunning(paths: paths))
    }
    func testOneProviderFailureDoesNotSkipTheOther() throws {
        try installFake(output: events, exit: 0)
        var settings = try TimerSettings.load(paths: paths)
        settings.claudePath = "/missing/claude"
        settings.providers = [.claude, .codex]
        try settings.save(paths: paths)
        let results = try PingRunner.runSelected(paths: paths, timeout: 4)
        XCTAssertEqual(results.map(\.provider), [.claude, .codex])
        XCTAssertEqual(results.map(\.outcome), [.failed, .success])
        XCTAssertEqual(try RunHistory.load(paths: paths).count, 2)
    }
    func testOnlySelectedProviderRuns() throws {
        try installFake(output: events, exit: 0)
        let results = try PingRunner.runSelected(paths: paths, timeout: 4)
        XCTAssertEqual(results.map(\.provider), [.codex])
        XCTAssertEqual(results.first?.outcome, .success)
    }
    func testCodexNonzeroExitCannotPassEvenAfterPong() throws {
        try installFake(output: events, exit: 5)
        XCTAssertEqual(try PingRunner.run(paths: paths, timeout: 4, provider: .codex).outcome, .failed)
    }
    func testCodexTimeoutKillsProcessAndReleasesLock() throws {
        let pidFile = paths.root.appendingPathComponent("codex.pid")
        try installScript("echo $$ > \(ClaudeCommand.shellQuote(pidFile.path))\nsleep 30\n")
        XCTAssertEqual(try PingRunner.run(paths: paths, timeout: 2, provider: .codex).outcome, .timedOut)
        let pid = Int32(try String(contentsOf: pidFile).trimmingCharacters(in: .whitespacesAndNewlines))!
        XCTAssertEqual(kill(pid, 0), -1)
        XCTAssertFalse(RunLock.isRunning(paths: paths))
    }
    func testBatchUsesSameCrossProcessLock() throws {
        let lock = try RunLock(paths: paths)
        try withExtendedLifetime(lock) { XCTAssertThrowsError(try PingRunner.runSelected(paths: paths, providers: [.codex])) }
    }
    private func assertFailure(_ result: SessionResult, file: StaticString = #filePath, line: UInt = #line) {
        if case .failure = result {} else { XCTFail("Expected failure, got \(result)", file: file, line: line) }
    }
    private func installFake(output: String, exit: Int) throws {
        try installScript("printf '%s\\n' \(ClaudeCommand.shellQuote(output))\nexit \(exit)\n")
    }
    private func installScript(_ content: String) throws {
        let file = paths.root.appendingPathComponent("fake codex")
        try ("#!/bin/bash\n" + content).write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        try TimerSettings(codexPath: file.path, providers: [.codex]).save(paths: paths)
    }
}
