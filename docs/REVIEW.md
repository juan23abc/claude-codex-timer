# Project review

Reviewed and rebuilt locally on September 23, 2026.

## Findings addressed

| Original issue | Resolution |
| --- | --- |
| API errors were considered successful assistant replies, including expired logins | Require an exact `pong` from the matching interactive session; reject API error records |
| A new unrelated transcript could be selected as the result | Generate an explicit UUID and read only its transcript; verify the session ID inside each record |
| `--dangerously-skip-permissions` was used for a trivial message | Remove the bypass; disable tools and customizations for the timer session |
| Scripts silently rewrote Claude trust settings and answered prompts | Never edit Claude configuration or send approval keystrokes; expose a manual setup flow |
| Personal home paths and user-specific launchd configuration prevented portability | Generate all installation paths from the current user’s home directory |
| Python discovery, script installation, and CLI dependencies were implicit | Replace shell/Python execution with a compiled native helper and visible executable detection |
| Manual and scheduled runs could overlap | Cross-process advisory lock, automatically released on exit |
| No reliable visible failure state or bounded history | Native run history with distinct errors, setup requirements, and timeouts; retain 100 results |
| README promised a particular usage-window schedule without evidence | Explain that Anthropic controls limits and the timer cannot guarantee a reset time |
| README incorrectly described calendar jobs during sleep | Document catch-up on wake, based on `launchd.plist` semantics |
| No desktop app, build workflow, or tests | SwiftUI window and menu bar, universal app build, isolated tests, build-only CI, contributor and release documentation |

## Automated verification

31 tests pass on Apple silicon. The original 19 cover reply validation, API errors, malformed and partial JSON, unrelated sessions, missing executables, early process exit, real PTY success/failure fixtures, timeout cleanup, setup prompts, concurrent-run locking, bounded history, settings persistence and corruption, DST, path quoting, portable launchd arguments, legacy migration, and rollback when registration fails. Twelve additional tests cover Codex event/exit validation, actual pipe-backed process success and cleanup, provider selection, failure isolation, restricted invocation flags, and backward-compatible settings and history.

The release app and helper build for both `arm64` and `x86_64`. The bundle passes plist validation and strict code-signature verification with an ad-hoc signature. Shell entry points pass syntax checks. Native UI and local schedule checks are recorded separately in ignored `docs/local-verification/` files so personal paths and account details are not prepared for publication.

The installed app’s schedule migration, time editor, disabling, manual run, activity updates, and Terminal setup flow were exercised. A real calendar event launched the helper with the GUI fully stopped, recorded the account-limit failure, and exited cleanly. The final daily time was restored to 07:00. The Intel helper’s status command also ran under Rosetta.

For version 1.1.0, the renamed Claude/Codex Timer app was installed and the native provider selector set to Both. A combined Run now recorded Claude’s usage-limit failure and then a successful Codex pong, each separately visible in the window. The daily schedule remains 07:00 for both providers. The installed background helper matches the bundled helper, and settings/history retain their existing compatible storage locations.

## Remaining limits

- A live Codex call returned `pong`, completed its turn, and exited successfully using the existing ChatGPT login. Codex CLI version: 0.156.1.
- Live Claude calls reach the authenticated CLI, but the current account is at its session usage limit. The app correctly records that as failure. A live successful Claude `pong` remains unverified. Neither provider’s usage-window start/reset behavior has been established by these tests.
- The interactive transcript format is a Claude Code implementation detail and can change. Tested CLI version: 2.1.280.
- Built for Intel, but not run on physical Intel hardware. Runtime checks were on macOS 26.5.2; macOS 13 compatibility is a deployment target, not a completed hardware test.
- Sleep/wake behavior follows macOS documentation; a physical sleep/wake cycle has not been tested here.
- The binary is not Developer ID signed or notarized for public distribution.
- License selection is intentionally deferred. Private GitHub storage is authorized; public visibility and release publication are not.
