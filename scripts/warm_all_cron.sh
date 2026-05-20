#!/usr/bin/env bash
# Cron entry: fire /warm-all in headless Claude Code.
# Picks the most-stale eligible platform per invocation; designed to be
# called 2-3 times per day at staggered minutes (see crontab).

set -euo pipefail

LOG_DIR="${HOME}/.social-skills/logs/cron"
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

# Read SOCIAL_SKILLS_CHROME_PROFILE + CLAUDE_CODE_OAUTH_TOKEN from .env
# (single-var greps — never `source`, see AGENTS.md re: passwords with $).
if [[ -f .env ]]; then
  PROFILE="$(grep -m1 '^SOCIAL_SKILLS_CHROME_PROFILE=' .env | cut -d= -f2-)"
  TOKEN="$(grep -m1 '^CLAUDE_CODE_OAUTH_TOKEN=' .env | cut -d= -f2-)"
  [[ -n "$TOKEN" ]] && export CLAUDE_CODE_OAUTH_TOKEN="$TOKEN"
fi
PROFILE="${PROFILE:-$HOME/.social-skills/chrome-profile}"
PROFILE="${PROFILE/#\~/$HOME}"

launch_browser_once() {
  local reason="$1"
  echo "$(date -u +%H:%M:%SZ) launching browser — $reason"
  bash scripts/launch_browser.sh
  sleep 2
}

# Probe Chrome's tab list via plain HTTP. NEVER use agent-browser for any guard
# step — agent-browser's `tab list` auto-spawns a fresh Chrome when its CDP
# WebSocket can't connect, which kills the user's session. Plain HTTP to
# /json/list is read-only and can't trigger any spawn. A noon cron once tripped
# this exact hazard: HTTP /json/version succeeded (Chrome was healthy enough to
# respond to HTTP) but agent-browser tab list still respawned Chrome because its
# CDP WebSocket attempt failed independently. User had to click "Restore" to
# recover their tabs.
# Timeout was -m 3 originally; bumped to -m 8 with a single retry after a later
# 6:22 PM CDT skip — Chrome was busy and curl's 3s read returned a body with no
# platform URLs in it, even though the tabs were pinned and present.
probe_tabs() {
  PORT=$(head -1 "$PROFILE/DevToolsActivePort" 2>/dev/null || true)
  DAEMON_PID=$(pgrep -f 'agent-browser-darwin' | head -1 || true)
  if [[ -z "$PORT" || -z "$DAEMON_PID" ]]; then
    return 0
  fi
  curl -sS -m 8 "http://127.0.0.1:${PORT}/json/list" 2>/dev/null || true
}
TAB_JSON=$(probe_tabs)
if [ -z "$TAB_JSON" ]; then
  launch_browser_once "DevToolsActivePort, daemon, or HTTP /json/list was unavailable (profile=$PROFILE, port=${PORT:-?}, pid=${DAEMON_PID:-?})"
  TAB_JSON=$(probe_tabs)
fi
if [ -z "$TAB_JSON" ] || ! echo "$TAB_JSON" | grep -qE 'instagram\.com|x\.com|pinterest\.com|linkedin\.com'; then
  echo "$(date -u +%H:%M:%SZ) probe miss — retrying in 2s"
  sleep 2
  TAB_JSON=$(probe_tabs)
fi

if [ -z "$TAB_JSON" ]; then
  echo "$(date -u +%H:%M:%SZ) skipped — Chrome at port ${PORT:-?} is unreachable after launch attempt (HTTP /json/list returned nothing after retry)"
  exit 0
fi

# Verify it's OUR Chrome (has at least one platform tab) before invoking any
# agent-browser command. If the tab list shows only about:blank / chrome://newtab,
# this is probably a fresh Chrome agent-browser spawned earlier — don't fire
# a warm pass against it (it has no logged-in sessions either).
if ! echo "$TAB_JSON" | grep -qE 'instagram\.com|x\.com|pinterest\.com|linkedin\.com'; then
  echo "$(date -u +%H:%M:%SZ) skipped — Chrome alive on port $PORT but no platform tabs after retry (possibly fresh/wrong Chrome)"
  echo "tab snapshot: $(echo "$TAB_JSON" | grep -oE '\"url\":\s*\"[^\"]*\"' | head -5 | tr '\n' ' ')"
  exit 0
fi
# Snapshot the current tab set so we can clean up anything the skill spawns.
# Default `keep_tabs_open=false` in config/brand.json; close_spawned_tabs.sh
# no-ops when the flag is true. Platform tabs (essential_tabs) and
# browser-internal URLs are always skipped by the closer.
TAB_BASELINE="${HOME}/.social-skills/state/tab-baseline-warm-$$.json"
bash scripts/tab_baseline_save.sh "$TAB_BASELINE"

# --dangerously-skip-permissions: cron can't prompt; the skill is read-only
# from a permissions standpoint (browser navigation + JSON state file writes
# under ~/.social-skills/state/) and has been live-tested manually.
claude --print --dangerously-skip-permissions "/warm-all"

bash scripts/close_spawned_tabs.sh "$TAB_BASELINE"
rm -f "$TAB_BASELINE"

echo "=== $(date -u +%Y-%m-%dT%H:%M:%SZ) warm cron complete ==="
