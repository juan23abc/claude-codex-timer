// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeCodexTimer",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ClaudeCodexTimer", targets: ["ClaudeCodexTimer"]),
        .executable(name: "claude-codex-timer-runner", targets: ["ClaudeCodexTimerRunner"])
    ],
    targets: [
        .target(name: "CPTY"),
        .target(name: "ClaudeCodexTimerCore", dependencies: ["CPTY"]),
        .executableTarget(name: "ClaudeCodexTimer", dependencies: ["ClaudeCodexTimerCore"]),
        .executableTarget(name: "ClaudeCodexTimerRunner", dependencies: ["ClaudeCodexTimerCore"]),
        .testTarget(name: "ClaudeCodexTimerCoreTests", dependencies: ["ClaudeCodexTimerCore"])
    ]
)
