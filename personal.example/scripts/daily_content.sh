#!/usr/bin/env bash
# Cron entry: fire your daily-content skill via headless Claude Code.
#
# This is a TEMPLATE — copy to scripts/daily_content.sh (gitignored), make
# executable, and add to your crontab. The skill name on the last line should
# match the personal composite skill you've installed at skills/<name>/
# (.claude/skills symlinks there for Claude Code).
#
# Usage in crontab (e.g. noon local):
#   0 12 * * * /bin/bash /absolute/path/to/social-skills/scripts/daily_content.sh

set -euo pipefail

# --- log redirection (shell-level errors before Claude starts) ---
LOG_DIR="${HOME}/.social-skills/logs/cron"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/$(date +%Y-%m-%d).log"
exec >> "$LOG_FILE" 2>&1
echo "=== $(date -u +%Y-%m-%dT%H:%M:%SZ) cron start ==="

# cron on macOS has a stripped PATH; restore the usual locations PLUS the
# path where `agent-browser` actually lives (~/.vite-plus/bin). Without
# ~/.vite-plus/bin the wrapper skips with "command not found".
export PATH="$HOME/.vite-plus/bin:$HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"

cd "$(dirname "$0")/.."

# Read SOCIAL_SKILLS_CHROME_PROFILE + CLAUDE_CODE_OAUTH_TOKEN from .env
# (single-var greps — never `source`, see AGENTS.md re: passwords with $).
if [[ -f .env ]]; then
  PROFILE="$(grep -m1 '^SOCIAL_SKILLS_CHROME_PROFILE=' .env | cut -d= -f2-)"
  TOKEN="$(grep -m1 '^CLAUDE_CODE_OAUTH_TOKEN=' .env | cut -d= -f2-)"
  [[ -n "$TOKEN" ]] && export CLAUDE_CODE_OAUTH_TOKEN="$TOKEN"
fi
PROFILE="${PROFILE:-$HOME/.social-skills/chrome-profile}"
PROFILE="${PROFILE/#\~/$HOME}"

# Strict guard: skip cleanly unless (a) Chrome is alive with OUR profile,
# (b) the agent-browser daemon is running, and (c) the daemon is attached
# to Chrome (or can re-attach without spawning a fresh browser).
PORT=$(head -1 "$PROFILE/DevToolsActivePort" 2>/dev/null || true)
DAEMON_PID=$(pgrep -f 'agent-browser-darwin' | head -1 || true)
if [[ -z "$PORT" || -z "$DAEMON_PID" ]]; then
  echo "$(date -u +%H:%M:%SZ) skipped — DevToolsActivePort or daemon missing (profile=$PROFILE, port=${PORT:-?}, pid=${DAEMON_PID:-?})"
  exit 0
fi

# Probe Chrome's tab list via plain HTTP. NEVER use agent-browser for any guard
# step — agent-browser's `tab list` auto-spawns a fresh Chrome when its CDP
# WebSocket can't connect, which kills the user's session. Plain HTTP to
# /json/list is read-only and can't trigger any spawn.
TAB_JSON=$(curl -sS -m 8 "http://127.0.0.1:${PORT}/json/list" 2>/dev/null || true)
if [ -z "$TAB_JSON" ]; then
  echo "$(date -u +%H:%M:%SZ) skipped — Chrome at port $PORT is unreachable"
  exit 0
fi

if ! echo "$TAB_JSON" | grep -qE 'instagram\.com|x\.com|pinterest\.com|linkedin\.com'; then
  echo "$(date -u +%H:%M:%SZ) skipped — Chrome alive on port $PORT but no platform tabs"
  exit 0
fi

# Boot the iOS simulator if your composite skill needs one (delete this block
# if your daily-content flow doesn't drive an iOS app). Set SOCIAL_SKILLS_SIM_UDID
# in .env to pin a specific device; otherwise the wrapper falls back to the first
# available iPhone 17.
if ! xcrun simctl list devices 2>/dev/null | grep -q '(Booted)'; then
  SIM_UDID="${SOCIAL_SKILLS_SIM_UDID:-}"
  if [ -n "$SIM_UDID" ] && xcrun simctl boot "$SIM_UDID" 2>/dev/null; then
    :
  else
    SIM_UDID=$(xcrun simctl list devices available 2>/dev/null | grep -E '^\s+iPhone 17( Pro)? \(' | head -1 | grep -oE '\([A-F0-9-]{36}\)' | tr -d '()')
    if [ -z "$SIM_UDID" ] || ! xcrun simctl boot "$SIM_UDID" 2>/dev/null; then
      echo "$(date -u +%H:%M:%SZ) skipped — no iPhone 17 simulator could be booted"
      exit 0
    fi
  fi
  echo "$(date -u +%H:%M:%SZ) booted simulator $SIM_UDID"
  open -a Simulator
  sleep 6
fi

# Snapshot the current tab set so we can clean up anything the skill spawns.
# Default `keep_tabs_open=false` in config/brand.json; close_spawned_tabs.sh
# no-ops when the flag is true. Platform tabs (essential_tabs) and
# browser-internal URLs are always skipped by the closer.
TAB_BASELINE="${HOME}/.social-skills/state/tab-baseline-daily-$$.json"
bash scripts/tab_baseline_save.sh "$TAB_BASELINE"

# --dangerously-skip-permissions: cron can't prompt for tool approvals.
# Replace /post-daily-content with whatever skill name you installed at
# skills/<name>/SKILL.md.
claude --print --dangerously-skip-permissions "/post-daily-content"

bash scripts/close_spawned_tabs.sh "$TAB_BASELINE"
rm -f "$TAB_BASELINE"

echo "=== $(date -u +%Y-%m-%dT%H:%M:%SZ) cron complete ==="
