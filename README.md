<p align="center">
  <img src="Resources/Icon/AppIcon.png" alt="Claude Codex Timer app icon" width="112">
</p>

<h1 align="center">Claude Codex Timer</h1>

<p align="center">Start your 5h usage limit window early, for Claude and Codex.<br>One small ping, at the time you choose. Built for Mac.</p>

<p align="center">
  <a href="https://github.com/juan23abc/claude-codex-timer/releases/latest/download/ClaudeCodexTimer.dmg"><img alt="Download for Mac — DMG" src="https://img.shields.io/badge/Download_for_Mac-DMG-C26040?style=for-the-badge&logo=apple&logoColor=white"></a>
</p>

<p align="center">macOS 13+ · Apple silicon &amp; Intel · Free &amp; MIT licensed</p>

![Claude Codex Timer overview showing the daily schedule and separate Claude and Codex results](docs/screenshots/overview.png)

Choose **Claude, Codex, or both**, set a daily time, and let your Mac handle the routine. The schedule works even when the app is closed, and each provider gets its own result in **Activity**.

- **Your schedule.** Set a local daily time, pause it, or run a ping on demand.
- **Your accounts.** Use your existing CLI sign-ins, with separate setup and tests for each provider.
- **Clear results.** See verified replies, setup issues, timeouts, and usage-limit failures.
- **Native and local.** SwiftUI window, menu bar controls, local history, and no analytics.

