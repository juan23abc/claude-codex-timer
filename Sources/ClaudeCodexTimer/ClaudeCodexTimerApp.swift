import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { sender.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil) }
        return true
    }
}

@main
struct ClaudeCodexTimerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        Window("Claude Codex Timer", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 850, minHeight: 650)
                .tint(Theme.accent)
        }
        .defaultSize(width: 920, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appSettings) {
                Button("Claude Codex Timer Settings…") { model.selection = .settings; NSApp.activate(ignoringOtherApps: true); NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil) }.keyboardShortcut(",")
            }
        }
        MenuBarExtra("Claude Codex Timer", systemImage: "timer") { TimerMenu(model: model) }
    }
}

struct TimerMenu: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(model.scheduled ? model.nextRun : "Daily schedule is off")
        if model.running { Text("Ping in progress…") }
        Divider()
        Button("Run now") { model.runNow() }.disabled(model.busy || model.running || !model.canRun)
        Button("Open Claude Codex Timer") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true); model.refresh() }
        Divider()
        Button("Quit Claude Codex Timer") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
