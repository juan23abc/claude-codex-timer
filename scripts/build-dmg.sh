#!/bin/bash
# Build a universal, drag-to-Applications disk image. --layout requires Finder.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
SKIP_BUILD=false
LAYOUT=false
for ARG in "$@"; do
  case "$ARG" in
    --skip-build) SKIP_BUILD=true ;;
    --layout) LAYOUT=true ;;
    *) echo "Usage: ./scripts/build-dmg.sh [--skip-build] [--layout]" >&2; exit 2 ;;
  esac
done
if [[ "$SKIP_BUILD" == false ]]; then ./scripts/build-app.sh --universal; fi
APP_DIR="$PROJECT_DIR/dist/Claude Codex Timer.app"
codesign --verify --deep --strict "$APP_DIR"
for BINARY in "$APP_DIR/Contents/MacOS/ClaudeCodexTimer" "$APP_DIR/Contents/Helpers/claude-codex-timer-runner"; do
  lipo "$BINARY" -verify_arch arm64 x86_64
done
WORK_DIR="$(mktemp -d "$PROJECT_DIR/dist/.dmg-build.XXXXXX")"
MOUNT_DIR="$WORK_DIR/mount"
cleanup() {
  if mount | grep -Fq " on $MOUNT_DIR "; then hdiutil detach "$MOUNT_DIR" -quiet || true; fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT
mkdir -p "$WORK_DIR/content"
ditto "$APP_DIR" "$WORK_DIR/content/Claude Codex Timer.app"
ln -s /Applications "$WORK_DIR/content/Applications"
if [[ "$LAYOUT" == true ]]; then
  mkdir -p "$WORK_DIR/content/.background"
  swift scripts/dmg-background.swift "$WORK_DIR/content/.background/background.png"
fi
hdiutil create -volname "Claude Codex Timer" -srcfolder "$WORK_DIR/content" -fs HFS+ -format UDRW "$WORK_DIR/writable.dmg" -quiet
if [[ "$LAYOUT" == true ]]; then
  mkdir -p "$MOUNT_DIR"
  hdiutil attach "$WORK_DIR/writable.dmg" -mountpoint "$MOUNT_DIR" -nobrowse -quiet
  osascript scripts/dmg-layout.applescript "$MOUNT_DIR"
  hdiutil detach "$MOUNT_DIR" -quiet
fi
hdiutil convert "$WORK_DIR/writable.dmg" -format UDZO -imagekey zlib-level=9 -o "$WORK_DIR/ClaudeCodexTimer.dmg" -quiet
hdiutil verify "$WORK_DIR/ClaudeCodexTimer.dmg"
mv -f "$WORK_DIR/ClaudeCodexTimer.dmg" "$PROJECT_DIR/dist/ClaudeCodexTimer.dmg"
cd "$PROJECT_DIR/dist"
shasum -a 256 ClaudeCodexTimer.dmg > ClaudeCodexTimer.dmg.sha256
echo "Built: $PROJECT_DIR/dist/ClaudeCodexTimer.dmg"
echo "Checksum: $PROJECT_DIR/dist/ClaudeCodexTimer.dmg.sha256"
