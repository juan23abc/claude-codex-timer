# Public release preparation

The owner has authorized a private GitHub repository. Making it public or publishing a release requires separate explicit permission. No build or CI script pushes code or publishes releases.

Before a public release:

- Select an open-source license and add the corresponding LICENSE file; currently undecided by request.
- Confirm maintainer details and the final bundle identifier if needed.
- Run `swift test` and `./scripts/build-app.sh --universal` on macOS.
- Smoke-test on Apple silicon and Intel, including the oldest supported macOS version.
- Verify real successful pings for both providers using logged-in accounts with available usage.
- Check the native window, setup flow, schedule enable/edit/disable, app relaunch, and a scheduled run with the app quit.
- If distributing prebuilt binaries, sign with a Developer ID Application identity, notarize with Apple, and staple the ticket. `CLAUDE_TIMER_SIGN_IDENTITY` selects the build script’s signing identity. Public distribution and notarization have not been performed.
- Review the source-only change set for secrets and personal data. `.build`, `dist`, local verification evidence, and runtime files must stay untracked.

CI only builds and tests. It has no publication step and no write permissions. Never bundle either provider CLI, credentials, or personal transcripts with the app.
