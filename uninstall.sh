#!/bin/bash
# Disable scheduling. Keep the app, settings, history, and Claude sessions.
set -euo pipefail
if [[ $# -ne 0 ]]; then echo "Usage: ./uninstall.sh" >&2; exit 2; fi
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
for RUNNER in \
  "$HOME/Library/Application Support/ClaudeTimer/bin/claude-timer-runner" \
  "$PROJECT_DIR/dist/Claude Codex Timer.app/Contents/Helpers/claude-timer-runner"; do
  if [[ -x "$RUNNER" ]]; then exec "$RUNNER" disable; fi
done
# Also supports uninstalling the original scripts before building the app.
for LABEL in io.claude-timer.daily com.juan.claude-morning-timer; do
  if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
    launchctl bootout "gui/$(id -u)/$LABEL"
  fi
  rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
done
echo "Daily schedule disabled. Local data kept."
