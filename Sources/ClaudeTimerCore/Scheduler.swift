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
    public static let label = "io.claude-timer.daily"
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
    public var isEnabled: Bool { isLoaded(Self.label) }
    public var hasLegacySchedule: Bool { FileManager.default.fileExists(atPath: paths.legacyAgent.path) || isLoaded(Self.legacyLabel) }
    private func isLoaded(_ label: String) -> Bool {
        (try? control(["print", "\(domain)/\(label)"]).status) == 0
    }
    public func plist(settings: TimerSettings) throws -> Data {
        try settings.validate()
        let dictionary: [String: Any] = [
            "Label": Self.label,
            "ProgramArguments": [paths.runner.path, "run", "--scheduled"],
            "WorkingDirectory": paths.workspace.path,
            "EnvironmentVariables": ["HOME": paths.home.path, "PATH": "\(paths.home.path)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"],
            "StartCalendarInterval": ["Hour": settings.hour, "Minute": settings.minute],
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
        guard FileManager.default.isExecutableFile(atPath: source.path) else { throw TimerError("The bundled runner is missing. Rebuild or reinstall Claude/Codex Timer.") }
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
        let previous = try? Data(contentsOf: paths.agent)
        let previousConfig = try? Data(contentsOf: paths.config)
        let wasEnabled = isEnabled
        let legacyWasEnabled = isLoaded(Self.legacyLabel)
        try installRunner(from: runner)
        do {
            if wasEnabled { try bootout(Self.label) }
            try settings.save(paths: paths)
            try plist(settings: settings).write(to: paths.agent, options: [.atomic])
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.agent.path)
            let result = try control(["bootstrap", domain, paths.agent.path])
            guard result.status == 0, isEnabled else { throw TimerError("macOS could not enable the schedule. \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))") }
            // Migrate only after the replacement is registered. Preserve a backup.
            if hasLegacySchedule {
                if fm.fileExists(atPath: paths.legacyAgent.path) {
                    try Data(contentsOf: paths.legacyAgent).write(to: paths.root.appendingPathComponent("legacy-launch-agent.plist.backup"), options: [.atomic])
                }
                if isLoaded(Self.legacyLabel) { try bootout(Self.legacyLabel) }
                if fm.fileExists(atPath: paths.legacyAgent.path) { try fm.removeItem(at: paths.legacyAgent) }
            }
        } catch {
            if isEnabled { try? bootout(Self.label) }
            if let previous { try? previous.write(to: paths.agent, options: [.atomic]) }
            else { try? fm.removeItem(at: paths.agent) }
            if let previousConfig { try? previousConfig.write(to: paths.config, options: [.atomic]) }
            else { try? fm.removeItem(at: paths.config) }
            if wasEnabled { _ = try? control(["bootstrap", domain, paths.agent.path]) }
            if legacyWasEnabled && !isLoaded(Self.legacyLabel) { _ = try? control(["bootstrap", domain, paths.legacyAgent.path]) }
            throw error
        }
    }
    public func disable() throws {
        if isEnabled { try bootout(Self.label) }
        if FileManager.default.fileExists(atPath: paths.agent.path) { try FileManager.default.removeItem(at: paths.agent) }
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
