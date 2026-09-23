#!/bin/bash
# Open the real SwiftUI screens with sample data and all live actions disabled.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
swift build
BIN_DIR="$(swift build --show-bin-path)"
APP_DIR="$PROJECT_DIR/.build/Claude Codex Timer Screenshots.app"
mkdir -p "$APP_DIR/Contents/"{MacOS,Resources}
cp "$BIN_DIR/ClaudeCodexTimer" "$APP_DIR/Contents/MacOS/ClaudeCodexTimer"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set CFBundleIdentifier io.claude-codex-timer.screenshots' "$APP_DIR/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP_DIR"
open -na "$APP_DIR" --args --screenshots -AppleLanguages '(en)' -AppleLocale en_US -AppleInterfaceStyle Light
