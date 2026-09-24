import Foundation

public struct TimerError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum TimerProvider: String, Codable, CaseIterable, Identifiable {
    case claude, codex
    public var id: String { rawValue }
    public var title: String { self == .claude ? "Claude" : "Codex" }
    public var cliTitle: String { self == .claude ? "Claude Code" : "Codex CLI" }
    public var installURL: URL { URL(string: self == .claude ? "https://code.claude.com/docs/en/setup" : "https://developers.openai.com/codex/cli")! }
    public func resolve(settings: TimerSettings, paths: AppPaths) -> String? {
        ClaudeCommand.resolve(self == .claude ? settings.claudePath : settings.codexPath, paths: paths, name: rawValue)
    }
}

public struct AppPaths {
    public let home: URL
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }
    // Persistent names are compatibility identifiers, not product branding.
    // Keep existing settings, history, Claude folder trust, and launchd jobs working.
    // The newly named bundled helper is installed at the original runner path.
    public var root: URL { home.appendingPathComponent("Library/Application Support/ClaudeTimer") }
    public var workspace: URL { home.appendingPathComponent(".claude-timer") }
    public var codexWorkspace: URL { root.appendingPathComponent("codex-workspace") }
    public var config: URL { root.appendingPathComponent("settings.json") }
    public var history: URL { root.appendingPathComponent("history.json") }
    public var lock: URL { root.appendingPathComponent("run.lock") }
    public var runner: URL { root.appendingPathComponent("bin/claude-timer-runner") }
    public var agent: URL { agent(label: Scheduler.label) }
    public func agent(label: String) -> URL { home.appendingPathComponent("Library/LaunchAgents/\(label).plist") }
    public var legacyAgent: URL { home.appendingPathComponent("Library/LaunchAgents/com.juan.claude-morning-timer.plist") }
    public var log: URL { home.appendingPathComponent("Library/Logs/ClaudeTimer/runner.log") }

    public func prepare() throws {
        for folder in [root, workspace, codexWorkspace, runner.deletingLastPathComponent(), agent.deletingLastPathComponent(), log.deletingLastPathComponent()] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
    }

    public func transcript(sessionID: String) -> URL {
        let canonical = workspace.resolvingSymlinksInPath().path
        let slug = canonical.replacingOccurrences(of: "[^A-Za-z0-9]", with: "-", options: .regularExpression)
        return home.appendingPathComponent(".claude/projects/\(slug)/\(sessionID).jsonl")
    }
}

public struct DailyTime: Codable, Hashable, Comparable {
    public var hour: Int
    public var minute: Int
    public init(hour: Int, minute: Int = 0) { self.hour = hour; self.minute = minute }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }
}

public struct DailyTimer: Codable, Equatable {
    public var time: DailyTime
    public var providers: [TimerProvider]
    public init(time: DailyTime, providers: [TimerProvider] = [.claude, .codex]) {
        self.time = time; self.providers = providers
    }
}

public struct TimerSettings: Codable, Equatable {
    public static let maximumTimes = 5
    public var timers: [DailyTimer]
    public var claudePath: String
    public var codexPath: String
    public var times: [DailyTime] {
        get { timers.map(\.time) }
        set {
            let providers = providers
            timers = newValue.map { time in DailyTimer(time: time, providers: timers.first(where: { $0.time == time })?.providers ?? providers) }
        }
    }
    // Manual runs use the union; the CLI's providers command applies to every timer.
    public var providers: [TimerProvider] {
        get { TimerProvider.allCases.filter { provider in timers.contains { $0.providers.contains(provider) } } }
        set { for index in timers.indices { timers[index].providers = newValue } }
    }
    public init(times: [DailyTime] = [DailyTime(hour: 7)], claudePath: String = "", codexPath: String = "", providers: [TimerProvider] = [.claude, .codex]) {
        self.init(timers: times.map { DailyTimer(time: $0, providers: providers) }, claudePath: claudePath, codexPath: codexPath)
    }
    public init(timers: [DailyTimer], claudePath: String = "", codexPath: String = "") {
        self.timers = timers; self.claudePath = claudePath; self.codexPath = codexPath
    }
    public init(hour: Int, minute: Int = 0, claudePath: String = "", codexPath: String = "", providers: [TimerProvider] = [.claude, .codex]) {
        self.init(times: [DailyTime(hour: hour, minute: minute)], claudePath: claudePath, codexPath: codexPath, providers: providers)
    }
    private enum CodingKeys: String, CodingKey { case timers, times, hour, minute, claudePath, codexPath, providers }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if values.contains(.timers) {
            timers = try values.decode([DailyTimer].self, forKey: .timers)
        } else {
            // Older installs keep their original provider selection for every time.
            let providers = try values.decodeIfPresent([TimerProvider].self, forKey: .providers) ?? [.claude]
            let times: [DailyTime]
            if values.contains(.times) { times = try values.decode([DailyTime].self, forKey: .times) }
            else { times = [DailyTime(hour: try values.decode(Int.self, forKey: .hour), minute: try values.decode(Int.self, forKey: .minute))] }
            timers = times.map { DailyTimer(time: $0, providers: providers) }
        }
        claudePath = try values.decode(String.self, forKey: .claudePath)
        codexPath = try values.decodeIfPresent(String.self, forKey: .codexPath) ?? ""
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(timers, forKey: .timers)
        try values.encode(claudePath, forKey: .claudePath)
        try values.encode(codexPath, forKey: .codexPath)
    }
    public func validate() throws {
        guard (1...Self.maximumTimes).contains(times.count) else { throw TimerError("Choose between 1 and \(Self.maximumTimes) daily times.") }
        guard times.allSatisfy({ (0...23).contains($0.hour) && (0...59).contains($0.minute) }) else { throw TimerError("Choose a valid daily time.") }
        guard Set(times).count == times.count else { throw TimerError("Choose a different time for each daily ping.") }
        guard timers.allSatisfy({ !$0.providers.isEmpty && Set($0.providers).count == $0.providers.count }) else { throw TimerError("Select at least one provider for each timer, without duplicates.") }
    }
    public static func load(paths: AppPaths) throws -> Self {
        guard FileManager.default.fileExists(atPath: paths.config.path) else {
            if let data = try? Data(contentsOf: paths.legacyAgent),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               let time = plist["StartCalendarInterval"] as? [String: Int] {
                let settings = Self(hour: time["Hour"] ?? 7, minute: time["Minute"] ?? 0, providers: [.claude])
                try settings.validate()
                return settings
            }
            return Self()
        }
        let settings = try JSONDecoder().decode(Self.self, from: Data(contentsOf: paths.config))
        try settings.validate()
        return settings
    }
    public func save(paths: AppPaths) throws {
        try validate(); try paths.prepare()
        try JSONEncoder().encode(self).write(to: paths.config, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.config.path)
    }
    public func nextRun(after date: Date = Date(), calendar: Calendar = .current) -> Date? {
        times.compactMap {
            calendar.nextDate(after: date, matching: DateComponents(hour: $0.hour, minute: $0.minute), matchingPolicy: .nextTime)
        }.min()
    }
}

