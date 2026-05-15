#!/usr/bin/env bash
# switch_to_platform_tab.sh
#
# Switches Chrome to the tab matching <host>. Combines:
#   1. find_platform_tab.sh — curl /json/list to identify the tab index
#   2. `agent-browser tab <index>` — switch
#   3. `agent-browser get url` — VERIFY we landed on the right tab
#   4. Fallback: `agent-browser tab new <full-url>` if the index was wrong
#
# The fallback exists because `/json/list` returns tabs in MRU-ish order while
# agent-browser's `tab <N>` uses tab-bar position — those orderings can drift
# (caught 2026-05-06 IG warm: helper said index 1, agent-browser had IG at 0).
#
# Usage: bash scripts/switch_to_platform_tab.sh <host-substring> <full-url>
# Example: bash scripts/switch_to_platform_tab.sh "instagram.com" "https://www.instagram.com/"
#
# stderr is informational; stdout is unused (the switch IS the side effect).
# Exits 0 on success (either branch). Exits 1 only on truly unrecoverable
# state (no Chrome).

set -euo pipefail

HOST="${1:?usage: $0 <host-substring> <full-url>}"
FULL_URL="${2:?usage: $0 <host-substring> <full-url>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

TAB_INDEX=$(bash "$SCRIPT_DIR/find_platform_tab.sh" "$HOST" 2>/dev/null || true)

if [ -n "$TAB_INDEX" ]; then
  agent-browser tab "$TAB_INDEX" >/dev/null 2>&1
  sleep 1   # focus transfer isn't instant
  CUR_URL=$(agent-browser get url 2>&1 | tail -1)
  if echo "$CUR_URL" | grep -q "$HOST"; then
    echo "switch_to_platform_tab: switched to tab $TAB_INDEX ($CUR_URL)" >&2
    exit 0
  fi
  echo "switch_to_platform_tab: tab $TAB_INDEX wasn't the $HOST tab (got $CUR_URL); opening new" >&2
fi

# Fallback: open a new tab. Then VERIFY agent-browser's focus actually
# transferred — caught 2026-05-15: the helper printed "opened new tab" but
# `agent-browser get url` still returned the previous tab's URL (about:blank
# or an unrelated tab). Without the post-fallback verify, callers proceed
# against the wrong page and downstream snapshots return stale refs.
agent-browser tab new "$FULL_URL" >/dev/null 2>&1
for retry in 1 2 3 4 5; do
  sleep 1
  CUR_URL=$(agent-browser get url 2>&1 | tail -1)
  if echo "$CUR_URL" | grep -q "$HOST"; then
    echo "switch_to_platform_tab: opened new tab at $FULL_URL (verified after ${retry}s)" >&2
    exit 0
  fi
done

# Last resort: the new tab IS in Chrome (curl /json/list will see it) but
# agent-browser's CDP attach didn't transfer focus. Re-query for the index
# and force-switch by it.
TAB_INDEX=$(bash "$SCRIPT_DIR/find_platform_tab.sh" "$HOST" 2>/dev/null || true)
if [ -n "$TAB_INDEX" ]; then
  agent-browser tab "$TAB_INDEX" >/dev/null 2>&1
  sleep 1
  CUR_URL=$(agent-browser get url 2>&1 | tail -1)
  if echo "$CUR_URL" | grep -q "$HOST"; then
    echo "switch_to_platform_tab: opened + force-switched to tab $TAB_INDEX ($CUR_URL)" >&2
    exit 0
  fi
fi

echo "switch_to_platform_tab: opened tab but agent-browser focus didn't transfer to $HOST (last get-url: $CUR_URL); caller MUST re-verify before acting" >&2
exit 0
