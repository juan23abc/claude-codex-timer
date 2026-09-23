import AppKit
import SwiftUI
import ClaudeTimerCore

@MainActor
final class AppModel: ObservableObject {
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
    var runner: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/claude-timer-runner") }
    var claudePath: String? { ClaudeCommand.resolve(settings.claudePath, paths: paths) }
    var savedProviders: [TimerProvider] { savedSettings.providers }
    var providerSummary: String { savedProviders.map(\.title).joined(separator: " + ") }
    var canRun: Bool { savedProviders.contains { $0.resolve(settings: savedSettings, paths: paths) != nil } }
    func path(for provider: TimerProvider) -> String? { provider.resolve(settings: settings, paths: paths) }
    enum ProviderChoice: String, CaseIterable, Identifiable {
        case claude = "Claude", codex = "Codex", both = "Both"
        var id: String { rawValue }
        var providers: [TimerProvider] { switch self { case .claude: return [.claude]; case .codex: return [.codex]; case .both: return [.claude, .codex] } }
    }
    var providerChoice: ProviderChoice {
        get { settings.providers.count == 2 ? .both : settings.providers.first == .codex ? .codex : .claude }
        set { settings.providers = newValue.providers; saveSettings() }
    }
    var scheduled: Bool { enabled || legacy }
    var date: Date {
        get { Calendar.current.date(bySettingHour: settings.hour, minute: settings.minute, second: 0, of: Date()) ?? Date() }
        set { let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue); settings.hour = parts.hour ?? 7; settings.minute = parts.minute ?? 0 }
    }
    var nextRun: String {
        guard scheduled, let date = savedSettings.nextRun() else { return "Enable your schedule when you’re ready." }
        return "Next ping \(date.formatted(.dateTime.weekday(.wide).hour().minute()))"
    }
    var scheduledDate: Date { Calendar.current.date(bySettingHour: savedSettings.hour, minute: savedSettings.minute, second: 0, of: Date()) ?? Date() }
    init() {
        do { settings = try TimerSettings.load(paths: paths); savedSettings = settings } catch { self.error = "Could not load settings: \(error.localizedDescription)" }
        refresh()
    }
    func refresh() {
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
        if scheduled { changeSchedule(enabled: true); return }
        do { try settings.save(paths: paths); savedSettings = settings; error = nil; notice = "Settings saved." }
        catch { self.error = error.localizedDescription }
    }
    func runNow(provider: TimerProvider? = nil) {
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
        guard let executable = path(for: provider) else { error = "Install \(provider.cliTitle) first, then choose its executable in Settings."; return }
        do {
            try paths.prepare()
            let script = paths.root.appendingPathComponent("\(provider.title) Timer Setup.command")
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
        do { try paths.prepare(); NSWorkspace.shared.open(paths.root) }
        catch { self.error = error.localizedDescription }
    }
}
