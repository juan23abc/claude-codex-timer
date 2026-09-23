import Foundation
import Darwin
import CPTY

public enum CodexCommand {
    public static func arguments(paths: AppPaths) -> [String] {
        ["exec", "--json", "--ephemeral", "--ignore-user-config", "--ignore-rules",
         "--skip-git-repo-check", "--sandbox", "read-only", "--color", "never",
         "-c", "approval_policy=\"never\"", "-c", "cli_auth_credentials_store=\"auto\"",
         "-c", "project_doc_max_bytes=0", "-c", "web_search=\"disabled\"",
         "-c", "features.shell_tool=false", "-c", "features.unified_exec=false",
         "-c", "features.hooks=false", "-c", "features.apps=false",
         "-c", "features.plugins=false", "-c", "features.multi_agent=false",
         "-c", "mcp_servers={}", "--cd", paths.codexWorkspace.path,
         "--", ClaudeCommand.prompt]
    }
    public static func setupScript(executable: String, paths: AppPaths) -> String {
        "#!/bin/bash\nset -e\ncd \(ClaudeCommand.shellQuote(paths.codexWorkspace.path))\nunset CODEX_API_KEY OPENAI_API_KEY OPENAI_BASE_URL\nexec \(ClaudeCommand.shellQuote(executable)) login\n"
    }
}

public enum CodexEventParser {
    public static func parse(_ data: Data, exitStatus: Int32?) -> SessionResult {
        var threadStarted = false, turnStarted = false, turnCompleted = false
        var reply: String?
        var failure: String?
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            guard let row = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], let type = row["type"] as? String else { continue }
            switch type {
            case "thread.started": threadStarted = !(row["thread_id"] as? String ?? "").isEmpty
            case "turn.started": turnStarted = threadStarted
            case "item.completed":
                if let item = row["item"] as? [String: Any], item["type"] as? String == "agent_message", turnStarted {
                    reply = item["text"] as? String
                }
            case "turn.completed": if turnStarted { turnCompleted = true }
            case "turn.failed", "error":
                let detail = (row["error"] as? [String: Any])?["message"] as? String ?? row["message"] as? String ?? "Codex returned an error."
                failure = String(detail.prefix(600))
            default: break
            }
        }
        // Never report a partial response as success: wait for the CLI exit too.
        guard let exitStatus else { return .waiting }
        if let failure { return .failure(failure) }
        guard exitStatus == 0 else { return .failure("Codex exited with code \(exitStatus). Check Codex setup, your usage limit, and CLI compatibility.") }
        guard threadStarted, turnStarted, turnCompleted, reply?.trimmingCharacters(in: .whitespacesAndNewlines) == "pong" else {
            return .failure("Codex did not complete a verified pong reply. Check your account and update Codex CLI if needed.")
        }
        return .success
    }
}

enum CodexRunner {
    static func perform(executable: String, paths: AppPaths, timeout: TimeInterval) throws -> (RunOutcome, String) {
        let argv = ([executable] + CodexCommand.arguments(paths: paths)).map { strdup($0) } + [nil]
        let envp = ClaudeCommand.environment(paths: paths, executable: executable).map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { for pointer in argv + envp { free(pointer) } }
        var fd: Int32 = -1
        let pid = argv.withUnsafeBufferPointer { args in
            envp.withUnsafeBufferPointer { env in ct_spawn_pipe(executable, args.baseAddress, env.baseAddress, paths.codexWorkspace.path, &fd) }
        }
        guard pid > 0 else { throw TimerError("Could not start Codex CLI.") }
        defer { close(fd); ct_stop_pty(pid) }
        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 16384)
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            if ct_cancel_requested() != 0 { return (.failed, "Ping cancelled.") }
            let count = read(fd, &buffer, buffer.count)
            if count > 0 {
                output.append(contentsOf: buffer.prefix(count))
                guard output.count <= 2 * 1024 * 1024 else { return (.failed, "Codex produced too much output for a simple ping.") }
                continue
            }
            var status: Int32 = 0
            if ct_child_exit_status(pid, &status) != 0 {
                // Drain any bytes written immediately before exit.
                while true {
                    let remaining = read(fd, &buffer, buffer.count)
                    if remaining <= 0 { break }
                    output.append(contentsOf: buffer.prefix(remaining))
                    guard output.count <= 2 * 1024 * 1024 else { return (.failed, "Codex produced too much output for a simple ping.") }
                }
                switch CodexEventParser.parse(output, exitStatus: status) {
                case .success: return (.success, "Codex replied: pong")
                case .failure(let detail): return (.failed, detail)
                case .waiting: return (.failed, "Codex exited before a verified reply.")
                }
            }
            usleep(100_000)
        }
        return (.timedOut, "No verified Codex reply within \(Int(timeout)) seconds. Check your connection and Codex sign-in, then try again.")
    }
}
