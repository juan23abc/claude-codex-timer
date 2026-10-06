import XCTest
@testable import ClaudeCodexTimerCore

final class ClaudeUsageTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-09-26T03:51:00Z")!
    private var screen: String {
        "Current session\n0% used\nResets 3:30pm (Asia/Makassar)\nCurrent week (all models)\n97% used\nResets Sep 27 at 10pm (Asia/Makassar)"
    }
    func testParsesActualSessionResetInItsReportedTimezone() throws {
        let usage = try XCTUnwrap(ClaudeUsageParser.parse(screen, now: now))
        XCTAssertEqual(usage.resetsAt, ISO8601DateFormatter().date(from: "2026-09-26T07:30:00Z"))
        XCTAssertEqual(usage.usedPercent, 0, "Rounded zero usage can still have an active window")
    }
    func testNoSessionResetCannotBeReplacedWithWeeklyReset() {
        XCTAssertNil(ClaudeUsageParser.parse("Current session\n0% used\nCurrent week (all models)\n97% used\nResets 3:30pm (Asia/Makassar)", now: now))
        XCTAssertNil(ClaudeUsageParser.parse("Resets 3:30pm (Asia/Makassar)", now: now))
        XCTAssertNil(ClaudeUsageParser.parse(screen.replacingOccurrences(of: "Asia/Makassar", with: "Unknown/Zone"), now: now))
        XCTAssertNil(ClaudeUsageParser.parse(screen.replacingOccurrences(of: "3:30pm", with: "11am"), now: now))
    }
    func testNoActiveWindowIsDifferentFromUnknownFormat() {
        XCTAssertEqual(ClaudeUsageParser.parse("Current session\nNo active session\nCurrent week", now: now)?.state, .inactive)
        XCTAssertNil(ClaudeUsageParser.parse("Current session\nLoading usage…", now: now))
    }
    func testMidnightAndNoonAnd24HourTime() throws {
        let midnight = ISO8601DateFormatter().date(from: "2026-09-26T14:00:00Z")!
        let usage = try XCTUnwrap(ClaudeUsageParser.parse("Current session\n0% used\nResets 12am (Asia/Makassar)", now: midnight))
        XCTAssertEqual(usage.resetsAt, ISO8601DateFormatter().date(from: "2026-09-26T16:00:00Z"))
        XCTAssertEqual(ClaudeUsageParser.parse(screen.replacingOccurrences(of: "3:30pm", with: "15:30"), now: now)?.resetsAt, ClaudeUsageParser.parse(screen, now: now)?.resetsAt)
        XCTAssertEqual(ClaudeUsageParser.parse(screen.replacingOccurrences(of: "3:30pm", with: "12pm"), now: now)?.resetsAt, now.addingTimeInterval(9 * 60))
    }
    func testTerminalAppliesFragmentedCursorUpdatesAndErasesOldReset() throws {
        var terminal = TerminalScreen()
        let data = Data("\u{1b}[2J\u{1b}[HCurrent session\r\n0% used\r\nResets 3:29pm (Asia/Makassar)\r\nCurrent week (all models)\r\n97% used\r\nResets Sep 27 at 10pm (Asia/Makassar)".utf8)
        for byte in data { terminal.feed(Data([byte])) }
        terminal.feed(Data("\u{1b}[3;10H30".utf8))
        XCTAssertEqual(ClaudeUsageParser.parse(terminal.text, now: now)?.resetsAt, now.addingTimeInterval(219 * 60))
        terminal.feed(Data("\u{1b}[3;1H\u{1b}[2KLoading usage…".utf8))
        XCTAssertNil(ClaudeUsageParser.parse(terminal.text, now: now))
    }
    func testTerminalIgnoresTitlesAndHandlesSplitUnicodeAndAlternateScreen() {
        var terminal = TerminalScreen()
        for byte in Data("\u{1b}]0;Current session\u{7}✓ OK".utf8) { terminal.feed(Data([byte])) }
        XCTAssertTrue(terminal.text.contains("✓ OK"))
        XCTAssertFalse(terminal.text.contains("Current session"))
        terminal.feed(Data("\u{1b}[?1049hNew screen".utf8))
        XCTAssertFalse(terminal.text.contains("✓ OK"))
    }
    func testVerificationSeparatesExistingStartedAndUnknownWindows() {
        let before = ClaudeUsageSnapshot(checkedAt: now, state: .inactive)
        let after = ClaudeUsageSnapshot(checkedAt: now.addingTimeInterval(10), state: .active, resetsAt: now.addingTimeInterval(5 * 3600), usedPercent: 0)
        XCTAssertEqual(ClaudeWindowVerification(before: before, after: after).status, .started)
        XCTAssertEqual(ClaudeWindowVerification(before: after, after: after).status, .alreadyActive)
        XCTAssertEqual(ClaudeWindowVerification(before: .init(state: .unavailable), after: after).status, .active)
        XCTAssertEqual(ClaudeWindowVerification(before: before, after: before).status, .notStarted)
        XCTAssertFalse(ClaudeWindowVerification(before: after, after: .init(state: .unavailable)).confirmed)
        let expired = ClaudeUsageSnapshot(checkedAt: now, state: .active, resetsAt: now.addingTimeInterval(-60))
        XCTAssertFalse(ClaudeWindowVerification(before: expired, after: expired).confirmed)
    }
    func testHistoricalPongsAreNotRelabeledAsVerifiedWindows() throws {
        let record = RunRecord(outcome: .success, detail: "Claude replied: pong", source: "scheduled")
        let decoded = try JSONDecoder().decode(RunRecord.self, from: JSONEncoder().encode(record))
        XCTAssertFalse(decoded.verifiedSuccess)
        XCTAssertEqual(decoded.title, "Ping delivered · window unchecked")
        XCTAssertEqual(decoded.outcome, .success, "Preserve the historical delivery outcome")
    }
    func testPartialPongWaitsForCompletedTurn() throws {
        var message: [String: Any] = ["content": [["type": "text", "text": "pong"]]]
        func data() throws -> Data {
            try JSONSerialization.data(withJSONObject: ["type": "assistant", "sessionId": "ours", "entrypoint": "cli", "message": message])
        }
        XCTAssertEqual(SessionParser.parse(try data(), sessionID: "ours"), .waiting)
        message["stop_reason"] = "end_turn"
        XCTAssertEqual(SessionParser.parse(try data(), sessionID: "ours"), .success)
    }
    func testRealPTYChecksBeforeAndAfterAndRequestsCleanExit() throws {
        let paths = AppPaths(home: FileManager.default.temporaryDirectory.appendingPathComponent("Usage checks ' \(UUID().uuidString)"))
        try paths.prepare()
        defer { try? FileManager.default.removeItem(at: paths.home) }
        let directory = paths.transcript(sessionID: "ignored").deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = paths.root.appendingPathComponent("fake claude")
        let marker = paths.root.appendingPathComponent("ping-sent")
        let exitLog = paths.root.appendingPathComponent("exits")
        let formatter = DateFormatter(); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "HH:mm"
        let reset = formatter.string(from: Date().addingTimeInterval(5 * 3600))
        let script = """
        #!/bin/bash
        stty -echo
        usage=0
        while [ "$#" -gt 0 ]; do
          if [ "$1" = '--session-id' ]; then shift; session="$1"; fi
          if [ "$1" = '/usage' ]; then usage=1; fi
          shift
        done
        if [ "$usage" = 1 ]; then
          printf '\\033[2J\\033[HCurrent session\\r\\n'
          if [ -e \(ClaudeCommand.shellQuote(marker.path)) ]; then
            printf '0%% used\\r\\nResets \(reset) (UTC)\\r\\nCurrent week (all models)\\r\\n97%% used\\r\\n'
          else
            printf 'No active session\\r\\nCurrent week (all models)\\r\\n'
          fi
        else
          touch \(ClaudeCommand.shellQuote(marker.path))
          printf '{"sessionId":"%s","entrypoint":"cli","type":"assistant","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"pong"}]}}\\n' "$session" > \(ClaudeCommand.shellQuote(directory.path))/"$session.jsonl"
        fi
        while IFS= read -r line; do
          case "$line" in *'/exit'*) echo clean >> \(ClaudeCommand.shellQuote(exitLog.path)); exit 0;; esac
        done
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        try TimerSettings(claudePath: executable.path, providers: [.claude]).save(paths: paths)
        let record = try PingRunner.run(paths: paths, timeout: 25)
        XCTAssertEqual(record.outcome, .success, record.detail)
        XCTAssertEqual(record.claudeWindow?.status, .started)
        XCTAssertEqual(try String(contentsOf: exitLog).split(separator: "\n").count, 3)
        let saved = try XCTUnwrap(RunHistory.load(paths: paths).first)
        XCTAssertEqual(saved.claudeWindow, record.claudeWindow)
        XCTAssertFalse(RunLock.isRunning(paths: paths))
    }
}
