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
            do {
                let settings = try TimerSettings.load(paths: paths)
                guard let executable = provider.resolve(settings: settings, paths: paths) else {
                    throw TimerError("\(provider.cliTitle) was not found. Install it or choose its executable in Settings.")
                }
                switch provider {
                case .claude: result = try perform(executable: executable, paths: paths, sessionID: sessionID, timeout: timeout)
                case .codex: result = try CodexRunner.perform(executable: executable, paths: paths, timeout: timeout)
                }
            } catch { result = (.failed, error.localizedDescription) }
            let record = RunRecord(id: sessionID, startedAt: start, finishedAt: Date(), outcome: result.0, detail: result.1, source: source, provider: provider)
            try RunHistory.append(record, paths: paths)
            return record
    }

    static func perform(executable: String, paths: AppPaths, sessionID: String, timeout: TimeInterval) throws -> (RunOutcome, String) {
        let arguments = [executable] + ClaudeCommand.arguments(sessionID: sessionID)
        let environment = ClaudeCommand.environment(paths: paths, executable: executable).map { "\($0.key)=\($0.value)" }
        let argv = arguments.map { strdup($0) } + [nil]
        let envp = environment.map { strdup($0) } + [nil]
        defer { for p in argv + envp { free(p) } }
        var fd: Int32 = -1
        let pid = argv.withUnsafeBufferPointer { args in
            envp.withUnsafeBufferPointer { env in ct_spawn_pty(executable, args.baseAddress, env.baseAddress, paths.workspace.path, &fd) }
        }
        guard pid > 0 else { throw TimerError("Could not start Claude Code: \(String(cString: strerror(errno)))") }
        // Close the master first. Some CLIs drain terminal output during exit;
        // waiting before closing it can leave even a killed child stuck exiting.
        defer { close(fd); ct_stop_pty(pid) }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        let transcript = paths.transcript(sessionID: sessionID)
        var tail = Data()
        var queryTail = Data()
        var buffer = [UInt8](repeating: 0, count: 16384)
        while ProcessInfo.processInfo.systemUptime < deadline {
            if ct_cancel_requested() != 0 { return (.failed, "Ping cancelled.") }
            if let data = try? Data(contentsOf: transcript) {
                switch SessionParser.parse(data, sessionID: sessionID) {
                case .success: return (.success, "Claude replied: pong")
                case .failure(let detail): return (.failed, detail)
                case .waiting: break
                }
            }
            let count = read(fd, &buffer, buffer.count)
            if count > 0 {
                let chunk = Data(buffer.prefix(count))
                tail.append(chunk)
                if tail.count > 65536 { tail = tail.suffix(65536) }
                // Queries can straddle reads. Never send approval keystrokes.
                queryTail.append(chunk)
                let queries: [(Data, String)] = [
                    (Data("\u{1b}[6n".utf8), "\u{1b}[1;1R"),
                    (Data("\u{1b}[c".utf8), "\u{1b}[?1;0c"),
                    (Data("\u{1b}]10;?\u{7}".utf8), "\u{1b}]10;rgb:c0c0/c0c0/c0c0\u{7}"),
                    (Data("\u{1b}]11;?\u{7}".utf8), "\u{1b}]11;rgb:1e1e/1e1e/1e1e\u{7}")
                ]
                for (query, answer) in queries {
                    while let range = queryTail.range(of: query) {
                        _ = answer.withCString { write(fd, $0, answer.utf8.count) }
                        queryTail.removeSubrange(range)
                    }
                }
                queryTail = queryTail.suffix(24)
                let plain = String(decoding: tail, as: UTF8.self).replacingOccurrences(of: "\u{1b}\\[[0-?]*[ -/]*[@-~]", with: "", options: .regularExpression).lowercased()
                if plain.contains("yes, i trust") || plain.contains("is this a project you created") || plain.contains("choose the text style") || plain.contains("select login method") {
                    return (.needsSetup, "Claude needs one-time setup. Click Open Claude setup, finish sign-in and trust this timer’s folder, then try again.")
                }
                if plain.contains("unknown option") || plain.contains("unknown argument") {
                    return (.failed, "This Claude Code version is unsupported. Update Claude Code, then try again.")
                }
            } else if count == 0 || (count < 0 && errno != EAGAIN && errno != EINTR) {
                // A final transcript write may arrive with PTY closure.
                if let data = try? Data(contentsOf: transcript) {
                    switch SessionParser.parse(data, sessionID: sessionID) {
                    case .success: return (.success, "Claude replied: pong")
                    case .failure(let detail): return (.failed, detail)
                    case .waiting: break
                    }
                }
                return (.failed, "Claude exited before a verified reply. Open Claude setup to check sign-in, your selected model, and CLI compatibility.")
            }
            usleep(100_000)
        }
        return (.timedOut, "No verified reply within \(Int(timeout)) seconds. Check your connection and complete Claude setup, then try again.")
    }
}
