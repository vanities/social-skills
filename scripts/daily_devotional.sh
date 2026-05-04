#!/usr/bin/env bash
# Cron entry: fire the /post-daily-devotional skill via headless Claude Code.

set -euo pipefail

# --- log redirection (shell-level errors before Claude starts) ---
LOG_DIR="${HOME}/.social-agents/logs/cron"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/$(date +%Y-%m-%d).log"
exec >> "$LOG_FILE" 2>&1
echo "=== $(date -u +%Y-%m-%dT%H:%M:%SZ) cron start ==="

# cron on macOS has a stripped PATH; restore the usual locations.
export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"

# Run the skill in headless Claude Code (uses the user's existing OAuth auth).
# --dangerously-skip-permissions: cron can't prompt. The skill captures a
# screenshot, pads it, drafts captions, and posts to IG/X/Pinterest — all
# operations have been validated manually beforehand.
cd "$(dirname "$0")/.."
claude --print --dangerously-skip-permissions "/post-daily-devotional"

echo "=== $(date -u +%Y-%m-%dT%H:%M:%SZ) cron complete ==="
