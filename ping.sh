#!/bin/bash
# Send one ping to each selected provider, or use --provider claude|codex.
set -euo pipefail
if [[ "${1:-}" == "--test" ]]; then shift; fi
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
for RUNNER in \
  "$PROJECT_DIR/dist/Claude Codex Timer.app/Contents/Helpers/claude-codex-timer-runner" \
  "$HOME/Library/Application Support/ClaudeTimer/bin/claude-timer-runner" \
  "$PROJECT_DIR/dist/Claude Codex Timer.app/Contents/Helpers/claude-timer-runner"; do
  if [[ -x "$RUNNER" ]]; then exec "$RUNNER" run "$@"; fi
done
echo "Build the app first: ./scripts/build-app.sh" >&2
exit 1
