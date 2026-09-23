#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
BUILD_ARGS=(-c release)
if [[ "${1:-}" == "--universal" && $# -eq 1 ]]; then
  BUILD_ARGS+=(--arch arm64 --arch x86_64)
elif [[ $# -ne 0 ]]; then
  echo "Usage: ./scripts/build-app.sh [--universal]" >&2
  exit 2
fi
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
OUTPUT_DIR="$PROJECT_DIR/dist/Claude Codex Timer.app"
# Assemble a fresh bundle so renamed executables cannot survive from an older build.
mkdir -p "$PROJECT_DIR/dist"
STAGING_DIR="$(mktemp -d "$PROJECT_DIR/dist/.app-build.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
APP_DIR="$STAGING_DIR/Claude Codex Timer.app"
mkdir -p "$APP_DIR/Contents/"{MacOS,Helpers,Resources}
cp "$BIN_DIR/ClaudeCodexTimer" "$APP_DIR/Contents/MacOS/ClaudeCodexTimer"
cp "$BIN_DIR/claude-codex-timer-runner" "$APP_DIR/Contents/Helpers/claude-codex-timer-runner"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp LICENSE "$APP_DIR/Contents/Resources/LICENSE"
if [[ ! -f Resources/AppIcon.icns || Resources/Icon/AppIcon.png -nt Resources/AppIcon.icns || scripts/make-icon.swift -nt Resources/AppIcon.icns ]]; then
  mkdir -p .build/AppIcon.iconset
  swift scripts/make-icon.swift .build/AppIcon.iconset
  iconutil -c icns .build/AppIcon.iconset -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
chmod 755 "$APP_DIR/Contents/MacOS/ClaudeCodexTimer" "$APP_DIR/Contents/Helpers/claude-codex-timer-runner"
plutil -lint "$APP_DIR/Contents/Info.plist"
# Accept the old environment variable for existing local build setups.
SIGN_IDENTITY="${CLAUDE_CODEX_TIMER_SIGN_IDENTITY:-${CLAUDE_TIMER_SIGN_IDENTITY:--}}"
codesign --force --sign "$SIGN_IDENTITY" --options runtime "$APP_DIR/Contents/Helpers/claude-codex-timer-runner"
codesign --force --sign "$SIGN_IDENTITY" --options runtime "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
rm -rf "$OUTPUT_DIR"
mv "$APP_DIR" "$OUTPUT_DIR"
echo "Built: $OUTPUT_DIR"
