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
APP_DIR="$PROJECT_DIR/dist/Claude Codex Timer.app"
mkdir -p "$APP_DIR/Contents/"{MacOS,Helpers,Resources}
cp "$BIN_DIR/ClaudeTimer" "$APP_DIR/Contents/MacOS/ClaudeTimer"
cp "$BIN_DIR/claude-timer-runner" "$APP_DIR/Contents/Helpers/claude-timer-runner"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
if [[ ! -f Resources/AppIcon.icns ]]; then
  mkdir -p .build/AppIcon.iconset
  swift scripts/make-icon.swift .build/AppIcon.iconset
  iconutil -c icns .build/AppIcon.iconset -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
chmod 755 "$APP_DIR/Contents/MacOS/ClaudeTimer" "$APP_DIR/Contents/Helpers/claude-timer-runner"
plutil -lint "$APP_DIR/Contents/Info.plist"
codesign --force --sign "${CLAUDE_TIMER_SIGN_IDENTITY:--}" --options runtime "$APP_DIR/Contents/Helpers/claude-timer-runner"
codesign --force --sign "${CLAUDE_TIMER_SIGN_IDENTITY:--}" --options runtime "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
echo "Built: $APP_DIR"
