#!/usr/bin/env bash
# switch_to_platform_tab.sh
#
# Switches Chrome to the tab matching <host> WITHOUT ever creating a duplicate
# AND WITHOUT ever cycling through tabs. Two invariants:
#   * `agent-browser tab new` fires ONLY when a fresh curl of /json/list shows
#     NO tab on <host> exists.
#   * We NEVER loop `agent-browser tab 0..N` to hunt for a tab. Each such call
#     activates (raises) a tab, so a hunt-loop drags Chrome to the foreground on
#     every iteration — that is what made the 2026-05-20 13:43 warm run yank the
#     user's window over and over. Callers must honor this too (see below).
#
# Strategy:
#   1. find_platform_tab.sh <host> id — curl /json/list for the tab's STABLE
#      target id (read-only HTTP; never spawns Chrome; never activates a tab).
#   2. Activate exactly that tab via `curl /json/activate/<id>`. The id never
#      drifts, unlike the page-array index, which Chrome reorders by recency.
#   3. Verify with `agent-browser get url`. If the daemon's current page didn't
#      follow the curl-activate, force it once with `agent-browser tab <index>`
#      (fresh index) and re-verify. Bounded — a handful of activations at most,
#      never a 0..N sweep.
#   4. Only if curl shows NO tab on <host> do we `agent-browser tab new`.
#
# If the switch can't be verified but curl still sees the tab, we hand back to
# the caller with a do-NOT-cycle message. The caller MUST re-verify with
# `agent-browser get url` before acting and MUST NOT improvise a tab sweep —
# for a warm pass, skip the platform; for a post, abort it.
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

PROFILE="${SOCIAL_SKILLS_CHROME_PROFILE:-$HOME/.social-skills/chrome-profile}"
PROFILE="${PROFILE/#\~/$HOME}"
PORT=$(head -1 "$PROFILE/DevToolsActivePort" 2>/dev/null || echo "")
if [ -z "$PORT" ]; then
  echo "switch_to_platform_tab: no DevToolsActivePort (is Chrome running?)" >&2
  exit 1
fi

find_id()     { bash "$SCRIPT_DIR/find_platform_tab.sh" "$HOST" id    2>/dev/null || true; }
find_index()  { bash "$SCRIPT_DIR/find_platform_tab.sh" "$HOST" index 2>/dev/null || true; }
activate_id() { curl -sS -m 3 "http://127.0.0.1:${PORT}/json/activate/$1" >/dev/null 2>&1 || true; }

# Echo the current tab URL on stdout; return 0 iff it's on HOST.
verify_host() {
  local url
  url=$(agent-browser get url 2>&1 | tail -1)
  echo "$url"
  echo "$url" | grep -q "$HOST"
}

# Force agent-browser's current-page pointer onto the matched tab, then verify.
# The tab-switch arg differs by agent-browser version:
#   * <=0.25 : `tab <index>`  — bare positional index
#   * >=0.26 : `tab t<N>`     — stable per-session id (1-based); bare int rejected
# We can't read the daemon's t<N> for a given URL without `tab list`, which is
# banned (its CDP attach can silently respawn Chrome — see AGENTS.md). So we try
# the plausible refs in order and let verify_host() guard each: landing on a
# non-HOST tab just fails that attempt, never a false success. Bounded (3 tries),
# never a 0..N sweep. find_index is 0-based, so the >=0.26 id is index+1.
force_via_index() {
  local idx ref
  idx=$(find_index)
  [ -z "$idx" ] && return 1
  for ref in "t$((idx + 1))" "$idx" "t$idx"; do
    agent-browser tab "$ref" >/dev/null 2>&1
    sleep 1
    if CUR_URL=$(verify_host); then
      echo "switch_to_platform_tab: switched via tab ref '$ref' ($CUR_URL)" >&2
      return 0
    fi
  done
  return 1
}

# --- A matching tab already exists: activate it by id, never spawn/sweep -----
TID=$(find_id)
if [ -n "$TID" ]; then
  # Each pass = 1 curl-activate of the correct (stable-id) tab, plus at most one
  # index-forced activation. Bounded at 3 passes; never a 0..N sweep.
  for attempt in 1 2 3; do
    activate_id "$TID"
    sleep 1
    if CUR_URL=$(verify_host); then
      echo "switch_to_platform_tab: activated $HOST tab by id $TID ($CUR_URL) on attempt $attempt" >&2
      exit 0
    fi
    # Daemon's current page didn't follow the curl-activate — force it by index.
    if force_via_index; then exit 0; fi
    TID=$(find_id)
    [ -z "$TID" ] && break   # tab vanished mid-loop; fall through to open
  done
  # Unverified but the tab still exists per curl: do NOT spawn a duplicate and
  # do NOT cycle. Hand back to the caller.
  if [ -n "$(find_id)" ]; then
    echo "switch_to_platform_tab: $HOST tab exists but the switch didn't verify; NOT opening a duplicate and NOT cycling tabs. Caller MUST re-verify (agent-browser get url) before acting and MUST NOT loop 'agent-browser tab 0..N' — skip the platform (warm) or abort it (post)." >&2
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

# New tab IS in Chrome but the daemon didn't follow — activate by fresh id, then
# (if needed) force by index. Still no sweep.
TID=$(find_id)
if [ -n "$TID" ]; then
  activate_id "$TID"
  sleep 1
  if CUR_URL=$(verify_host); then
    echo "switch_to_platform_tab: opened + activated new $HOST tab by id $TID ($CUR_URL)" >&2
    exit 0
  fi
  if force_via_index; then exit 0; fi
fi

echo "switch_to_platform_tab: opened tab but the switch didn't verify for $HOST (last get-url: ${CUR_URL:-none}); caller MUST re-verify before acting and MUST NOT cycle tabs" >&2
exit 0
