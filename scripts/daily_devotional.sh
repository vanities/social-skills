#!/usr/bin/env bash
# Cron entry: fire the /post-daily-devotional skill via headless Claude Code.

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
# (single-var greps — never `source`, see CLAUDE.md re: passwords with $).
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
# /json/list is read-only and can't trigger any spawn. 2026-05-06 noon devotional
# tripped this exact hazard: HTTP succeeded (Chrome was healthy enough to
# respond to HTTP) but agent-browser tab list respawned Chrome anyway. User
# had to click Restore to recover tabs. /json/list returns the full tab list,
# which doubles as our "is this our Chrome" check.
TAB_JSON=$(curl -sS -m 3 "http://127.0.0.1:${PORT}/json/list" 2>/dev/null || true)
if [ -z "$TAB_JSON" ]; then
  echo "$(date -u +%H:%M:%SZ) skipped — Chrome at port $PORT is unreachable (HTTP /json/list returned nothing; refusing to auto-spawn a fresh browser)"
  exit 0
fi

if ! echo "$TAB_JSON" | grep -qE 'instagram\.com|x\.com|pinterest\.com|linkedin\.com'; then
  echo "$(date -u +%H:%M:%SZ) skipped — Chrome alive on port $PORT but no platform tabs (possibly fresh/wrong Chrome)"
  echo "tab snapshot: $(echo "$TAB_JSON" | grep -oE '\"url\":\"[^\"]*\"' | head -5 | tr '\n' ' ')"
  exit 0
fi

# Boot the iOS simulator if none is booted. The skill needs a foregrounded
# Swift Bible app to capture today's devotional. 2026-05-08 noon cron failed
# silently because the wrapper didn't do this — the skill aborted at "no
# booted simulator" and produced no log output.
if ! xcrun simctl list devices 2>/dev/null | grep -q '(Booted)'; then
  # Try the iPhone 17 Pro UDID we've used historically; fall back to whatever
  # iPhone 17 family device is available.
  SIM_UDID="${SOCIAL_SKILLS_SIM_UDID:-1D488BFC-505C-4A5E-BF6C-0A390AEDB8C9}"
  if ! xcrun simctl boot "$SIM_UDID" 2>/dev/null; then
    SIM_UDID=$(xcrun simctl list devices available 2>/dev/null | grep -E '^\s+iPhone 17( Pro)? \(' | head -1 | grep -oE '\([A-F0-9-]{36}\)' | tr -d '()')
    if [ -z "$SIM_UDID" ] || ! xcrun simctl boot "$SIM_UDID" 2>/dev/null; then
      echo "$(date -u +%H:%M:%SZ) skipped — no iPhone 17 simulator could be booted"
      exit 0
    fi
  fi
  echo "$(date -u +%H:%M:%SZ) booted simulator $SIM_UDID"
  open -a Simulator
  sleep 6   # let SpringBoard finish coming up before the skill's launch call
fi

# --dangerously-skip-permissions: cron can't prompt. The skill launches the
# Swift Bible app, navigates to the Devotional tab, captures a screenshot,
# drafts captions, and posts to IG/X/Pinterest — all operations validated
# manually beforehand.
claude --print --dangerously-skip-permissions "/post-daily-devotional"

echo "=== $(date -u +%Y-%m-%dT%H:%M:%SZ) cron complete ==="
