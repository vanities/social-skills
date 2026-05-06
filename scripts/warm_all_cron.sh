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

# macOS cron has a stripped PATH; restore the usual locations PLUS the path
# where `agent-browser` actually lives (~/.vite-plus/bin — Vite Plus's per-tool
# install directory). Without this, the wrapper's `agent-browser tab list`
# probe fails with "command not found" and the run skips. Caught 2026-05-06
# 9:17 AM CDT — first cron fire after switching the guard to use tab-list.
export PATH="$HOME/.vite-plus/bin:$HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"

cd "$(dirname "$0")/.."

# Read SOCIAL_AGENTS_CHROME_PROFILE + CLAUDE_CODE_OAUTH_TOKEN from .env
# (single-var greps — never `source`, see CLAUDE.md re: passwords with $).
if [[ -f .env ]]; then
  PROFILE="$(grep -m1 '^SOCIAL_AGENTS_CHROME_PROFILE=' .env | cut -d= -f2-)"
  TOKEN="$(grep -m1 '^CLAUDE_CODE_OAUTH_TOKEN=' .env | cut -d= -f2-)"
  [[ -n "$TOKEN" ]] && export CLAUDE_CODE_OAUTH_TOKEN="$TOKEN"
fi
PROFILE="${PROFILE:-$HOME/.social-agents/chrome-profile}"
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
# /json/list is read-only and can't trigger any spawn. 2026-05-06 noon devotional
# tripped this exact hazard: HTTP /json/version succeeded (Chrome was healthy
# enough to respond to HTTP) but agent-browser tab list still respawned Chrome
# because its CDP WebSocket attempt failed independently. The user had to click
# "Restore" to recover their tabs.
TAB_JSON=$(curl -sS -m 3 "http://127.0.0.1:${PORT}/json/list" 2>/dev/null || true)
if [ -z "$TAB_JSON" ]; then
  echo "$(date -u +%H:%M:%SZ) skipped — Chrome at port $PORT is unreachable (HTTP /json/list returned nothing; refusing to auto-spawn a fresh browser)"
  exit 0
fi

# Verify it's OUR Chrome (has at least one platform tab) before invoking any
# agent-browser command. If the tab list shows only about:blank / chrome://newtab,
# this is probably a fresh Chrome agent-browser spawned earlier — don't fire
# a warm pass against it (it has no logged-in sessions either).
if ! echo "$TAB_JSON" | grep -qE 'instagram\.com|x\.com|pinterest\.com|linkedin\.com'; then
  echo "$(date -u +%H:%M:%SZ) skipped — Chrome alive on port $PORT but no platform tabs (possibly fresh/wrong Chrome)"
  echo "tab snapshot: $(echo "$TAB_JSON" | grep -oE '\"url\":\"[^\"]*\"' | head -5 | tr '\n' ' ')"
  exit 0
fi
# --dangerously-skip-permissions: cron can't prompt; the skill is read-only
# from a permissions standpoint (browser navigation + JSON state file writes
# under ~/.social-agents/state/) and has been live-tested manually.
claude --print --dangerously-skip-permissions "/warm-all"

echo "=== $(date -u +%Y-%m-%dT%H:%M:%SZ) warm cron complete ==="
