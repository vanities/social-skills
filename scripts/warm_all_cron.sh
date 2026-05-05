#!/usr/bin/env bash
# Cron entry: fire /warm-all in headless Claude Code.
# Picks the most-stale eligible platform per invocation; designed to be
# called 2-3 times per day at staggered minutes (see crontab).

set -euo pipefail

LOG_DIR="${HOME}/.social-agents/logs/cron"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/warm-$(date +%Y-%m-%d).log"
exec >> "$LOG_FILE" 2>&1
echo "=== $(date -u +%Y-%m-%dT%H:%M:%SZ) warm cron start ==="

# macOS cron has a stripped PATH; restore the usual locations.
export PATH="$HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"

cd "$(dirname "$0")/.."
# --dangerously-skip-permissions: cron can't prompt; the skill is read-only
# from a permissions standpoint (browser navigation + JSON state file writes
# under ~/.social-agents/state/) and has been live-tested manually.
claude --print --dangerously-skip-permissions "/warm-all"

echo "=== $(date -u +%Y-%m-%dT%H:%M:%SZ) warm cron complete ==="
