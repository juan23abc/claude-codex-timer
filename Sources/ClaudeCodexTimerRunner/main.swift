import Foundation
import ClaudeCodexTimerCore

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
                if selected == nil { selected = [] }
                selected?.append(provider)
            default: throw TimerError("Usage: claude-codex-timer-runner run [--scheduled] [--provider claude|codex]")
            }
            index += 1
        }
        PingRunner.installCancellationHandlers()
        let records = try PingRunner.runSelected(paths: paths, source: scheduled ? "scheduled" : "manual", providers: selected, waitForTurn: scheduled)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        print(String(decoding: try encoder.encode(records), as: UTF8.self))
        exit(records.allSatisfy { $0.outcome == .success } ? 0 : 1)
    case "providers":
        let providers = arguments.dropFirst().compactMap(TimerProvider.init(rawValue:))
        guard providers.count == arguments.count - 1, !providers.isEmpty else { throw TimerError("Usage: claude-codex-timer-runner providers claude|codex [codex|claude]") }
        var settings = try TimerSettings.load(paths: paths)
        settings.providers = providers
        let scheduler = Scheduler(paths: paths)
        if scheduler.isEnabled { try scheduler.enable(settings: settings, runner: URL(fileURLWithPath: CommandLine.arguments[0])) }
        else { try settings.save(paths: paths) }
        print("Selected: \(providers.map(\.title).joined(separator: " + "))")
    case "enable":
        var settings = try TimerSettings.load(paths: paths)
        guard arguments.count <= TimerSettings.maximumTimes + 1 else { throw TimerError("Use enable with up to \(TimerSettings.maximumTimes) HH:MM times (24-hour time).") }
        if arguments.count > 1 {
            settings.times = try arguments.dropFirst().map { argument in
                let time = argument.split(separator: ":", omittingEmptySubsequences: false)
                guard time.count == 2, let hour = Int(time[0]), let minute = Int(time[1]) else { throw TimerError("Use enable with up to \(TimerSettings.maximumTimes) HH:MM times (24-hour time).") }
                return DailyTime(hour: hour, minute: minute)
            }
        }
        try Scheduler(paths: paths).enable(settings: settings, runner: URL(fileURLWithPath: CommandLine.arguments[0]))
        print("Schedule enabled daily at \(settings.times.sorted().map { String(format: "%02d:%02d", $0.hour, $0.minute) }.joined(separator: ", ")) local time.")
    case "disable":
        try Scheduler(paths: paths).disable()
        print("Daily schedule disabled. Settings and history kept.")
    case "status":
        let settings = try TimerSettings.load(paths: paths)
        print("Schedule: \(Scheduler(paths: paths).isEnabled ? "enabled" : "disabled")")
        print("Daily times: \(settings.times.sorted().map { String(format: "%02d:%02d", $0.hour, $0.minute) }.joined(separator: ", "))")
        for timer in settings.timers.sorted(by: { $0.time < $1.time }) {
            print("  \(String(format: "%02d:%02d", timer.time.hour, timer.time.minute)): \(timer.providers.map(\.title).joined(separator: " + "))")
        }
        print("Claude Code: \(ClaudeCommand.resolve(settings.claudePath, paths: paths) ?? "not found")")
        print("Codex CLI: \(TimerProvider.codex.resolve(settings: settings, paths: paths) ?? "not found")")
        print("Providers: \(settings.providers.map(\.title).joined(separator: " + "))")
        print("Ping running: \(RunLock.isRunning(paths: paths))")
        let history = try RunHistory.load(paths: paths)
        for provider in settings.providers {
            if let latest = history.first(where: { $0.provider == provider }) { print("\(provider.title) last run: \(latest.outcome.rawValue) — \(latest.detail)") }
        }
    default:
        print("Claude Codex Timer\nUsage: claude-codex-timer-runner run [--scheduled] [--provider claude|codex] | providers claude|codex [codex|claude] | enable [HH:MM ...] (up to \(TimerSettings.maximumTimes) times) | disable | status")
        exit(arguments.isEmpty ? 0 : 2)
    }
} catch {
    FileHandle.standardError.write(Data("Claude Codex Timer: \(error.localizedDescription)\n".utf8))
    exit(1)
}
