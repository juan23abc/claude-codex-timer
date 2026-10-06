import Foundation
import Darwin
import CPTY

public final class RunLock {
    private var descriptor: Int32
    public init(paths: AppPaths, waitTimeout: TimeInterval = 0) throws {
        try paths.prepare()
        descriptor = open(paths.lock.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw TimerError("Could not open the run lock.") }
        let deadline = ProcessInfo.processInfo.systemUptime + waitTimeout
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            let lockError = errno
            guard (lockError == EWOULDBLOCK || lockError == EINTR), ct_cancel_requested() == 0,
                  ProcessInfo.processInfo.systemUptime < deadline else {
                close(descriptor); descriptor = -1
                throw TimerError(ct_cancel_requested() != 0 ? "Ping cancelled." : "A ping is already running. Wait for it to finish.")
            }
            usleep(50_000)
        }
    }
    deinit { if descriptor >= 0 { flock(descriptor, LOCK_UN); close(descriptor) } }
    public static func isRunning(paths: AppPaths) -> Bool {
        guard FileManager.default.fileExists(atPath: paths.lock.path) else { return false }
        do { let lock = try RunLock(paths: paths); withExtendedLifetime(lock) {}; return false }
        catch { return true }
    }
}

public enum PingRunner {
    public static func installCancellationHandlers() { ct_install_signal_handlers() }
    public static func run(paths: AppPaths = AppPaths(), source: String = "manual", timeout: TimeInterval = 90, provider: TimerProvider = .claude) throws -> RunRecord {
        let lock = try RunLock(paths: paths)
        return try withExtendedLifetime(lock) { try runUnlocked(paths: paths, source: source, timeout: timeout, provider: provider) }
    }

    public static func runSelected(paths: AppPaths = AppPaths(), source: String = "manual", timeout: TimeInterval = 90, providers: [TimerProvider]? = nil, waitForTurn: Bool = false) throws -> [RunRecord] {
        // Independent timers can launch together after wake; serialize them without dropping a timer.
        let lock = try RunLock(paths: paths, waitTimeout: waitForTurn ? Double(TimerSettings.maximumTimes * TimerProvider.allCases.count) * (timeout + 5) : 0)
        return try withExtendedLifetime(lock) {
            let selected = try providers ?? TimerSettings.load(paths: paths).providers
            guard !selected.isEmpty, Set(selected).count == selected.count else { throw TimerError("Choose at least one provider, without duplicates.") }
            var records: [RunRecord] = []
            for provider in selected {
                if ct_cancel_requested() != 0 { throw TimerError("Ping cancelled.") }
                records.append(try runUnlocked(paths: paths, source: source, timeout: timeout, provider: provider))
            }
            return records
        }
    }

    private static func runUnlocked(paths: AppPaths, source: String, timeout: TimeInterval, provider: TimerProvider) throws -> RunRecord {
        let start = Date()
        let sessionID = UUID().uuidString.lowercased()
        let result: (RunOutcome, String)
        var verification: ClaudeWindowVerification?
        // Keep this bounded background run awake through the reply and usage checks.
        let activity = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "Complete scheduled ping and verify usage window")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        do {
            let settings = try TimerSettings.load(paths: paths)
            guard let executable = provider.resolve(settings: settings, paths: paths) else {
                throw TimerError("\(provider.cliTitle) was not found. Install it or choose its executable in Settings.")
            }
            switch provider {
            case .claude:
                let deadline = ProcessInfo.processInfo.systemUptime + timeout
                let before = ClaudeUsageProbe.read(executable: executable, paths: paths, deadline: min(deadline, ProcessInfo.processInfo.systemUptime + min(12, timeout / 4)))
                let ping = try perform(executable: executable, paths: paths, sessionID: sessionID, timeout: max(0, deadline - ProcessInfo.processInfo.systemUptime - min(18, timeout / 4)))
                if ping.0 == .success {
                    let after = ClaudeUsageProbe.read(executable: executable, paths: paths, deadline: deadline)
                    let window = ClaudeWindowVerification(before: before, after: after)
                    verification = window
                    result = ct_cancel_requested() != 0 ? (.unverified, "Claude replied: pong. Usage verification was cancelled.") : (window.confirmed ? .success : .unverified, window.detail)
                } else { result = ping }
            case .codex:
                result = try CodexRunner.perform(executable: executable, paths: paths, timeout: timeout)
            }
        } catch { result = (.failed, error.localizedDescription) }
        let record = RunRecord(id: sessionID, startedAt: start, finishedAt: Date(), outcome: result.0, detail: result.1, source: source, provider: provider, claudeWindow: verification)
        try RunHistory.append(record, paths: paths)
        return record
    }

    static func perform(executable: String, paths: AppPaths, sessionID: String, timeout: TimeInterval) throws -> (RunOutcome, String) {
        guard ct_cancel_requested() == 0 else { return (.failed, "Ping cancelled.") }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        let terminal = try ClaudePTY(executable: executable, paths: paths, arguments: ClaudeCommand.arguments(sessionID: sessionID))
        let transcript = paths.transcript(sessionID: sessionID)
        var replyFinishedAt: TimeInterval?
        while ProcessInfo.processInfo.systemUptime < deadline {
            if ct_cancel_requested() != 0 { return (.failed, "Ping cancelled.") }
            terminal.readOutput()
            if let problem = terminal.problem { return problem }
            if let data = try? Data(contentsOf: transcript) {
                switch SessionParser.parse(data, sessionID: sessionID) {
                case .success:
                    if replyFinishedAt == nil { replyFinishedAt = ProcessInfo.processInfo.systemUptime }
                    // Allow the CLI to finish its turn before submitting /exit.
                    if terminal.ended || ProcessInfo.processInfo.systemUptime - replyFinishedAt! >= 0.5 {
                        terminal.exitGracefully(deadline: deadline)
                        return (.success, "Claude replied: pong")
                    }
                case .failure(let detail): return (.failed, detail)
                case .waiting: break
                }
            }
            if terminal.ended { return (.failed, "Claude exited before a completed reply. Open Claude setup to check sign-in and CLI compatibility.") }
            usleep(50_000)
        }
        if replyFinishedAt != nil { return (.success, "Claude replied: pong") }
        return (.timedOut, "No completed reply before the timeout. Check your connection and complete Claude setup, then try again.")
    }
}