If it makes your mornings easier, [star the repository](https://github.com/juan23abc/claude-codex-timer) to support the project.

## Download and install

**[Download ClaudeCodexTimer.dmg](https://github.com/juan23abc/claude-codex-timer/releases/latest/download/ClaudeCodexTimer.dmg)** · [Release notes and checksums](https://github.com/juan23abc/claude-codex-timer/releases/latest)

1. Open the DMG and drag **Claude Codex Timer** into **Applications**.
2. Eject the disk image, then open the app from Applications.
3. In **Settings**, choose your providers, complete their CLI setup, and try **Test ping**.
4. Choose a daily time and enable the schedule.

**First launch:** this initial build is ad-hoc signed and is **not notarized by Apple**. If macOS blocks it and you trust this download, first try opening it, then use **System Settings → Privacy & Security → Open Anyway**. See [Apple’s instructions](https://support.apple.com/en-us/102445). You do not need to disable Gatekeeper.

**You still need [Claude Code](https://code.claude.com/docs/en/setup) and/or [Codex CLI](https://developers.openai.com/codex/cli) installed and signed in.** The DMG includes the timer and its helper, not either provider CLI. Pings use your account’s usage allowance.

## Screenshots

<details>
<summary><strong>Settings — choose your providers and daily time</strong></summary>

![Settings with a daily time, provider selection, and separate Claude and Codex connections](docs/screenshots/settings.png)

</details>

<details>
<summary><strong>Activity — a separate result for every provider</strong></summary>

![Activity showing individual Claude and Codex ping results](docs/screenshots/activity.png)

</details>

Screenshots show the native app with sample activity and example executable paths.

An independent project maintained by [juan23abc](https://github.com/juan23abc). Not affiliated with or endorsed by Anthropic or OpenAI.

## What it does

Each selected provider receives `Reply with exactly: pong`:

- **Claude:** opens a fresh interactive CLI session. Success requires the exact session’s assistant reply to be `pong`, without an API error.
- **Codex:** uses the documented `codex exec --json` automation interface. Success requires a started thread, completed turn, an exact `pong` agent reply, and exit code zero. Error events and incomplete responses fail. Each call is ephemeral, so Codex does not retain its session rollout.

Pings run sequentially, with a separate history entry for each provider. Expired logins, usage limits, missing executables, setup prompts, unexpected replies, and timeouts are visible failures.

The original motivation was to start a usage window early in the day. **The app cannot guarantee when either provider’s window starts or resets.** Anthropic and OpenAI control usage accounting. Check the provider’s own usage display for the authoritative reset time. Pings consume account usage; API billing and subscription limits differ. The runner reuses saved CLI authentication and does not inherit API keys from the calling shell.

## Requirements

- macOS 13 Ventura or later.
- Current [Claude Code](https://code.claude.com/docs/en/setup) and/or [Codex CLI](https://developers.openai.com/codex/cli), with an active login for each selected provider. You only need the CLIs you select.
- Tested CLI versions: Claude Code **2.1.280**, Codex CLI **0.156.1**. Older releases may not support the required flags.
- To build: Xcode or Command Line Tools with Swift 5.9 or later. The app requires no third-party Swift packages, Python, Node, or Electron. Each provider CLI has its own installation requirements.

## Build and open

```bash
./scripts/build-app.sh
open "dist/Claude Codex Timer.app"
```

The app and bundle use **Claude Codex Timer**; the Swift package and app executable use `ClaudeCodexTimer`. Drag `Claude Codex Timer.app` to Applications to keep it there. Local builds are ad-hoc signed, not notarized for public distribution.

1. In **Settings**, choose **Claude**, **Codex**, or **Both** under **Send pings to**.
2. Check the selected CLIs are found; **Choose…** supports custom installation paths.
3. For Claude, **Open Claude setup**, complete sign-in and explicitly trust the dedicated `~/.claude-timer` folder. Type `/exit` when finished. For Codex, **Sign in to Codex** opens the official login flow in Terminal; an existing CLI login is reused automatically.
4. Use the provider’s **Test ping** or **Run now** to verify replies. Run now uses the saved provider selection.
5. Choose a daily time and enable the schedule. The default is **7:00 AM local time**.

Upgrading preserves settings and history. Old history entries are labeled Claude, and older settings remain Claude-only until you choose Both or Codex. The original script timer has an **Upgrade schedule** action that saves a backup and replaces its job only after the new job registers successfully. Internal data paths and the LaunchAgent identifier retain their original names for compatibility.

### Terminal shortcuts

```bash
./install.sh                 # build, install to ~/Applications, enable saved time
./install.sh 07:30           # same, selecting a time
./ping.sh                   # ping all saved providers
./ping.sh --provider codex   # test only Codex
./uninstall.sh               # disable schedules; keep app, settings, and history
```

`send-hi.sh` remains an alias for older integrations. The helper supports:

```bash
"dist/Claude Codex Timer.app/Contents/Helpers/claude-codex-timer-runner" providers claude codex
"dist/Claude Codex Timer.app/Contents/Helpers/claude-codex-timer-runner" run --provider codex
"dist/Claude Codex Timer.app/Contents/Helpers/claude-codex-timer-runner" status
"dist/Claude Codex Timer.app/Contents/Helpers/claude-codex-timer-runner" enable 07:00
"dist/Claude Codex Timer.app/Contents/Helpers/claude-codex-timer-runner" disable
```

`run` prints a JSON array of provider results and exits nonzero if any selected provider fails. A single-provider test does not change the saved selection.

## Scheduling and sleep

A per-user macOS LaunchAgent runs the compiled helper, without `sudo`. The helper is copied outside Desktop/Documents so scheduling does not depend on the app’s location or access to the source folder. Enabling or editing the schedule does not immediately send a ping.

- You must be logged in; the app may be closed or quit.
- A calendar event missed during sleep runs after wake. Multiple missed events coalesce into one. This does **not** wake the Mac; see `man launchd.plist`.
- Runs missed while shut down or logged out are not guaranteed to replay.
- Local time-zone and daylight-saving changes apply.
- macOS background-item controls can prevent jobs from running. Loaded status cannot guarantee a future launch or network connectivity.
- A process lock prevents overlapping batches. Each provider has a 90-second timeout; both together may take about three minutes. The timer has no retry loop.

## Privacy and local files

Claude Codex Timer has no analytics, direct network requests, or credential storage. Each CLI handles authentication and sends its prompt to its provider. A saved API-key CLI login can still incur API charges; excluding shell API-key variables does not change your saved login type.

Claude uses safe mode with built-in tools disabled, MCP tools denied, and hooks disabled through session settings. The app never edits `~/.claude.json` or answers trust prompts.

Codex uses a read-only sandbox with approvals disabled, ignores user configuration and execution rules for this invocation, skips project instructions, and disables shell execution, hooks, plugins, app integrations, multi-agent tools, and web search through session options. Saved authentication is still used. No sandbox or permission bypass is used. Organization-managed policy can still apply to either CLI.

| Location | Contents |
| --- | --- |
| `~/Library/Application Support/ClaudeTimer/` | Settings, last 100 provider results, lock, setup scripts, installed helper, Codex workspace, optional legacy backup |
| `~/Library/LaunchAgents/io.claude-timer.daily.plist` | Daily schedule for selected providers |
| `~/Library/Logs/ClaudeTimer/runner.log` | Helper diagnostic output |
| `~/.claude-timer/` | Claude’s dedicated working folder |
| `~/.claude/projects/…` | Claude timer transcripts, managed by Claude Code |

Use **Show local data in Finder** to inspect app data. Redact account or usage details before sharing errors. Codex pings use ephemeral sessions, but the Codex CLI may maintain its own local diagnostics and authentication state. Removing the app alone does not remove its schedule: turn the schedule off first or run `./uninstall.sh`.

## Development

```bash
swift test
./scripts/build-app.sh
./scripts/build-app.sh --universal  # Apple silicon + Intel
./scripts/build-dmg.sh --layout    # universal DMG with a Finder install window
```

Tests use isolated temporary homes and fake CLI processes. They do not contact providers, change your real schedule, or read credentials. See [CONTRIBUTING.md](CONTRIBUTING.md), [review notes](docs/REVIEW.md), and [release preparation](docs/RELEASE.md).

Claude’s interactive transcript format is an implementation detail that can change. Codex’s automation protocol can also evolve. Unknown or incomplete output fails visibly. Provider references: [Claude CLI](https://code.claude.com/docs/en/cli-reference), [Claude usage guidance](https://support.claude.com/en/articles/9797557-usage-limit-best-practices), [Codex non-interactive mode](https://developers.openai.com/codex/noninteractive), [Codex configuration](https://developers.openai.com/codex/config-reference).

## Release status

The first DMG is being prepared for release; the download links above become available when it is published. See the [release checklist](docs/RELEASE.md) for remaining checks. Prebuilt apps are not yet Developer ID signed or notarized. No build or CI script publishes releases.

## License

[MIT License](LICENSE) · Copyright (c) 2026 juan23abc.

The license permits commercial use, modification, and redistribution, including closed-source derivatives, provided its copyright and license notice are preserved. The software is provided without warranty. Third-party names and logos belong to their respective owners; the software license does not grant rights to their trademarks. See the [artwork notes](Resources/Icon/README.md).
