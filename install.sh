#!/bin/bash
# Build and install the app and enable the daily schedule (default 07:00).
set -euo pipefail
if [[ $# -gt 1 ]]; then echo "Usage: ./install.sh [HH:MM]" >&2; exit 2; fi
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
"$PROJECT_DIR/scripts/build-app.sh"
mkdir -p "$HOME/Applications"
if [[ -d "$HOME/Applications/Claude Timer.app" && ! -e "$HOME/Applications/Claude Codex Timer.app" ]]; then
  if [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$HOME/Applications/Claude Timer.app/Contents/Info.plist" 2>/dev/null)" == "io.claude-timer.app" ]]; then
    mv "$HOME/Applications/Claude Timer.app" "$HOME/Applications/Claude Codex Timer.app"
  fi
fi
ditto "$PROJECT_DIR/dist/Claude Codex Timer.app" "$HOME/Applications/Claude Codex Timer.app"
"$HOME/Applications/Claude Codex Timer.app/Contents/Helpers/claude-timer-runner" enable "$@"
echo "Open: $HOME/Applications/Claude Codex Timer.app"
