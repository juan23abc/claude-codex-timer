// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeTimer",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ClaudeTimer", targets: ["ClaudeTimer"]),
        .executable(name: "claude-timer-runner", targets: ["ClaudeTimerRunner"])
    ],
    targets: [
        .target(name: "CPTY"),
        .target(name: "ClaudeTimerCore", dependencies: ["CPTY"]),
        .executableTarget(name: "ClaudeTimer", dependencies: ["ClaudeTimerCore"]),
        .executableTarget(name: "ClaudeTimerRunner", dependencies: ["ClaudeTimerCore"]),
        .testTarget(name: "ClaudeTimerCoreTests", dependencies: ["ClaudeTimerCore"])
    ]
)
