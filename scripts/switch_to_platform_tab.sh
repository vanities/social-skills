#!/usr/bin/env bash
# switch_to_platform_tab.sh
#
# Switches Chrome to the tab matching <host> WITHOUT ever creating a duplicate.
# Invariant: `agent-browser tab new` fires ONLY when a fresh curl of Chrome's
# /json/list confirms NO tab on <host> exists. Everything else resolves to a
# switch into the already-open tab.
#
#   1. find_platform_tab.sh — curl /json/list to locate the tab index (read-only
#      HTTP; never spawns Chrome).
#   2. `agent-browser tab <index>` + `get url` verify, retried — agent-browser's
#      focus transfer is flaky under load, but the tab IS there (curl proved it),
#      so we retry the switch rather than spawn a second tab.
#   3. Only if curl shows the host has NO tab do we `agent-browser tab new`.
#
# Why this shape: the helper used to open a new tab on the FIRST failed verify,
# so the documented focus-transfer flake ("tab <N> prints info but doesn't
# transfer focus") spawned a duplicate every time it hit. Cron runs this many
# times a day, so duplicate platform tabs piled up. Gating `tab new` on a fresh
# curl check makes spawning impossible while a real tab exists.
#
# Usage: bash scripts/switch_to_platform_tab.sh <host-substring> <full-url>
# Example: bash scripts/switch_to_platform_tab.sh "instagram.com" "https://www.instagram.com/"
#
# stderr is informational; stdout is unused (the switch IS the side effect).
# Exits 0 on success or best-effort; exits 1 only when Chrome is unreachable.

set -euo pipefail

HOST="${1:?usage: $0 <host-substring> <full-url>}"
FULL_URL="${2:?usage: $0 <host-substring> <full-url>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Curl-based tab lookup. Echoes the agent-browser tab index, or empty.
find_tab() { bash "$SCRIPT_DIR/find_platform_tab.sh" "$HOST" 2>/dev/null || true; }

# Echo the current tab URL on stdout and return 0 iff it's on HOST.
verify_host() {
  local url
  url=$(agent-browser get url 2>&1 | tail -1)
  echo "$url"
  echo "$url" | grep -q "$HOST"
}

# --- A matching tab already exists: switch into it, never spawn -------------
TAB_INDEX=$(find_tab)
if [ -n "$TAB_INDEX" ]; then
  for attempt in 1 2 3 4; do
    agent-browser tab "$TAB_INDEX" >/dev/null 2>&1
    sleep 1
    if CUR_URL=$(verify_host); then
      echo "switch_to_platform_tab: switched to existing tab $TAB_INDEX ($CUR_URL) on attempt $attempt" >&2
      exit 0
    fi
    # Index can drift if the tab set changed between calls — re-query.
    TAB_INDEX=$(find_tab)
    [ -z "$TAB_INDEX" ] && break   # tab vanished mid-loop; fall through to open
  done
  # Couldn't verify the switch. If curl STILL sees the tab, do NOT open a
  # duplicate — a duplicate is exactly what we're trying to prevent. Hand back
  # to the caller, which re-verifies (snapshot / get url) before acting.
  if [ -n "$(find_tab)" ]; then
    echo "switch_to_platform_tab: $HOST tab exists but agent-browser focus didn't verify after retries; NOT opening a duplicate — caller MUST re-verify before acting" >&2
    exit 0
  fi
fi

# --- No tab on this host: open one ------------------------------------------
agent-browser tab new "$FULL_URL" >/dev/null 2>&1
for retry in 1 2 3 4 5; do
  sleep 1
  if CUR_URL=$(verify_host); then
    echo "switch_to_platform_tab: opened new tab at $FULL_URL (verified after ${retry}s)" >&2
    exit 0
  fi
done

# New tab IS in Chrome (curl will see it) but agent-browser focus didn't
# transfer — re-query the index and force-switch by it.
TAB_INDEX=$(find_tab)
if [ -n "$TAB_INDEX" ]; then
  agent-browser tab "$TAB_INDEX" >/dev/null 2>&1
  sleep 1
  if CUR_URL=$(verify_host); then
    echo "switch_to_platform_tab: opened + force-switched to tab $TAB_INDEX ($CUR_URL)" >&2
    exit 0
  fi
fi

echo "switch_to_platform_tab: opened tab but agent-browser focus didn't transfer to $HOST (last get-url: ${CUR_URL:-none}); caller MUST re-verify before acting" >&2
exit 0
