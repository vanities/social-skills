#!/usr/bin/env bash
# find_platform_tab.sh
#
# Finds the index of a Chrome tab whose URL contains the given substring,
# using ONLY plain HTTP — never `agent-browser`. agent-browser's CDP attach
# can fail and silently respawn Chrome (killing the user's session) even
# when Chrome's HTTP endpoints are responding cleanly. Hit this 3 times
# across 2026-05-05 → 2026-05-06 before this helper was written.
#
# Usage: bash scripts/find_platform_tab.sh <url-substring>
# Echoes the agent-browser tab index on stdout. Empty + exit 1 if no match.
#
# Tab numbering: agent-browser's `tab <N>` indexing matches the array order
# of `type=page` entries in Chrome's /json/list response (verified by user
# observation 2026-05-06).
#
# IMPORTANT CAVEAT: this helper eliminates the GRATUITOUS `agent-browser tab
# list` probe but does NOT eliminate first-call spawn risk entirely. The
# subsequent `agent-browser tab <N>` call (which is the actual work) can
# still respawn-on-CDP-fail. We're reducing risk from 2 spawn-chances per
# skill to 1.

set -euo pipefail

NEEDLE="${1:?usage: $0 <url-substring>}"
PROFILE="${SOCIAL_AGENTS_CHROME_PROFILE:-$HOME/.social-agents/chrome-profile}"
PROFILE="${PROFILE/#\~/$HOME}"

PORT=$(head -1 "$PROFILE/DevToolsActivePort" 2>/dev/null || echo "")
if [ -z "$PORT" ]; then
  echo "find_platform_tab: no DevToolsActivePort" >&2
  exit 1
fi

TAB_JSON=$(curl -sS -m 3 "http://127.0.0.1:${PORT}/json/list" 2>/dev/null || echo "")
if [ -z "$TAB_JSON" ]; then
  echo "find_platform_tab: Chrome unreachable on port $PORT" >&2
  exit 1
fi

INDEX=$(echo "$TAB_JSON" | python3 -c "
import sys, json
needle = sys.argv[1]
data = json.load(sys.stdin)
pages = [t for t in data if t.get('type') == 'page']
for i, t in enumerate(pages):
    if needle in t.get('url', ''):
        print(i)
        sys.exit(0)
sys.exit(1)
" "$NEEDLE" 2>/dev/null) || true

if [ -z "$INDEX" ]; then
  echo "find_platform_tab: no tab matching '$NEEDLE'" >&2
  exit 1
fi
echo "$INDEX"
