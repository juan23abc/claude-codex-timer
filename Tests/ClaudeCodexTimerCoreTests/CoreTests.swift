import XCTest
@testable import ClaudeCodexTimerCore

final class CoreTests: XCTestCase {
    private var paths: AppPaths!
    override func setUpWithError() throws {
        paths = AppPaths(home: FileManager.default.temporaryDirectory.appendingPathComponent("Claude Codex Timer's tests \(UUID().uuidString)"))
        try paths.prepare()
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: paths.home) }
    private func row(session: String = "ours", entrypoint: String = "cli", text: String = "pong", error: Bool = false) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["sessionId": session, "entrypoint": entrypoint, "type": "assistant", "isApiErrorMessage": error, "message": ["content": [["type": "text", "text": text]]]])
    }
    func testAPIErrorCannotBeSuccessfulEvenIfTextIsPong() throws {
        XCTAssertEqual(SessionParser.parse(try row(text: "pong", error: true), sessionID: "ours"), .failure("pong"))
        XCTAssertEqual(SessionParser.parse(try row(text: "Login expired", error: true), sessionID: "ours"), .failure("Login expired"))
    }
    func testOnlyExpectedReplyInExactInteractiveSessionSucceeds() throws {
        XCTAssertEqual(SessionParser.parse(try row(), sessionID: "ours"), .success)
        XCTAssertEqual(SessionParser.parse(try row(session: "other"), sessionID: "ours"), .waiting)
        if case .failure = SessionParser.parse(try row(entrypoint: "sdk-cli"), sessionID: "ours") {} else { XCTFail("SDK replies must not pass") }
        if case .failure = SessionParser.parse(try row(text: "Out of credits"), sessionID: "ours") {} else { XCTFail("Unexpected replies must not pass") }
    }
    func testParserHandlesPartialMalformedAndNonAssistantLines() throws {
        let prefix = Data("not json\n{\"type\":\"user\",\"sessionId\":\"ours\"}\n{\"broken\n".utf8)
        XCTAssertEqual(SessionParser.parse(prefix, sessionID: "ours"), .waiting)
        XCTAssertEqual(SessionParser.parse(prefix + (try row()), sessionID: "ours"), .success)
    }
    func testSettingsRoundTripAndInvalidDataDoesNotResetSilently() throws {
        let settings = TimerSettings(hour: 16, minute: 45, claudePath: "/some path/claude")
        try settings.save(paths: paths)
        XCTAssertEqual(try TimerSettings.load(paths: paths), settings)
        XCTAssertThrowsError(try TimerSettings(hour: 24).save(paths: paths))
        try Data("broken".utf8).write(to: paths.config)
        XCTAssertThrowsError(try TimerSettings.load(paths: paths))
    }
    func testLegacyTimeImportedWithoutEnablingAnything() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: ["StartCalendarInterval": ["Hour": 8, "Minute": 30]], format: .xml, options: 0)
        try data.write(to: paths.legacyAgent)
        XCTAssertEqual(try TimerSettings.load(paths: paths).hour, 8)
        XCTAssertEqual(try TimerSettings.load(paths: paths).minute, 30)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.agent.path))
    }
    func testNextRunTodayTomorrowAndDST() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let before = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 6))!
        let settings = TimerSettings()
        XCTAssertEqual(calendar.component(.day, from: settings.nextRun(after: before, calendar: calendar)!), 7)
        let atTime = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 7))!
        let next = settings.nextRun(after: atTime, calendar: calendar)!
        XCTAssertEqual(calendar.component(.day, from: next), 8)
        XCTAssertEqual(calendar.component(.hour, from: next), 7)
        XCTAssertEqual(next.timeIntervalSince(atTime), 23 * 3600)
    }
    func testScheduleUsesCurrentHomeAndDoesNotPingOnLoad() throws {
        let data = try Scheduler(paths: paths).plist(settings: TimerSettings(hour: 9, minute: 17))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["ProgramArguments"] as? [String], [paths.runner.path, "run", "--scheduled"])
        XCTAssertEqual(plist["StartCalendarInterval"] as? [String: Int], ["Hour": 9, "Minute": 17])
        XCTAssertNil(plist["RunAtLoad"])
        XCTAssertNil(plist["KeepAlive"])
    }
    func testProcessLockBlocksOverlappingRunsAndReleases() throws {
        var lock: RunLock? = try RunLock(paths: paths)
        XCTAssertTrue(RunLock.isRunning(paths: paths))
        XCTAssertThrowsError(try RunLock(paths: paths))
        withExtendedLifetime(lock) {}
        lock = nil
        XCTAssertFalse(RunLock.isRunning(paths: paths))
        XCTAssertNoThrow(try RunLock(paths: paths))
    }
    func testHistoryIsBoundedAndPreservesOutcome() throws {
        for i in 0..<105 {
            try RunHistory.append(RunRecord(id: "\(i)", outcome: .failed, detail: "Login expired", source: "manual"), paths: paths)
        }
        let history = try RunHistory.load(paths: paths)
        XCTAssertEqual(history.count, 100)
        XCTAssertEqual(history.first?.id, "104")
        XCTAssertEqual(history.last?.id, "5")
        XCTAssertEqual(history.first?.outcome, .failed)
    }
    func testArgumentsDisableToolsAndPreserveInteractiveMode() {
        let args = ClaudeCommand.arguments(sessionID: "ours")
        XCTAssertTrue(args.contains("--safe-mode"))
        XCTAssertTrue(args.contains("--strict-mcp-config"))
        XCTAssertFalse(args.contains("--dangerously-skip-permissions"))
        XCTAssertFalse(args.contains("--print"))
        XCTAssertEqual(args[args.firstIndex(of: "--tools")! + 1], "")
        let env = ClaudeCommand.environment(paths: paths, executable: "/test/claude")
        XCTAssertNil(env["ANTHROPIC_API_KEY"])
        XCTAssertNil(env["CLAUDECODE"])
    }
    func testShellQuoteRoundTrip() throws {
        let value = "a ' quote $HOME `echo nope` and spaces"
        let output = try LocalProcess.run("/bin/bash", ["-c", "printf %s \(ClaudeCommand.shellQuote(value))"])
        XCTAssertEqual(output.output, value)
    }
    func testPTYSuccessAndErrorAreRecorded() throws {
        try installFake(reply: "pong", apiError: false)
        let successful = try PingRunner.run(paths: paths, timeout: 3)
        XCTAssertEqual(successful.outcome, .success)
        try installFake(reply: "Login expired", apiError: true)
        let failed = try PingRunner.run(paths: paths, timeout: 3)
        XCTAssertEqual(failed.outcome, .failed)
        XCTAssertEqual(failed.detail, "Login expired")
        XCTAssertEqual(try RunHistory.load(paths: paths).count, 2)
        XCTAssertFalse(RunLock.isRunning(paths: paths))
    }
    func testTimeoutStopsChildAndReleasesLock() throws {
        let pidFile = paths.root.appendingPathComponent("child.pid")
        try installScript("echo $$ > \(ClaudeCommand.shellQuote(pidFile.path))\nsleep 30\n")
        XCTAssertEqual(try PingRunner.run(paths: paths, timeout: 2).outcome, .timedOut)
        let pid = Int32(try String(contentsOf: pidFile).trimmingCharacters(in: .whitespacesAndNewlines))!
        XCTAssertEqual(kill(pid, 0), -1)
        XCTAssertFalse(RunLock.isRunning(paths: paths))
    }
    func testTrustPromptNeedsSetupWithoutAutomaticApproval() throws {
        try installScript("printf 'Yes, I trust this folder\\n'\nsleep 30\n")
        XCTAssertEqual(try PingRunner.run(paths: paths, timeout: 3).outcome, .needsSetup)
    }
    func testMissingExecutableProducesUsefulFailure() throws {
        try TimerSettings(claudePath: "/nonexistent/claude").save(paths: paths)
        let result = try PingRunner.run(paths: paths, timeout: 1)
        XCTAssertEqual(result.outcome, .failed)
        XCTAssertTrue(result.detail.contains("not found"))
    }
    func testEarlyExitIsNotSuccess() throws {
        try installScript("exit 1\n")
        XCTAssertEqual(try PingRunner.run(paths: paths, timeout: 3).outcome, .failed)
    }
    func testScheduleMigrationKeepsTimeAndBacksUpLegacy() throws {
        try installScript("exit 0\n")
        let executable = try TimerSettings.load(paths: paths).claudePath
        let settings = TimerSettings(hour: 8, minute: 30, claudePath: executable, providers: [.claude])
        let legacy = Data("legacy plist fixture".utf8)
        try legacy.write(to: paths.legacyAgent)
        let launchd = FakeLaunchd(loaded: [Scheduler.legacyLabel])
        let scheduler = Scheduler(paths: paths, control: launchd.run)
        try scheduler.enable(settings: settings, runner: URL(fileURLWithPath: executable))
        XCTAssertTrue(scheduler.isEnabled)
        XCTAssertFalse(scheduler.hasLegacySchedule)
        XCTAssertEqual(try TimerSettings.load(paths: paths), settings)
        XCTAssertEqual(try Data(contentsOf: paths.root.appendingPathComponent("legacy-launch-agent.plist.backup")), legacy)
        try scheduler.disable()
        XCTAssertFalse(scheduler.isEnabled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.agent.path))
    }
    func testFailedReplacementRestoresWorkingScheduleAndSettings() throws {
        try installScript("exit 0\n")
        let original = try TimerSettings.load(paths: paths)
        let launchd = FakeLaunchd(loaded: [Scheduler.label])
        let scheduler = Scheduler(paths: paths, control: launchd.run)
        let plist = try scheduler.plist(settings: original)
        try plist.write(to: paths.agent)
        launchd.failNextBootstrap = true
        XCTAssertThrowsError(try scheduler.enable(settings: TimerSettings(hour: 9, claudePath: original.claudePath, providers: [.claude]), runner: URL(fileURLWithPath: original.claudePath)))
        XCTAssertTrue(scheduler.isEnabled)
        XCTAssertEqual(try Data(contentsOf: paths.agent), plist)
        XCTAssertEqual(try TimerSettings.load(paths: paths), original)
    }
    func testRenamedBundledRunnerPreservesExistingInstallation() throws {
        let oldRoot = paths.home.appendingPathComponent("Library/Application Support/ClaudeTimer")
        let oldRunner = oldRoot.appendingPathComponent("bin/claude-timer-runner")
        let oldAgent = paths.home.appendingPathComponent("Library/LaunchAgents/io.claude-timer.daily.plist")
        let settings = TimerSettings(hour: 8, minute: 30, claudePath: "/bin/echo", providers: [.claude])
        try JSONEncoder().encode(settings).write(to: oldRoot.appendingPathComponent("settings.json"))
        let record = RunRecord(outcome: .success, detail: "Existing pong", source: "scheduled")
        let history = try JSONEncoder().encode([record])
        try history.write(to: oldRoot.appendingPathComponent("history.json"))
        try Data("old helper".utf8).write(to: oldRunner)

        let bundledRunner = paths.home.appendingPathComponent("Claude Codex Timer.app/Contents/Helpers/claude-codex-timer-runner")
        try FileManager.default.createDirectory(at: bundledRunner.deletingLastPathComponent(), withIntermediateDirectories: true)
        let script = Data("#!/bin/sh\nprintf 'Claude Codex Timer'\n".utf8)
        try script.write(to: bundledRunner)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: bundledRunner.path)
        let launchd = FakeLaunchd(loaded: ["io.claude-timer.daily"])
        let scheduler = Scheduler(paths: paths, control: launchd.run)
        try scheduler.plist(settings: settings).write(to: oldAgent)

        XCTAssertEqual(try TimerSettings.load(paths: paths), settings)
        try scheduler.enable(settings: settings, runner: bundledRunner)

        XCTAssertEqual(launchd.loaded, ["io.claude-timer.daily"])
        XCTAssertEqual(try Data(contentsOf: oldRunner), script)
        XCTAssertEqual(try LocalProcess.run(oldRunner.path, []).output, "Claude Codex Timer")
        XCTAssertEqual(try TimerSettings.load(paths: paths), settings)
        XCTAssertEqual(try Data(contentsOf: paths.history), history)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: oldAgent), format: nil) as? [String: Any])
        XCTAssertEqual(plist["ProgramArguments"] as? [String], [oldRunner.path, "run", "--scheduled"])
    }
    func testFailedMigrationLeavesOriginalJobLoaded() throws {
        try installScript("exit 0\n")
        let settings = try TimerSettings.load(paths: paths)
        try Data("legacy".utf8).write(to: paths.legacyAgent)
        let launchd = FakeLaunchd(loaded: [Scheduler.legacyLabel])
        launchd.failNextBootstrap = true
        let scheduler = Scheduler(paths: paths, control: launchd.run)
        XCTAssertThrowsError(try scheduler.enable(settings: settings, runner: URL(fileURLWithPath: settings.claudePath)))
        XCTAssertTrue(launchd.loaded.contains(Scheduler.legacyLabel))
        XCTAssertFalse(scheduler.isEnabled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.legacyAgent.path))
    }
    private func installFake(reply: String, apiError: Bool) throws {
        let directory = paths.transcript(sessionID: "ignored").deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let template = "{\"sessionId\":\"%s\",\"entrypoint\":\"cli\",\"type\":\"assistant\",\"isApiErrorMessage\":\(apiError),\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"\(reply)\"}]}}\\n"
        try installScript("""
        while [ "$#" -gt 0 ]; do
          if [ "$1" = "--session-id" ]; then shift; session="$1"; fi
          shift
        done
        printf \(ClaudeCommand.shellQuote(template)) "$session" > \(ClaudeCommand.shellQuote(directory.path))/"$session.jsonl"
        sleep 30
        """)
    }
    private func installScript(_ content: String) throws {
        let file = paths.root.appendingPathComponent("fake claude")
        try ("#!/bin/bash\n" + content).write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        try TimerSettings(claudePath: file.path, providers: [.claude]).save(paths: paths)
    }
}

private final class FakeLaunchd {
    var loaded: Set<String>
    var failNextBootstrap = false
    init(loaded: Set<String>) { self.loaded = loaded }
    func run(_ arguments: [String]) throws -> CommandResult {
        let target = arguments.last!.contains(Scheduler.legacyLabel) ? Scheduler.legacyLabel : Scheduler.label
        switch arguments.first {
        case "print": return CommandResult(status: loaded.contains(target) ? 0 : 113, output: "")
        case "bootout": loaded.remove(target)
        case "bootstrap":
            if failNextBootstrap { failNextBootstrap = false; return CommandResult(status: 5, output: "Injected bootstrap failure") }
            loaded.insert(target)
        default: throw TimerError("Unexpected launchctl command")
        }
        return CommandResult(status: 0, output: "")
    }
}
