# Claude/Codex Timer

A native macOS app that sends one small message to **Claude, Codex, or both** at a time you choose each day.

Choose your providers, set a daily time, and check results in **Activity**. Each provider has its own sign-in, executable, test action, and result. A failed Claude ping does not prevent Codex from running, or vice versa. The daily schedule works when the app is closed.

This project is being prepared for an open-source release. **No license has been selected and no public release has been authorized yet.** It is independent of Anthropic and OpenAI.

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

The app displays **Claude/Codex Timer**. Its file is named `Claude Codex Timer.app` because `/` separates filesystem paths. Drag it to Applications to keep it there. Local builds are ad-hoc signed, not notarized for public distribution.

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
./send-hi.sh --test          # ping all saved providers
./send-hi.sh --provider codex # test only Codex
./uninstall.sh               # disable schedules; keep app, settings, and history
```

The helper supports:

```bash
"dist/Claude Codex Timer.app/Contents/Helpers/claude-timer-runner" providers claude codex
"dist/Claude Codex Timer.app/Contents/Helpers/claude-timer-runner" run --provider codex
"dist/Claude Codex Timer.app/Contents/Helpers/claude-timer-runner" status
"dist/Claude Codex Timer.app/Contents/Helpers/claude-timer-runner" enable 07:00
"dist/Claude Codex Timer.app/Contents/Helpers/claude-timer-runner" disable
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

Claude/Codex Timer has no analytics, direct network requests, or credential storage. Each CLI handles authentication and sends its prompt to its provider. A saved API-key CLI login can still incur API charges; excluding shell API-key variables does not change your saved login type.

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
```

Tests use isolated temporary homes and fake CLI processes. They do not contact providers, change your real schedule, or read credentials. See [CONTRIBUTING.md](CONTRIBUTING.md), [review notes](docs/REVIEW.md), and [release preparation](docs/RELEASE.md).

Claude’s interactive transcript format is an implementation detail that can change. Codex’s automation protocol can also evolve. Unknown or incomplete output fails visibly. Provider references: [Claude CLI](https://code.claude.com/docs/en/cli-reference), [Claude usage guidance](https://support.claude.com/en/articles/9797557-usage-limit-best-practices), [Codex non-interactive mode](https://developers.openai.com/codex/noninteractive), [Codex configuration](https://developers.openai.com/codex/config-reference).

## Release status

**Private development repository.** Public release is not authorized. License selection, final maintainer metadata, Developer ID signing/notarization, and explicit permission to make the project public remain outstanding. No build or CI script publishes releases.
