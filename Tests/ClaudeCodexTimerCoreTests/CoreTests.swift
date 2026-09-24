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
    func testMultipleTimesRoundTripAndInvalidTimesPreserveSavedSettings() throws {
        let settings = TimerSettings(times: [DailyTime(hour: 7), DailyTime(hour: 9), DailyTime(hour: 12), DailyTime(hour: 17), DailyTime(hour: 23, minute: 59)])
        try settings.save(paths: paths)
        XCTAssertEqual(try TimerSettings.load(paths: paths), settings)
        for times in [[], [DailyTime(hour: 7), DailyTime(hour: 7)],
                      [DailyTime(hour: 0), DailyTime(hour: 7), DailyTime(hour: 9), DailyTime(hour: 12), DailyTime(hour: 17), DailyTime(hour: 21)],
                      [DailyTime(hour: -1)], [DailyTime(hour: 24)],
                      [DailyTime(hour: 7, minute: -1)], [DailyTime(hour: 7, minute: 60)]] {
            XCTAssertThrowsError(try TimerSettings(times: times).save(paths: paths))
            XCTAssertEqual(try TimerSettings.load(paths: paths), settings)
        }
    }
    func testSingleTimeSettingsMigrateWithoutLosingProvidersOrPaths() throws {
        let legacy: [String: Any] = ["hour": 17, "minute": 45, "claudePath": "/custom/claude", "codexPath": "/custom/codex", "providers": ["codex"]]
        try JSONSerialization.data(withJSONObject: legacy).write(to: paths.config)
        let settings = try TimerSettings.load(paths: paths)
        XCTAssertEqual(settings, TimerSettings(times: [DailyTime(hour: 17, minute: 45)], claudePath: "/custom/claude", codexPath: "/custom/codex", providers: [.codex]))
        try settings.save(paths: paths)
        XCTAssertEqual(try TimerSettings.load(paths: paths), settings)
    }
    func testEachTimerKeepsItsOwnProvidersAndManualRunsUseTheirUnion() throws {
        var settings = TimerSettings(timers: [DailyTimer(time: DailyTime(hour: 7), providers: [.claude]), DailyTimer(time: DailyTime(hour: 17), providers: [.codex])])
        try settings.save(paths: paths)
        XCTAssertEqual(try TimerSettings.load(paths: paths), settings)
        XCTAssertEqual(settings.providers, [.claude, .codex])
        settings.timers[0].time = DailyTime(hour: 8)
        settings.timers[1].providers = [.claude, .codex]
        try settings.save(paths: paths)
        XCTAssertEqual(try TimerSettings.load(paths: paths).timers[0].providers, [.claude])
        XCTAssertEqual(try TimerSettings.load(paths: paths).timers[1].providers, [.claude, .codex])
        for providers: [TimerProvider] in [[], [.codex, .codex]] {
            settings.timers[1].providers = providers
            XCTAssertThrowsError(try settings.save(paths: paths))
        }
        settings.timers[1] = DailyTimer(time: settings.timers[0].time, providers: [.codex])
        XCTAssertThrowsError(try settings.validate(), "Different providers must not allow duplicate times")
    }
    func testMultipleLegacyTimesInheritTheirSharedProviders() throws {
        let data = try JSONSerialization.data(withJSONObject: ["times": [["hour": 7, "minute": 0], ["hour": 17, "minute": 0]], "providers": ["codex"], "claudePath": ""])
        try data.write(to: paths.config)
        let settings = try TimerSettings.load(paths: paths)
        XCTAssertEqual(settings.timers.map(\.providers), [[.codex], [.codex]])
    }
    func testInvalidNewTimesDoNotFallBackToLegacyTime() throws {
        for times: Any in [[], NSNull(), [["hour": 7, "minute": 0], ["hour": 7, "minute": 0]]] {
            let data = try JSONSerialization.data(withJSONObject: ["times": times, "hour": 7, "minute": 0, "claudePath": ""])
            try data.write(to: paths.config)
            XCTAssertThrowsError(try TimerSettings.load(paths: paths))
        }
    }
    func testLegacyTimeImportedWithoutEnablingAnything() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: ["StartCalendarInterval": ["Hour": 8, "Minute": 30]], format: .xml, options: 0)
        try data.write(to: paths.legacyAgent)
        XCTAssertEqual(try TimerSettings.load(paths: paths).times, [DailyTime(hour: 8, minute: 30)])
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
        XCTAssertEqual(plist["ProgramArguments"] as? [String], [paths.runner.path, "run", "--scheduled", "--provider", "claude", "--provider", "codex"])
        XCTAssertEqual(plist["StartCalendarInterval"] as? [String: Int], ["Hour": 9, "Minute": 17])
        XCTAssertNil(plist["RunAtLoad"])
        XCTAssertNil(plist["KeepAlive"])
    }
    func testNextRunChoosesEarliestOfAllTimesAndWrapsAtMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let settings = TimerSettings(times: [DailyTime(hour: 17), DailyTime(hour: 0), DailyTime(hour: 7)])
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 24))!
        for (after, expected) in [(6, 7), (7, 17), (12, 17), (17, 24), (23, 24), (24, 31)] {
            XCTAssertEqual(settings.nextRun(after: start.addingTimeInterval(Double(after) * 3600), calendar: calendar), start.addingTimeInterval(Double(expected) * 3600))
        }
    }
    func testMultipleTimesFollowDaylightSavingChanges() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let settings = TimerSettings(times: [DailyTime(hour: 17), DailyTime(hour: 7)])
        for (month, day, overnightHours) in [(3, 7, 13), (10, 31, 15)] {
            let evening = calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 17))!
            let morning = try XCTUnwrap(settings.nextRun(after: evening, calendar: calendar))
            XCTAssertEqual(calendar.component(.hour, from: morning), 7)
            XCTAssertEqual(morning.timeIntervalSince(evening), Double(overnightHours) * 3600)
            let next = try XCTUnwrap(settings.nextRun(after: morning, calendar: calendar))
            XCTAssertEqual(calendar.component(.hour, from: next), 17)
            XCTAssertEqual(next.timeIntervalSince(morning), 10 * 3600)
        }
    }
    func testScheduleRegistersFiveTimersWithTheirOwnProviders() throws {
        let timers = [DailyTimer(time: DailyTime(hour: 7), providers: [.claude]), DailyTimer(time: DailyTime(hour: 17), providers: [.codex]), DailyTimer(time: DailyTime(hour: 12)), DailyTimer(time: DailyTime(hour: 21), providers: [.claude]), DailyTimer(time: DailyTime(hour: 9), providers: [.codex])]
        let settings = TimerSettings(timers: timers)
        for (index, timer) in timers.enumerated() {
            let data = try Scheduler(paths: paths).plist(settings: settings, timerIndex: index)
            let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            XCTAssertEqual(plist["Label"] as? String, Scheduler.labels[index])
            XCTAssertEqual(plist["StartCalendarInterval"] as? [String: Int], ["Hour": timer.time.hour, "Minute": timer.time.minute])
            XCTAssertEqual(plist["ProgramArguments"] as? [String], [paths.runner.path, "run", "--scheduled"] + timer.providers.flatMap { ["--provider", $0.rawValue] })
            XCTAssertNil(plist["RunAtLoad"])
        }
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
    func testQueuedScheduledRunWaitsForExistingRunAndKeepsItsProviders() throws {
        try TimerSettings(claudePath: "/missing/claude", codexPath: "/missing/codex").save(paths: paths)
        let acquired = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let holderFinished = expectation(description: "Existing run releases lock")
        let paths = paths!
        DispatchQueue.global().async {
            do {
                let lock = try RunLock(paths: paths)
                acquired.signal()
                _ = release.wait(timeout: .now() + 5)
                withExtendedLifetime(lock) {}
            } catch { XCTFail(error.localizedDescription); acquired.signal() }
            holderFinished.fulfill()
        }
        XCTAssertEqual(acquired.wait(timeout: .now() + 2), .success)
        XCTAssertThrowsError(try RunLock(paths: paths, waitTimeout: 0.1))
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { release.signal() }
        let started = ProcessInfo.processInfo.systemUptime
        let records = try PingRunner.runSelected(paths: paths, source: "scheduled", timeout: 1, providers: [.codex], waitForTurn: true)
        XCTAssertGreaterThanOrEqual(ProcessInfo.processInfo.systemUptime - started, 0.15)
        XCTAssertEqual(records.map(\.provider), [.codex])
        XCTAssertEqual(records.map(\.source), ["scheduled"])
        wait(for: [holderFinished], timeout: 2)
        XCTAssertFalse(RunLock.isRunning(paths: paths))
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
        var original = try TimerSettings.load(paths: paths)
        original.times = [DailyTime(hour: 7), DailyTime(hour: 9), DailyTime(hour: 12), DailyTime(hour: 17), DailyTime(hour: 21)]
        try original.save(paths: paths)
        let launchd = FakeLaunchd(loaded: [])
        let scheduler = Scheduler(paths: paths, control: launchd.run)
        let runner = URL(fileURLWithPath: original.claudePath)
        try scheduler.enable(settings: original, runner: runner)
        let previous = try Scheduler.labels.map { try Data(contentsOf: paths.agent(label: $0)) }
        var replacement = original
        replacement.timers[0].time = DailyTime(hour: 8)
        launchd.failBootstrapNumber = launchd.bootstrapCount + 3
        XCTAssertThrowsError(try scheduler.enable(settings: replacement, runner: runner))
        XCTAssertTrue(scheduler.isEnabled)
        XCTAssertEqual(launchd.loaded, Set(Scheduler.labels))
        XCTAssertEqual(try Scheduler.labels.map { try Data(contentsOf: paths.agent(label: $0)) }, previous)
        XCTAssertEqual(try TimerSettings.load(paths: paths), original)
    }
    func testScheduleUpdateRemovesOldTimesAndRejectsDuplicatesBeforeChangingJob() throws {
        try installScript("exit 0\n")
        var settings = try TimerSettings.load(paths: paths)
        let launchd = FakeLaunchd(loaded: [])
        let scheduler = Scheduler(paths: paths, control: launchd.run)
        let runner = URL(fileURLWithPath: settings.claudePath)
        settings.times = [DailyTime(hour: 7), DailyTime(hour: 12), DailyTime(hour: 17)]
        try scheduler.enable(settings: settings, runner: runner)
        settings.times.remove(at: 1)
        try scheduler.enable(settings: settings, runner: runner)
        let data = try Data(contentsOf: paths.agent)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["StartCalendarInterval"] as? [String: Int], ["Hour": 7, "Minute": 0])
        let second = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: paths.agent(label: Scheduler.labels[1])), format: nil) as? [String: Any])
        XCTAssertEqual(second["StartCalendarInterval"] as? [String: Int], ["Hour": 17, "Minute": 0])
        XCTAssertEqual(launchd.loaded, Set(Scheduler.labels.prefix(2)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.agent(label: Scheduler.labels[2]).path))
        var invalid = settings
        invalid.times.append(settings.times[0])
        XCTAssertThrowsError(try scheduler.enable(settings: invalid, runner: runner))
        XCTAssertEqual(try Data(contentsOf: paths.agent), data)
        XCTAssertEqual(try TimerSettings.load(paths: paths), settings)
        XCTAssertTrue(scheduler.isEnabled)
        try scheduler.disable()
        XCTAssertTrue(launchd.loaded.isEmpty)
        XCTAssertFalse(Scheduler.labels.contains { FileManager.default.fileExists(atPath: paths.agent(label: $0).path) })
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
        XCTAssertEqual(plist["ProgramArguments"] as? [String], [oldRunner.path, "run", "--scheduled", "--provider", "claude"])
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
    var failBootstrapNumber: Int?
    var bootstrapCount = 0
    init(loaded: Set<String>) { self.loaded = loaded }
    func run(_ arguments: [String]) throws -> CommandResult {
        let url = URL(fileURLWithPath: arguments.last!)
        let target = arguments.first == "bootstrap" ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent
        switch arguments.first {
        case "print": return CommandResult(status: loaded.contains(target) ? 0 : 113, output: "")
        case "bootout": loaded.remove(target)
        case "bootstrap":
            bootstrapCount += 1
            if failNextBootstrap || bootstrapCount == failBootstrapNumber { failNextBootstrap = false; return CommandResult(status: 5, output: "Injected bootstrap failure") }
            loaded.insert(target)
        default: throw TimerError("Unexpected launchctl command")
        }
        return CommandResult(status: 0, output: "")
    }
}
