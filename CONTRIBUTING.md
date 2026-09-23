# Contributing

The project is maintained in a private repository and is awaiting a license decision and permission for public release. These notes prepare it for a future public repository.

## Structure

- `Sources/ClaudeTimer/`: SwiftUI macOS window, menu bar, app state.
- `Sources/ClaudeTimerCore/`: settings, launchd scheduling, result validation, run history, and the Claude PTY / Codex JSON runners.
- `Sources/CPTY/`: C shim for starting and cleaning up a controlling terminal or a pipe-backed subprocess. The child uses only C operations between `fork` and `execve`.
- `Sources/ClaudeTimerRunner/`: independent background executable and command-line entry point.
- `Tests/ClaudeTimerCoreTests/`: isolated behavior tests, including actual PTY subprocesses.
- `Resources/`: app metadata and original icon; `scripts/make-icon.swift` is its vector source.

Build with `./scripts/build-app.sh`, then open `dist/Claude Codex Timer.app`. `swift run ClaudeTimer` is useful for UI iteration, but running pings from the GUI requires the packaged helper. Run `swift test` before submitting changes. Real provider tests consume account usage and should be run explicitly, never automatically in CI.

## Expectations

Keep the app native and dependency-free. Never add permission bypasses, auto-accept trust prompts, rewrite Claude configuration, or silently report unknown transcript formats as success. Keep run isolation, bounded execution, migration rollback, and credential-free tests intact.

New settings need a compatible decoding strategy. Changes to scheduling or PTY behavior need tests covering failure and cleanup paths. Do not commit local settings, logs, account details, build products, signing keys, or screenshots containing personal information.
