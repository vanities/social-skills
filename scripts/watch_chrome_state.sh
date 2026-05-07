#!/usr/bin/env bash
# watch_chrome_state.sh — log Chrome + agent-browser daemon state every 1s
#
# Diagnostic-only. Run this in a background terminal/process and observe
# the log to see exactly when Chrome's PID changes (= respawn) and what
# the agent-browser daemon was doing at that moment.
#
# Usage: bash scripts/watch_chrome_state.sh [interval_sec]
#   default interval 1s

set -uo pipefail

INTERVAL="${1:-1}"
PROFILE="${SOCIAL_AGENTS_CHROME_PROFILE:-$HOME/.social-agents/chrome-profile}"
PROFILE="${PROFILE/#\~/$HOME}"
LOG_DIR="${HOME}/.social-agents/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/chrome-watch-$(date +%Y%m%d-%H%M%S).log"

echo "watch_chrome_state: profile=$PROFILE interval=${INTERVAL}s log=$LOG" >&2
echo "ts_utc,chrome_pid,chrome_lstart,daemon_pid,daemon_lstart,port,ab_proc_count,event" > "$LOG"

prev_chrome_pid=""
prev_daemon_pid=""
prev_port=""

while :; do
  ts=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
  chrome_pid=$(pgrep -f "Google Chrome.*--user-data-dir=$PROFILE" 2>/dev/null | head -1)
  daemon_pid=$(pgrep -f "agent-browser-darwin" 2>/dev/null | head -1)
  port=$(head -1 "$PROFILE/DevToolsActivePort" 2>/dev/null)
  ab_count=$(pgrep -f "agent-browser" 2>/dev/null | wc -l | tr -d ' ')

  chrome_lstart=""
  daemon_lstart=""
  [ -n "$chrome_pid" ] && chrome_lstart=$(ps -o lstart= -p "$chrome_pid" 2>/dev/null | tr -s ' ' | sed 's/,/_/g')
  [ -n "$daemon_pid" ] && daemon_lstart=$(ps -o lstart= -p "$daemon_pid" 2>/dev/null | tr -s ' ' | sed 's/,/_/g')

  # Detect events
  event=""
  [ "$chrome_pid" != "$prev_chrome_pid" ] && event="${event}CHROME_PID:${prev_chrome_pid:-none}->${chrome_pid:-none};"
  [ "$daemon_pid" != "$prev_daemon_pid" ] && event="${event}DAEMON_PID:${prev_daemon_pid:-none}->${daemon_pid:-none};"
  [ "$port" != "$prev_port" ] && event="${event}PORT:${prev_port:-none}->${port:-none};"

  echo "$ts,$chrome_pid,$chrome_lstart,$daemon_pid,$daemon_lstart,$port,$ab_count,$event" >> "$LOG"

  # Also tail interesting events to stderr for live viewing
  [ -n "$event" ] && echo "$ts $event" >&2

  prev_chrome_pid="$chrome_pid"
  prev_daemon_pid="$daemon_pid"
  prev_port="$port"

  sleep "$INTERVAL"
done
