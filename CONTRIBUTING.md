# Contributing

Claude Codex Timer is maintained by [juan23abc](https://github.com/juan23abc) at [juan23abc/claude-codex-timer](https://github.com/juan23abc/claude-codex-timer) and licensed under [MIT](LICENSE).

## Structure

- `Sources/ClaudeCodexTimer/`: SwiftUI macOS window, menu bar, app state.
- `Sources/ClaudeCodexTimerCore/`: settings, launchd scheduling, result validation, run history, and the Claude PTY / Codex JSON runners.
- `Sources/CPTY/`: C shim for starting and cleaning up a controlling terminal or a pipe-backed subprocess. The child uses only C operations between `fork` and `execve`.
- `Sources/ClaudeCodexTimerRunner/`: independent background executable and command-line entry point.
- `Tests/ClaudeCodexTimerCoreTests/`: isolated behavior tests, including actual PTY subprocesses.
- `Resources/`: app metadata and packaged icon. `Resources/Icon/` contains the supplied logo, cream-background artwork, and generation notes; `scripts/make-icon.swift` exports the macOS icon sizes.

Build with `./scripts/build-app.sh`, then open `dist/Claude Codex Timer.app`. `swift run ClaudeCodexTimer` is useful for UI iteration, but running pings from the GUI requires the packaged helper. Run `swift test` before submitting changes. Real provider tests consume account usage and should be run explicitly, never automatically in CI.

## Making a contribution

Open an [issue](https://github.com/juan23abc/claude-codex-timer/issues) to report a bug or discuss a feature. Include the macOS version, app version, selected providers, CLI versions, and steps to reproduce. Redact account details and personal paths from logs and screenshots.

For a code change, fork the repository, create a focused branch, and open a pull request explaining the problem, the resulting behavior, and how you verified it. Include screenshots for visible UI changes. Contributions are provided under the project's [MIT license](LICENSE).

## Builds, packaging, and screenshots

```bash
swift test
./scripts/build-app.sh --universal
./scripts/build-dmg.sh --skip-build          # headless packaging, used in CI
./scripts/build-dmg.sh --skip-build --layout # arrange the install window using Finder
bash -n install.sh uninstall.sh ping.sh send-hi.sh scripts/*.sh
```

The DMG contains the app and an Applications shortcut. Packaging verifies both architectures and the app signature, then writes `dist/ClaudeCodexTimer.dmg` and its `.sha256` checksum. Keep the DMG asset name stable so the README's latest-release download link continues to work. Build products belong in release assets, not Git. See [release preparation](docs/RELEASE.md) for signing and publication.

Run `./scripts/preview-screenshots.sh` to open a debug build with sample history and example CLI paths. This preview does not read account history, write settings, change schedules, or run providers. Capture the window's Overview, Settings, and Activity pages into `docs/screenshots/`; identify the sample data in the README. The `--screenshots` mode is absent from release builds. Screenshots should show the actual UI and contain no personal data.

## Expectations

Keep the app native and dependency-free. Never add permission bypasses, auto-accept trust prompts, rewrite Claude configuration, or silently report unknown transcript formats as success. Keep run isolation, bounded execution, migration rollback, and credential-free tests intact.

New settings need a compatible decoding strategy. Changes to scheduling or PTY behavior need tests covering failure and cleanup paths. Do not commit local settings, logs, account details, build products, signing keys, or screenshots containing personal information.

## Naming and compatibility

| Purpose | Name |
| --- | --- |
| App display and bundle | `Claude Codex Timer`, `Claude Codex Timer.app` |
| Swift package and app target | `ClaudeCodexTimer` |
| Core, runner, and test targets | `ClaudeCodexTimerCore`, `ClaudeCodexTimerRunner`, `ClaudeCodexTimerCoreTests` |
| Bundled helper | `claude-codex-timer-runner` |
| Repository | `claude-codex-timer` |
| Signing environment variable | `CLAUDE_CODEX_TIMER_SIGN_IDENTITY` |

These original identifiers deliberately remain stable for installed copies:

- Bundle ID `io.claude-timer.app` preserves macOS app identity.
- `AppPaths` keeps the `ClaudeTimer` Application Support and Logs folders, the installed `bin/claude-timer-runner`, and `~/.claude-timer` so saved data, existing schedule arguments, and Claude folder trust continue to work.
- LaunchAgent `io.claude-timer.daily` remains the single daily job. `com.juan.claude-morning-timer` identifies the original script job for migration and removal only.
- The shell entry points recognize the older bundle/helper names. `send-hi.sh` forwards to `ping.sh`, and `CLAUDE_TIMER_SIGN_IDENTITY` remains a fallback for existing build setups.

Do not rename persistent identifiers without an explicit migration that preserves saved data and avoids duplicate schedules. Use the current product names for new files, targets, commands, and documentation.
