#!/usr/bin/env bash
# tab_baseline_save.sh
#
# Snapshot the IDs of every Chrome page-tab currently open and save them
# to a baseline file. Pair with `close_spawned_tabs.sh <baseline>` at the
# end of a skill run — anything not in the baseline (and not a platform
# tab) gets closed.
#
# Usage: bash scripts/tab_baseline_save.sh [output-path]
#   Default output path: ~/.social-skills/state/tab-baseline.json
#
# NEVER uses agent-browser — that command's CDP attach can respawn Chrome
# even when HTTP /json/list is fine. Curl only. See AGENTS.md for the full
# rationale.

set -euo pipefail

OUT="${1:-$HOME/.social-skills/state/tab-baseline.json}"
mkdir -p "$(dirname "$OUT")"

PROFILE="${SOCIAL_SKILLS_CHROME_PROFILE:-$HOME/.social-skills/chrome-profile}"
PROFILE="${PROFILE/#\~/$HOME}"

PORT=$(head -1 "$PROFILE/DevToolsActivePort" 2>/dev/null || echo "")
if [ -z "$PORT" ]; then
  echo "tab_baseline_save: no DevToolsActivePort at $PROFILE — writing empty baseline" >&2
  echo '[]' > "$OUT"
  exit 0
fi

TAB_JSON=$(curl -sS -m 3 "http://127.0.0.1:${PORT}/json/list" 2>/dev/null || echo "")
if [ -z "$TAB_JSON" ]; then
  echo "tab_baseline_save: Chrome unreachable on port $PORT — writing empty baseline" >&2
  echo '[]' > "$OUT"
  exit 0
fi

echo "$TAB_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
ids = [t['id'] for t in data if t.get('type') == 'page' and 'id' in t]
json.dump(ids, sys.stdout)
" > "$OUT"

echo "tab_baseline_save: $(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))))' "$OUT") tabs recorded → $OUT" >&2
