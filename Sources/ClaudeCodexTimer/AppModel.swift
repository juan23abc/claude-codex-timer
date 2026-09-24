import AppKit
import SwiftUI
import ClaudeCodexTimerCore

@MainActor
final class AppModel: ObservableObject {
    // Debug-only fixtures for screenshots; no account data or live actions are used.
    private var isScreenshotPreview: Bool {
        #if DEBUG
        CommandLine.arguments.contains("--screenshots")
        #else
        false
        #endif
    }
    let paths = AppPaths()
    @Published var settings = TimerSettings()
    @Published private var savedSettings = TimerSettings()
    @Published var enabled = false
    @Published var legacy = false
    @Published var running = false
    @Published var busy = false
    @Published var history: [RunRecord] = []
    @Published var error: String?
    @Published var notice: String?
    @Published var selection: Page = .overview
    enum Page: String, CaseIterable, Identifiable {
        case overview = "Overview", activity = "Activity", settings = "Settings"
        var id: String { rawValue }
        var symbol: String { switch self { case .overview: return "timer"; case .activity: return "clock.arrow.circlepath"; case .settings: return "slider.horizontal.3" } }
    }
    var runner: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/claude-codex-timer-runner") }
    var claudePath: String? { ClaudeCommand.resolve(settings.claudePath, paths: paths) }
    var savedProviders: [TimerProvider] { savedSettings.providers }
    var providerSummary: String { savedProviders.map(\.title).joined(separator: " + ") }
    var canRun: Bool { isScreenshotPreview || savedProviders.contains { $0.resolve(settings: savedSettings, paths: paths) != nil } }
    func path(for provider: TimerProvider) -> String? {
        if isScreenshotPreview { return "/opt/homebrew/bin/\(provider.rawValue)" }
        return provider.resolve(settings: settings, paths: paths)
    }
    enum ProviderChoice: String, CaseIterable, Identifiable {
        case claude = "Claude", codex = "Codex", both = "Both"
        var id: String { rawValue }
        var providers: [TimerProvider] { switch self { case .claude: return [.claude]; case .codex: return [.codex]; case .both: return [.claude, .codex] } }
    }
    func providerChoice(at index: Int) -> ProviderChoice {
        guard settings.timers.indices.contains(index) else { return .both }
        let providers = settings.timers[index].providers
        return providers.count == 2 ? .both : providers.first == .codex ? .codex : .claude
    }
    func setProviderChoice(at index: Int, to choice: ProviderChoice) {
        guard !busy, !running, settings.timers.indices.contains(index) else { return }
        settings.timers[index].providers = choice.providers
    }
    var scheduled: Bool { enabled || legacy }
    func date(for time: DailyTime) -> Date {
        // A fixed reference day keeps editing independent of today's DST transition.
        Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: time.hour, minute: time.minute)) ?? Date()
    }
    func date(at index: Int) -> Date {
        date(for: settings.times.indices.contains(index) ? settings.times[index] : DailyTime(hour: 7))
    }
    func setTime(at index: Int, to date: Date) {
        guard !busy, !running, settings.times.indices.contains(index) else { return }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        settings.timers[index].time = DailyTime(hour: parts.hour ?? 7, minute: parts.minute ?? 0)
    }
    func addTime() {
        guard !busy, !running, settings.times.count < TimerSettings.maximumTimes else { return }
        if let time = [17, 12, 21, 9, 7].map({ DailyTime(hour: $0) }).first(where: { !settings.times.contains($0) }) {
            settings.timers.append(DailyTimer(time: time, providers: settings.timers.last?.providers ?? [.claude, .codex]))
        }
    }
    func removeTime(at index: Int) {
        guard !busy, !running, settings.times.count > 1, settings.times.indices.contains(index) else { return }
        settings.timers.remove(at: index)
    }
    var nextRun: String {
        guard scheduled, let date = savedSettings.nextRun() else { return "Enable your schedule when you’re ready." }
        return "Next ping \(date.formatted(.dateTime.weekday(.wide).hour().minute()))"
    }
    var scheduledTimers: [DailyTimer] { savedSettings.timers.sorted { $0.time < $1.time } }
    init() {
        #if DEBUG
        if isScreenshotPreview {
            enabled = true
            let today = Calendar.current.startOfDay(for: Date())
            for day in 0..<3 {
                for provider in TimerProvider.allCases {
                    let start = Calendar.current.date(byAdding: .day, value: -day, to: today)!.addingTimeInterval(7 * 3600)
                    history.append(RunRecord(startedAt: start, finishedAt: start.addingTimeInterval(provider == .claude ? 3 : 2), outcome: .success, detail: "Replied with pong.", source: "scheduled", provider: provider))
                }
            }
            return
        }
        #endif
        do { settings = try TimerSettings.load(paths: paths); savedSettings = settings } catch { self.error = "Could not load settings: \(error.localizedDescription)" }
        refresh()
    }
    func refresh() {
        guard !isScreenshotPreview else { return }
        running = RunLock.isRunning(paths: paths)
        do { history = try RunHistory.load(paths: paths) } catch { self.error = "Could not read run history: \(error.localizedDescription)" }
        if let persisted = try? TimerSettings.load(paths: paths) { savedSettings = persisted }
        // Small launchctl calls run off the UI thread.
        let paths = paths
        Task {
            let status = await Task.detached { (Scheduler(paths: paths).isEnabled, Scheduler(paths: paths).hasLegacySchedule) }.value
            self.enabled = status.0; self.legacy = status.1
        }
    }
    func changeSchedule(enabled: Bool) {
        guard !isScreenshotPreview else { return }
        guard !busy else { return }
        busy = true; error = nil; notice = nil
        let settings = settings, paths = paths, runner = runner
        Task {
            let failure = await Task.detached { () -> String? in
                do {
                    let scheduler = Scheduler(paths: paths)
                    if enabled { try scheduler.enable(settings: settings, runner: runner) }
                    else { try scheduler.disable() }
                    return nil
                } catch { return error.localizedDescription }
            }.value
            error = failure; busy = false
            if failure == nil { notice = enabled ? "Daily schedule saved. It runs even when the app is closed." : "Daily schedule is off." }
            refresh()
        }
    }
    func saveSettings() {
        if isScreenshotPreview {
            do { try settings.validate(); savedSettings = settings; error = nil; notice = "Settings saved." }
            catch { self.error = error.localizedDescription }
            return
        }
        if scheduled { changeSchedule(enabled: true); return }
        do { try settings.save(paths: paths); savedSettings = settings; error = nil; notice = "Settings saved." }
        catch { self.error = error.localizedDescription }
    }
    func runNow(provider: TimerProvider? = nil) {
        guard !isScreenshotPreview else { return }
        guard !busy, !running else { return }
        busy = true; running = true; error = nil; notice = nil
        let runner = runner
        Task {
            let failure = await Task.detached { () -> String? in
                do {
                    let arguments = ["run"] + (provider.map { ["--provider", $0.rawValue] } ?? [])
                    let result = try LocalProcess.run(runner.path, arguments, timeout: 200)
                    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                    if result.status != 0, (try? decoder.decode([RunRecord].self, from: Data(result.output.utf8))) == nil { return result.output }
                    return nil
                } catch { return error.localizedDescription }
            }.value
            error = failure; busy = false; running = false; refresh()
        }
    }
    func chooseExecutable(for provider: TimerProvider) {
        guard !isScreenshotPreview else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose the \(provider.cliTitle) executable"
        panel.message = "Select the \(provider.rawValue) executable from your installation."
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false; panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: path(for: provider) ?? "/opt/homebrew/bin/\(provider.rawValue)").deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url {
            guard FileManager.default.isExecutableFile(atPath: url.path) else { error = "Select an executable file."; return }
            if provider == .claude { settings.claudePath = url.path }
            else { settings.codexPath = url.path }
            saveSettings()
        }
    }
    func openSetup(provider: TimerProvider = .claude) {
        guard !isScreenshotPreview else { return }
        guard let executable = path(for: provider) else { error = "Install \(provider.cliTitle) first, then choose its executable in Settings."; return }
        do {
            try paths.prepare()
            let script = paths.root.appendingPathComponent("Claude Codex Timer - \(provider.title) Setup.command")
            let contents = provider == .claude ? ClaudeCommand.setupScript(executable: executable, paths: paths) : CodexCommand.setupScript(executable: executable, paths: paths)
            try contents.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { throw TimerError("Terminal could not be found.") }
            NSWorkspace.shared.open([script], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error { Task { @MainActor in self.error = error.localizedDescription } }
            }
        } catch { self.error = error.localizedDescription }
    }
    func revealData() {
        guard !isScreenshotPreview else { return }
        do { try paths.prepare(); NSWorkspace.shared.open(paths.root) }
        catch { self.error = error.localizedDescription }
    }
}
