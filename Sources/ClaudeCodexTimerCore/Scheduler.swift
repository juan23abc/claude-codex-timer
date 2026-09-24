import Foundation
import Darwin

public struct CommandResult { public let status: Int32; public let output: String }
public enum LocalProcess {
    public static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 15) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        // File output cannot deadlock when a pipe's buffer fills.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close(); try? FileManager.default.removeItem(at: url) }
        process.standardOutput = file; process.standardError = file
        try process.run()
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline { usleep(50_000) }
        if process.isRunning {
            process.terminate()
            let cleanupDeadline = ProcessInfo.processInfo.systemUptime + 4
            while process.isRunning && ProcessInfo.processInfo.systemUptime < cleanupDeadline { usleep(50_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw TimerError("The command timed out: \(URL(fileURLWithPath: executable).lastPathComponent)")
        }
        process.waitUntilExit()
        return CommandResult(status: process.terminationStatus, output: String(decoding: (try? Data(contentsOf: url)) ?? Data(), as: UTF8.self))
    }
}

public struct Scheduler {
    // The first timer retains the original job identity for in-place upgrades.
    public static let label = "io.claude-timer.daily"
    public static let labels = [label] + (2...TimerSettings.maximumTimes).map { "\(label).\($0)" }
    public static let legacyLabel = "com.juan.claude-morning-timer"
    public let paths: AppPaths
    private let control: ([String]) throws -> CommandResult
    public init(paths: AppPaths = AppPaths()) {
        self.paths = paths
        self.control = { try LocalProcess.run("/bin/launchctl", $0) }
    }
    init(paths: AppPaths, control: @escaping ([String]) throws -> CommandResult) {
        self.paths = paths; self.control = control
    }
    private var domain: String { "gui/\(getuid())" }
    public var isEnabled: Bool { Self.labels.contains(where: isLoaded) }
    public var hasLegacySchedule: Bool { FileManager.default.fileExists(atPath: paths.legacyAgent.path) || isLoaded(Self.legacyLabel) }
    private func isLoaded(_ label: String) -> Bool {
        (try? control(["print", "\(domain)/\(label)"]).status) == 0
    }
    public func plist(settings: TimerSettings, timerIndex: Int = 0) throws -> Data {
        try settings.validate()
        guard settings.timers.indices.contains(timerIndex) else { throw TimerError("Choose an existing timer.") }
        let timer = settings.timers[timerIndex]
        let dictionary: [String: Any] = [
            "Label": Self.labels[timerIndex],
            "ProgramArguments": [paths.runner.path, "run", "--scheduled"] + timer.providers.flatMap { ["--provider", $0.rawValue] },
            "WorkingDirectory": paths.workspace.path,
            "EnvironmentVariables": ["HOME": paths.home.path, "PATH": "\(paths.home.path)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"],
            "StartCalendarInterval": ["Hour": timer.time.hour, "Minute": timer.time.minute],
            "StandardOutPath": paths.log.path,
            "StandardErrorPath": paths.log.path,
            "ProcessType": "Background",
            "ExitTimeOut": 5
        ]
        return try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
    }
    public func installRunner(from source: URL) throws {
        try paths.prepare()
        guard source.standardizedFileURL != paths.runner.standardizedFileURL else { return }
        guard FileManager.default.isExecutableFile(atPath: source.path) else { throw TimerError("The bundled runner is missing. Rebuild or reinstall Claude Codex Timer.") }
        // Atomic replacement permits updating a binary while a previous run finishes.
        try Data(contentsOf: source).write(to: paths.runner, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: paths.runner.path)
    }
    public func enable(settings: TimerSettings, runner: URL) throws {
        try settings.validate()
        for provider in settings.providers {
            guard provider.resolve(settings: settings, paths: paths) != nil else { throw TimerError("Choose or install \(provider.cliTitle), or deselect it before enabling the schedule.") }
        }
        let fm = FileManager.default
        let previous = Dictionary(uniqueKeysWithValues: Self.labels.compactMap { label in
            (try? Data(contentsOf: paths.agent(label: label))).map { (label, $0) }
        })
        let previousConfig = try? Data(contentsOf: paths.config)
        let loadedLabels = Self.labels.filter(isLoaded)
        let legacyWasEnabled = isLoaded(Self.legacyLabel)
        try installRunner(from: runner)
        do {
            for label in loadedLabels { try bootout(label) }
            try settings.save(paths: paths)
            for (index, label) in Self.labels.enumerated() {
                let agent = paths.agent(label: label)
                if settings.timers.indices.contains(index) {
                    try plist(settings: settings, timerIndex: index).write(to: agent, options: [.atomic])
                    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: agent.path)
                    let result = try control(["bootstrap", domain, agent.path])
                    guard result.status == 0, isLoaded(label) else { throw TimerError("macOS could not enable timer \(index + 1). \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))") }
                } else if fm.fileExists(atPath: agent.path) {
                    try fm.removeItem(at: agent)
                }
            }
            // Migrate only after the replacement is registered. Preserve a backup.
            if hasLegacySchedule {
                if fm.fileExists(atPath: paths.legacyAgent.path) {
                    try Data(contentsOf: paths.legacyAgent).write(to: paths.root.appendingPathComponent("legacy-launch-agent.plist.backup"), options: [.atomic])
                }
                if isLoaded(Self.legacyLabel) { try bootout(Self.legacyLabel) }
                if fm.fileExists(atPath: paths.legacyAgent.path) { try fm.removeItem(at: paths.legacyAgent) }
            }
        } catch {
            for label in Self.labels {
                if isLoaded(label) { try? bootout(label) }
                if let data = previous[label] { try? data.write(to: paths.agent(label: label), options: [.atomic]) }
                else { try? fm.removeItem(at: paths.agent(label: label)) }
            }
            if let previousConfig { try? previousConfig.write(to: paths.config, options: [.atomic]) }
            else { try? fm.removeItem(at: paths.config) }
            for label in loadedLabels { _ = try? control(["bootstrap", domain, paths.agent(label: label).path]) }
            if legacyWasEnabled && !isLoaded(Self.legacyLabel) { _ = try? control(["bootstrap", domain, paths.legacyAgent.path]) }
            throw error
        }
    }
    public func disable() throws {
        for label in Self.labels {
            if isLoaded(label) { try bootout(label) }
            if FileManager.default.fileExists(atPath: paths.agent(label: label).path) { try FileManager.default.removeItem(at: paths.agent(label: label)) }
        }
        if hasLegacySchedule {
            if isLoaded(Self.legacyLabel) { try bootout(Self.legacyLabel) }
            if FileManager.default.fileExists(atPath: paths.legacyAgent.path) { try FileManager.default.removeItem(at: paths.legacyAgent) }
        }
    }
    private func bootout(_ label: String) throws {
        let result = try control(["bootout", "\(domain)/\(label)"])
        guard result.status == 0 else { throw TimerError("macOS could not stop the schedule: \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))") }
    }
}
