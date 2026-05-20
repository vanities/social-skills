#!/usr/bin/env bash
# find_platform_tab.sh
#
# Locates a Chrome tab whose URL contains <url-substring>, using ONLY plain
# HTTP (curl /json/list) — never `agent-browser`. agent-browser's CDP attach
# can fail and silently respawn Chrome (killing the user's session) even when
# Chrome's HTTP endpoints respond cleanly. Hit this 3x across 2026-05-05 →
# 2026-05-06 before this helper existed. curl /json/list is read-only: it can
# neither spawn Chrome nor activate (raise) a tab.
#
# Usage: bash scripts/find_platform_tab.sh <url-substring> [index|id]
#   index (default) → echoes the tab's position among type=page entries
#   id              → echoes the tab's STABLE Chrome target id
# Empty output + exit 1 if no match.
#
# Prefer `id`. The /json/list array order can drift relative to agent-browser's
# `tab <N>` index once tabs have been activated in a session (Chrome reorders by
# recency), so a position computed now may switch the WRONG tab a moment later.
# Observed live 2026-05-20: the noon devotional landed on the wrong X tab, and
# the 13:43 warm run then brute-forced `tab 0..N` to recover, yanking the user's
# Chrome window to the foreground on every step. A target id never drifts, and
# `curl /json/activate/<id>` activates exactly that tab — so switch_to_platform_tab.sh
# uses `id` as its primary path and only falls back to `index`.

set -euo pipefail

NEEDLE="${1:?usage: $0 <url-substring> [index|id]}"
FIELD="${2:-index}"
case "$FIELD" in
  index|id) ;;
  *) echo "find_platform_tab: field must be 'index' or 'id', got '$FIELD'" >&2; exit 2 ;;
esac

PROFILE="${SOCIAL_SKILLS_CHROME_PROFILE:-$HOME/.social-skills/chrome-profile}"
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

RESULT=$(echo "$TAB_JSON" | python3 -c "
import sys, json
needle, field = sys.argv[1], sys.argv[2]
data = json.load(sys.stdin)
pages = [t for t in data if t.get('type') == 'page']
for i, t in enumerate(pages):
    if needle in t.get('url', ''):
        print(t.get('id') if field == 'id' else i)
        sys.exit(0)
sys.exit(1)
" "$NEEDLE" "$FIELD" 2>/dev/null) || true

if [ -z "$RESULT" ]; then
  echo "find_platform_tab: no tab matching '$NEEDLE'" >&2
  exit 1
fi
echo "$RESULT"
