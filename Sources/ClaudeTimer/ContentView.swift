import SwiftUI
import ClaudeTimerCore

enum Theme {
    static let accent = Color(red: 0.76, green: 0.37, blue: 0.25)
    static let card = Color(nsColor: .controlBackgroundColor)
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    private let refreshTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 40, height: 40)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Claude/Codex Timer").font(.headline).fixedSize(horizontal: false, vertical: true)
                        Text("A daily head start").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 15).padding(.top, 24)
                List(AppModel.Page.allCases, selection: $model.selection) { page in
                    Label(page.rawValue, systemImage: page.symbol).tag(page).padding(.vertical, 5)
                }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 7) {
                    Label("Runs on your Mac", systemImage: "desktopcomputer").font(.caption)
                    Text("An independent project").font(.caption2)
                }.foregroundStyle(.secondary).padding(20)
            }.navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 250)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let error = model.error { banner(error, symbol: "exclamationmark.triangle.fill", color: .orange) }
                    else if let notice = model.notice { banner(notice, symbol: "checkmark.circle.fill", color: .secondary) }
                    switch model.selection {
                    case .overview: overview
                    case .activity: activity
                    case .settings: settings
                    }
                }.padding(32).frame(maxWidth: 780, alignment: .leading).frame(maxWidth: .infinity)
            }.background(Color(nsColor: .windowBackgroundColor))
        }
        .onReceive(refreshTimer) { _ in model.refresh() }
        .toolbar { ToolbarItem(placement: .automatic) { Button { model.refresh() } label: { Label("Refresh status", systemImage: "arrow.clockwise") }.help("Refresh status") } }
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 24) {
            heading("Good timing.", subtitle: "One small ping. A more predictable start to your day.")
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Label("DAILY SCHEDULE", systemImage: "sunrise").font(.system(size: 11, weight: .semibold)).tracking(1.2).foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 6) { Circle().fill(model.scheduled ? Color.green : .secondary).frame(width: 6, height: 6); Text(model.scheduled ? "On" : "Off").font(.caption.weight(.medium)) }
                        .padding(.horizontal, 10).padding(.vertical, 5).background(.quaternary, in: Capsule())
                }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(model.scheduledDate, format: .dateTime.hour().minute()).font(.system(size: 52, weight: .light, design: .rounded)).monospacedDigit().accessibilityLabel("Daily time \(model.scheduledDate.formatted(date: .omitted, time: .shortened))")
                    Text("every day").font(.callout).foregroundStyle(.secondary)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.nextRun).font(.subheadline.weight(.medium))
                        Text("\(model.providerSummary) · \(TimeZone.current.identifier)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Change time") { model.selection = .settings }.accessibilityLabel("Change time")
                }
                Divider()
                HStack(spacing: 12) {
                    Button { model.changeSchedule(enabled: !model.scheduled) } label: {
                        Label(model.scheduled ? "Turn off schedule" : "Enable schedule", systemImage: model.scheduled ? "pause" : "calendar.badge.plus")
                    }.disabled(model.busy || model.running || (!model.scheduled && !model.canRun)).accessibilityLabel(model.scheduled ? "Turn off schedule" : "Enable schedule")
                    Spacer()
                    Button { model.runNow() } label: {
                        HStack(spacing: 7) {
                            if model.running { ProgressView().controlSize(.small) }
                            else { Image(systemName: "play.fill") }
                            Text(model.running ? "Pinging…" : "Run now")
                        }
                    }.buttonStyle(.borderedProminent).disabled(model.busy || model.running || !model.canRun).keyboardShortcut("r", modifiers: .command).accessibilityLabel(model.running ? "Pinging" : "Run now")
                }
            }.padding(24).background(Theme.card, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
            if model.legacy {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "arrow.up.circle").foregroundStyle(Theme.accent).font(.title2)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Your existing timer is still scheduled.").font(.subheadline.weight(.medium))
                        Text("Upgrade it to use this app’s verified replies and run history. Your daily time stays the same.").font(.caption).foregroundStyle(.secondary)
                        Button("Upgrade schedule") { model.changeSchedule(enabled: true) }.disabled(model.busy || model.running).accessibilityLabel("Upgrade schedule")
                    }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("LATEST ACTIVITY").font(.system(size: 11, weight: .semibold)).tracking(1.2).foregroundStyle(.secondary); Spacer(); Button("View all") { model.selection = .activity }.buttonStyle(.link) }
                ForEach(model.savedProviders) { provider in
                    if let record = model.history.first(where: { $0.provider == provider }) { RunRow(record: record) }
                    else {
                        HStack(spacing: 12) {
                            Image(systemName: "bubble.left.and.bubble.right").font(.title2).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(provider.title) is ready for a first ping").font(.subheadline.weight(.medium))
                                Text("Run now to check that \(provider.title) can reply.").font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 10)
                    }
                }
            }
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "info.circle")
                Text("Pings use the selected accounts. Anthropic and OpenAI control their usage windows; a reply does not guarantee a reset time. Your Mac must be logged in. A sleeping Mac runs the missed pings after waking.")
            }.font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !model.canRun || model.savedProviders.contains(where: { provider in model.history.first(where: { $0.provider == provider }).map { $0.outcome != .success } ?? false }) {
                Button("Manage connections", systemImage: "slider.horizontal.3") { model.selection = .settings }
            }
        }
    }
    private var activity: some View {
        VStack(alignment: .leading, spacing: 24) {
            heading("Every ping, accounted for.", subtitle: "Your last 100 runs, stored only on this Mac.")
            if model.history.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 38, weight: .light)).foregroundStyle(.secondary)
                    Text("No runs yet").font(.headline)
                    Text("Your first result will appear here.").foregroundStyle(.secondary)
                    Button("Run now") { model.runNow() }.disabled(model.busy || model.running || !model.canRun)
                }.frame(maxWidth: .infinity).padding(.vertical, 70)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(model.history) { record in
                        RunRow(record: record).padding(18)
                        if record.id != model.history.last?.id { Divider().padding(.leading, 52) }
                    }
                }.background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            }
            Button("Show local data in Finder", systemImage: "folder") { model.revealData() }
        }
    }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 24) {
            heading("Make it your routine.", subtitle: "Choose your providers and a time to start the day.")
            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    DatePicker("Daily ping", selection: Binding(get: { model.date }, set: { model.date = $0 }), displayedComponents: [.hourAndMinute])
                    Picker("Send pings to", selection: Binding(get: { model.providerChoice }, set: { model.providerChoice = $0 })) {
                        ForEach(AppModel.ProviderChoice.allCases) { choice in Text(choice.rawValue).tag(choice) }
                    }.pickerStyle(.segmented).disabled(model.busy || model.running)
                    Text("Follows this Mac’s local time zone, including daylight saving changes.").font(.caption).foregroundStyle(.secondary)
                    HStack { Spacer(); Button("Save schedule") { model.saveSettings() }.buttonStyle(.borderedProminent).disabled(model.busy || model.running) }
                }.padding(12)
            } label: { Label("Schedule", systemImage: "calendar") }
            ForEach(TimerProvider.allCases) { provider in connection(provider) }
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("The daily schedule keeps working when this app is closed. Turning it off removes the background schedule; your settings and history stay on this Mac.")
                    Text("Claude/Codex Timer has no analytics and stores no credentials. Each CLI handles its own sign-in and sends its ping to Anthropic or OpenAI.")
                    Button("Show local data in Finder") { model.revealData() }
                }.font(.caption).foregroundStyle(.secondary).padding(12)
            } label: { Label("On this Mac", systemImage: "desktopcomputer") }
            Text("Claude/Codex Timer 1.1.0 · An independent project").font(.caption).foregroundStyle(.tertiary)
        }
    }
    private func connection(_ provider: TimerProvider) -> some View {
        let path = model.path(for: provider)
        return GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(path == nil ? "\(provider.cliTitle) not found" : "\(provider.cliTitle) found", systemImage: path == nil ? "exclamationmark.circle" : "checkmark.circle.fill").foregroundStyle(path == nil ? .orange : .green)
                    Spacer()
                    Button("Choose…") { model.chooseExecutable(for: provider) }.disabled(model.busy || model.running)
                }
                Text(path ?? "Install \(provider.cliTitle) to get started.").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(3)
                Text(provider == .claude ? "Use your Claude sign-in. Open setup to finish sign-in and trust the timer folder. Type /exit when you’re done." : "Use your Codex sign-in. Sign in opens the official Codex login in Terminal. A test ping consumes a small amount of usage.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(provider == .claude ? "Open Claude setup" : "Sign in to Codex", systemImage: "terminal") { model.openSetup(provider: provider) }.disabled(path == nil || model.busy || model.running)
                    Button("Test ping") { model.runNow(provider: provider) }.disabled(path == nil || model.busy || model.running)
                    Spacer()
                    Link("Install ↗", destination: provider.installURL)
                }
            }.padding(12)
        } label: { Label(provider.title, systemImage: "terminal") }
    }
    private func heading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(title).font(.system(size: 28, weight: .semibold, design: .rounded)); Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }.padding(.top, 5)
    }
    private func banner(_ text: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .top) { Image(systemName: symbol).foregroundStyle(color); Text(text).font(.caption); Spacer(); Button { model.error = nil; model.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss message") }
            .padding(12).background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct RunRow: View {
    let record: RunRecord
    var success: Bool { record.outcome == .success }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: success ? "checkmark.circle.fill" : "exclamationmark.circle.fill").font(.title3).foregroundStyle(success ? .green : .orange).padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text(success ? "Ping delivered" : record.outcome == .needsSetup ? "Setup needed" : record.outcome == .timedOut ? "Ping timed out" : "Ping failed").font(.subheadline.weight(.semibold)); Spacer(); Text(record.startedAt, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.caption).foregroundStyle(.secondary) }
                Text(record.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Text("\(record.provider.title) · \(record.source.capitalized) · \(max(0, Int(record.finishedAt.timeIntervalSince(record.startedAt))))s").font(.caption2).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
