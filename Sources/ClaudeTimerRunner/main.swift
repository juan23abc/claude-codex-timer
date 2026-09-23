import Foundation
import ClaudeTimerCore

let paths = AppPaths()
do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    switch arguments.first {
    case "run":
        var selected: [TimerProvider]?
        var scheduled = false
        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--scheduled": scheduled = true
            case "--provider":
                index += 1
                guard index < arguments.count, let provider = TimerProvider(rawValue: arguments[index]) else { throw TimerError("Use --provider claude or --provider codex.") }
                selected = [provider]
            default: throw TimerError("Usage: claude-timer-runner run [--scheduled] [--provider claude|codex]")
            }
            index += 1
        }
        PingRunner.installCancellationHandlers()
        let records = try PingRunner.runSelected(paths: paths, source: scheduled ? "scheduled" : "manual", providers: selected)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        print(String(decoding: try encoder.encode(records), as: UTF8.self))
        exit(records.allSatisfy { $0.outcome == .success } ? 0 : 1)
    case "providers":
        let providers = arguments.dropFirst().compactMap(TimerProvider.init(rawValue:))
        guard providers.count == arguments.count - 1, !providers.isEmpty else { throw TimerError("Usage: claude-timer-runner providers claude|codex [codex|claude]") }
        var settings = try TimerSettings.load(paths: paths)
        settings.providers = providers
        try settings.save(paths: paths)
        print("Selected: \(providers.map(\.title).joined(separator: " + "))")
    case "enable":
        var settings = try TimerSettings.load(paths: paths)
        if arguments.count == 2 {
            let time = arguments[1].split(separator: ":")
            guard time.count == 2, let hour = Int(time[0]), let minute = Int(time[1]) else { throw TimerError("Use enable HH:MM (24-hour time).") }
            settings.hour = hour; settings.minute = minute
        } else if arguments.count != 1 { throw TimerError("Usage: claude-timer-runner enable [HH:MM]") }
        try Scheduler(paths: paths).enable(settings: settings, runner: URL(fileURLWithPath: CommandLine.arguments[0]))
        print(String(format: "Schedule enabled daily at %02d:%02d local time.", settings.hour, settings.minute))
    case "disable":
        try Scheduler(paths: paths).disable()
        print("Daily schedule disabled. Settings and history kept.")
    case "status":
        let settings = try TimerSettings.load(paths: paths)
        print("Schedule: \(Scheduler(paths: paths).isEnabled ? "enabled" : "disabled")")
        print("Claude Code: \(ClaudeCommand.resolve(settings.claudePath, paths: paths) ?? "not found")")
        print("Codex CLI: \(TimerProvider.codex.resolve(settings: settings, paths: paths) ?? "not found")")
        print("Providers: \(settings.providers.map(\.title).joined(separator: " + "))")
        print("Ping running: \(RunLock.isRunning(paths: paths))")
        let history = try RunHistory.load(paths: paths)
        for provider in settings.providers {
            if let latest = history.first(where: { $0.provider == provider }) { print("\(provider.title) last run: \(latest.outcome.rawValue) — \(latest.detail)") }
        }
    default:
        print("Claude/Codex Timer\nUsage: claude-timer-runner run [--scheduled] [--provider claude|codex] | providers claude|codex [codex|claude] | enable [HH:MM] | disable | status")
        exit(arguments.isEmpty ? 0 : 2)
    }
} catch {
    FileHandle.standardError.write(Data("Claude/Codex Timer: \(error.localizedDescription)\n".utf8))
    exit(1)
}
