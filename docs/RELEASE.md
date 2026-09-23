# Release preparation

Maintainer: [juan23abc](https://github.com/juan23abc) · Repository: [juan23abc/claude-codex-timer](https://github.com/juan23abc/claude-codex-timer) · License: [MIT](../LICENSE).

The initial distribution is a universal, ad-hoc signed DMG. It is not Developer ID signed or notarized. The README and release notes disclose the first-open macOS security prompt. The repository is currently private; changing visibility and publishing the prepared public release are separate final publication steps. Build and CI scripts never publish releases or push code.

## Build and verify

```bash
swift test
./scripts/build-app.sh --universal
./scripts/build-dmg.sh --skip-build --layout
bash -n install.sh uninstall.sh ping.sh send-hi.sh scripts/*.sh
```

`--layout` uses Finder to arrange the app, Applications shortcut, and installation background. For headless CI, omit it. The DMG builder checks both architectures, verifies the app signature and disk image, and generates a SHA-256 checksum.

Before publication:

- Inspect the mounted DMG, drag the app to Applications, eject the image, and open the copied app.
- Verify the settings, setup flow, schedule enable/edit/disable, app relaunch, and a scheduled run with the app quit. Use isolated fixtures for automated tests; real pings consume account usage.
- Check the current [review notes](REVIEW.md) for unverified hardware and provider cases. Do not present sample screenshot activity as live verification.
- Confirm redistribution rights for the included brand artwork, or replace it with original artwork; see [artwork notes](../Resources/Icon/README.md).
- Review the complete Git history and release contents for secrets and personal data. Keep `.build`, `dist`, local verification evidence, signing keys, credentials, and transcripts out of Git.
- Keep `CFBundleShortVersionString`, `CFBundleVersion`, the Settings version label, and release tag consistent when changing versions. The persistent bundle and LaunchAgent identifiers stay stable as documented in [CONTRIBUTING.md](../CONTRIBUTING.md).

## GitHub assets

The first release is `v1.1.0`. Attach these generated files:

- `dist/ClaudeCodexTimer.dmg`
- `dist/ClaudeCodexTimer.dmg.sha256`

Use [release notes](releases/v1.1.0.md) for the release body. Upload a draft for review before publication. Keep the DMG filename stable: the README uses `https://github.com/juan23abc/claude-codex-timer/releases/latest/download/ClaudeCodexTimer.dmg`. Draft and private releases are not publicly downloadable. Once publishing the first release, remove the pending-release sentence from the README and verify the download without authentication.

To verify a download, place both assets in the same directory and run:

```bash
shasum -a 256 -c ClaudeCodexTimer.dmg.sha256
```

## Future Developer ID releases

Set `CLAUDE_CODEX_TIMER_SIGN_IDENTITY` to the installed Developer ID Application identity when building. The earlier `CLAUDE_TIMER_SIGN_IDENTITY` name remains supported as a fallback. Before advertising a notarized release, submit the signed distribution to Apple's notary service, staple the accepted ticket, and verify Gatekeeper behavior on a downloaded copy. Regenerate the checksum after signing or stapling changes the DMG.

Apple documents [Developer ID signing and notarization](https://developer.apple.com/developer-id/) and [first-open security behavior](https://support.apple.com/en-us/102445). Never bundle either provider CLI or its authentication state.
