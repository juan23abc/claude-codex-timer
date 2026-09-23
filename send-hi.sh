#!/bin/bash
# Legacy entry point; use ./ping.sh for new commands and integrations.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$PROJECT_DIR/ping.sh" "$@"
