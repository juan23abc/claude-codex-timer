import Foundation
import Darwin
import CPTY

final class ClaudePTY {
    private let pid: pid_t
    private let fd: Int32
    private var queryTail = Data()
    private(set) var screen = TerminalScreen()
    private(set) var ended = false

    init(executable: String, paths: AppPaths, arguments: [String]) throws {
        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        let envp = ClaudeCommand.environment(paths: paths, executable: executable).map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { for p in argv + envp { free(p) } }
        var master: Int32 = -1
        pid = argv.withUnsafeBufferPointer { args in
            envp.withUnsafeBufferPointer { env in ct_spawn_pty(executable, args.baseAddress, env.baseAddress, paths.workspace.path, &master) }
        }
        guard pid > 0 else { throw TimerError("Could not start Claude Code: \(String(cString: strerror(errno)))") }
        fd = master
    }
    deinit { close(fd); ct_stop_pty(pid) }

    func send(_ text: String) {
        let data = Array(text.utf8)
        data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count > 0 { offset += count }
                else if errno != EINTR { break }
            }
        }
    }
    func readOutput() {
        var buffer = [UInt8](repeating: 0, count: 16384)
        for _ in 0..<16 {
            let count = read(fd, &buffer, buffer.count)
            if count > 0 {
                let chunk = Data(buffer.prefix(count))
                screen.feed(chunk)
                queryTail.append(chunk)
                let queries = [
                    ("\u{1b}[6n", "\u{1b}[1;1R"), ("\u{1b}[c", "\u{1b}[?1;0c"),
                    ("\u{1b}]10;?\u{7}", "\u{1b}]10;rgb:c0c0/c0c0/c0c0\u{7}"),
                    ("\u{1b}]11;?\u{7}", "\u{1b}]11;rgb:1e1e/1e1e/1e1e\u{7}")
                ]
                for (query, answer) in queries {
                    while let range = queryTail.range(of: Data(query.utf8)) { send(answer); queryTail.removeSubrange(range) }
                }
                queryTail = queryTail.suffix(24)
            } else {
                if count == 0 || (errno != EAGAIN && errno != EINTR) { ended = true }
                break
            }
        }
    }
    var problem: (RunOutcome, String)? {
        let plain = screen.text.lowercased()
        if ["yes, i trust", "is this a project you created", "choose the text style", "select login method"].contains(where: plain.contains) {
            return (.needsSetup, "Claude needs one-time setup. Click Open Claude setup, finish sign-in and trust this timer’s folder, then try again.")
        }
        if plain.contains("unknown option") || plain.contains("unknown argument") {
            return (.failed, "This Claude Code version is unsupported. Update Claude Code, then try again.")
        }
        return nil
    }
    func exitGracefully(fromUsage: Bool = false, deadline: TimeInterval) {
        guard !ended, ct_cancel_requested() == 0 else { return }
        if fromUsage {
            send("\u{1b}")
            // Let the usage panel dismiss before typing a built-in command.
            drain(until: min(deadline, ProcessInfo.processInfo.systemUptime + 0.2))
        }
        send("/exit\r")
        drain(until: min(deadline, ProcessInfo.processInfo.systemUptime + 2))
    }
    private func drain(until deadline: TimeInterval) {
        while !ended && ct_cancel_requested() == 0 && ProcessInfo.processInfo.systemUptime < deadline {
            readOutput()
            var status: Int32 = 0
            if ct_child_exit_status(pid, &status) != 0 { ended = true; break }
            usleep(50_000)
        }
    }
}

enum ClaudeUsageProbe {
    static func read(executable: String, paths: AppPaths, deadline: TimeInterval) -> ClaudeUsageSnapshot {
        guard ProcessInfo.processInfo.systemUptime < deadline, ct_cancel_requested() == 0 else {
            return ClaudeUsageSnapshot(state: .unavailable, detail: "Usage check did not complete")
        }
        do {
            let args = ClaudeCommand.arguments(sendPrompt: false) + ["--", "/usage"]
            let terminal = try ClaudePTY(executable: executable, paths: paths, arguments: args)
            defer { terminal.exitGracefully(fromUsage: true, deadline: deadline) }
            let start = ProcessInfo.processInfo.systemUptime
            var candidate: ClaudeUsageSnapshot?
            var stableSince = start
            while ProcessInfo.processInfo.systemUptime < deadline, ct_cancel_requested() == 0 {
                terminal.readOutput()
                if let problem = terminal.problem { return ClaudeUsageSnapshot(state: .unavailable, detail: problem.1) }
                let parsed = ClaudeUsageParser.parse(terminal.screen.text)
                if parsed?.state != candidate?.state || parsed?.resetsAt != candidate?.resetsAt || parsed?.usedPercent != candidate?.usedPercent {
                    candidate = parsed; stableSince = ProcessInfo.processInfo.systemUptime
                }
                // /usage may first paint cached data, then replace it after its request finishes.
                if let candidate, ProcessInfo.processInfo.systemUptime - start >= 4,
                   ProcessInfo.processInfo.systemUptime - stableSince >= 2 {
                    return ClaudeUsageSnapshot(checkedAt: Date(), state: candidate.state, resetsAt: candidate.resetsAt, usedPercent: candidate.usedPercent)
                }
                if terminal.ended { break }
                usleep(50_000)
            }
            return ClaudeUsageSnapshot(state: .unavailable, detail: "Could not read a stable reset time from Claude /usage")
        } catch { return ClaudeUsageSnapshot(state: .unavailable, detail: "Could not open Claude /usage") }
    }
}