public enum RunOutcome: String, Codable { case success, failed, needsSetup, timedOut }
public struct RunRecord: Codable, Identifiable {
    public var id: String
    public var startedAt: Date
    public var finishedAt: Date
    public var outcome: RunOutcome
    public var detail: String
    public var source: String
    public var provider: TimerProvider
    public init(id: String = UUID().uuidString.lowercased(), startedAt: Date = Date(), finishedAt: Date = Date(), outcome: RunOutcome, detail: String, source: String, provider: TimerProvider = .claude) {
        self.id = id; self.startedAt = startedAt; self.finishedAt = finishedAt
        self.outcome = outcome; self.detail = detail; self.source = source; self.provider = provider
    }
    private enum CodingKeys: String, CodingKey { case id, startedAt, finishedAt, outcome, detail, source, provider }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        startedAt = try values.decode(Date.self, forKey: .startedAt)
        finishedAt = try values.decode(Date.self, forKey: .finishedAt)
        outcome = try values.decode(RunOutcome.self, forKey: .outcome)
        detail = try values.decode(String.self, forKey: .detail)
        source = try values.decode(String.self, forKey: .source)
        provider = try values.decodeIfPresent(TimerProvider.self, forKey: .provider) ?? .claude
    }
}

public enum RunHistory {
    public static func load(paths: AppPaths) throws -> [RunRecord] {
        guard FileManager.default.fileExists(atPath: paths.history.path) else { return [] }
        return try JSONDecoder().decode([RunRecord].self, from: Data(contentsOf: paths.history))
    }
    // Caller holds the process-wide run lock.
    public static func append(_ record: RunRecord, paths: AppPaths) throws {
        var history = try load(paths: paths)
        history.insert(record, at: 0)
        try JSONEncoder().encode(Array(history.prefix(100))).write(to: paths.history, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.history.path)
    }
}

public enum ClaudeCommand {
    public static let prompt = "Reply with exactly: pong"
    public static func resolve(_ configured: String = "", paths: AppPaths = AppPaths(), name: String = "claude") -> String? {
        let fm = FileManager.default
        if !configured.isEmpty { return fm.isExecutableFile(atPath: configured) ? configured : nil }
        let candidates = [paths.home.appendingPathComponent(".local/bin/\(name)").path, "/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)"]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/\(name)" }
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }
    public static func arguments(sessionID: String? = nil, sendPrompt: Bool = true) -> [String] {
        var args = ["--safe-mode", "--tools", "", "--disallowedTools", "mcp__*", "--strict-mcp-config", "--mcp-config", "{\"mcpServers\":{}}", "--settings", "{\"disableAllHooks\":true}"]
        if let sessionID { args += ["--session-id", sessionID] }
        if sendPrompt { args += ["--", prompt] }
        return args
    }
    public static func environment(paths: AppPaths, executable: String) -> [String: String] {
        // Do not inherit API keys, nested-agent flags, or shell startup scripts.
        ["HOME": paths.home.path,
         "USER": NSUserName(), "LOGNAME": NSUserName(),
         "PATH": "\(URL(fileURLWithPath: executable).deletingLastPathComponent().path):\(paths.home.path)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
         "TERM": "xterm-256color", "LANG": "en_US.UTF-8", "COLUMNS": "100", "LINES": "32",
         "TMPDIR": NSTemporaryDirectory()]
    }
    public static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    public static func setupScript(executable: String, paths: AppPaths) -> String {
        "#!/bin/bash\nset -e\ncd \(shellQuote(paths.workspace.path))\nunset CLAUDECODE ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN CLAUDE_CONFIG_DIR\nexec \(shellQuote(executable)) \(arguments(sendPrompt: false).map(shellQuote).joined(separator: " "))\n"
    }
}
