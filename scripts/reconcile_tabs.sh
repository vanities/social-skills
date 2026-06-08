#!/usr/bin/env bash
# reconcile_tabs.sh
#
# Make the set of open Chrome page-tabs equal EXACTLY the `essential_tabs` set
# from config/brand.json — one tab per essential URL:
#   - keep one tab per essential (prefer an exact-URL match, tolerate sub-paths),
#   - close every other tab that matches an essential (e.g. a 2nd Pinterest tab
#     parked on /pin-creation-tool/, an X tab left on /home),
#   - close any tab that matches NO essential,
#   - (re)open any essential that ended up with no open tab.
#
# WHY THIS EXISTS: the older close_spawned_tabs.sh keeps tabs by HOST, so
# posting leftovers that live on a platform host (Pinterest's pin-creation-tool,
# x.com/home) were treated as "platform tabs" and never pruned — they piled up
# over time. Matching by URL (with sub-path tolerance) lets us keep the real
# platform tabs — INCLUDING both X account tabs, which share the x.com host —
# while still closing same-host cruft. close_spawned_tabs.sh stays for the
# per-skill (login/post) cleanup; this is the end-of-run reconcile for crons.
#
# Honors `keep_tabs_open` in config/brand.json (true → no-op). Browser-internal
# tabs (about:/chrome:/devtools:/…) are never touched (closing one can collapse
# the window).
#
# curl-only for closing (DevTools /json/close/<id>); agent-browser ONLY to open
# a missing tab. NEVER calls `agent-browser tab list` — it can respawn Chrome on
# a CDP-attach failure (see AGENTS.md "Known issues").
#
# Usage: bash scripts/reconcile_tabs.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BRAND_CONFIG="${REPO_ROOT}/config/brand.json"
if [ ! -f "$BRAND_CONFIG" ]; then
  echo "reconcile_tabs: $BRAND_CONFIG missing — skipping" >&2
  exit 0
fi

# Guard: with no essential_tabs we'd have nothing to keep and would close every
# tab. Bail out instead.
ESSENTIAL_COUNT=$(jq -r '.essential_tabs // [] | length' "$BRAND_CONFIG" 2>/dev/null || echo 0)
if [ "$ESSENTIAL_COUNT" = "0" ]; then
  echo "reconcile_tabs: no .essential_tabs in $BRAND_CONFIG — skipping" >&2
  exit 0
fi

KEEP_OPEN=$(python3 -c "
import json, sys
try:
    cfg = json.load(open(sys.argv[1]))
except Exception:
    print('false'); sys.exit(0)
print('true' if cfg.get('keep_tabs_open') else 'false')
" "$BRAND_CONFIG")
if [ "$KEEP_OPEN" = "true" ]; then
  echo "reconcile_tabs: keep_tabs_open=true — leaving tabs alone" >&2
  exit 0
fi

PROFILE="${SOCIAL_SKILLS_CHROME_PROFILE:-$HOME/.social-skills/chrome-profile}"
PROFILE="${PROFILE/#\~/$HOME}"
PORT=$(head -1 "$PROFILE/DevToolsActivePort" 2>/dev/null || echo "")
if [ -z "$PORT" ]; then
  echo "reconcile_tabs: no DevToolsActivePort — skipping" >&2
  exit 0
fi

TAB_JSON=$(curl -sS -m 8 "http://127.0.0.1:${PORT}/json/list" 2>/dev/null || echo "")
if [ -z "$TAB_JSON" ]; then
  echo "reconcile_tabs: Chrome unreachable on port $PORT — skipping" >&2
  exit 0
fi

# One python pass decides everything. It emits, in order:
#   C\t<targetId>\t<url>   -- a tab to close
#   O\t<url>               -- an essential to (re)open
# All C lines precede all O lines, so we never close a tab we just opened.
PLAN=$(echo "$TAB_JSON" | python3 -c "
import json, sys

cfg = json.load(open(sys.argv[1]))
essentials = [u for u in cfg.get('essential_tabs', []) if u]

INTERNAL = ('about:', 'chrome:', 'chrome-extension:', 'devtools:', 'view-source:')

def norm(u):
    # drop a single trailing slash so comparisons are boundary-safe
    return u[:-1] if u.endswith('/') else u

def matches(url, ess):
    u, e = norm(url), norm(ess)
    # exact, or a sub-path/query of the essential (so x.com/swift_bible also
    # claims x.com/swift_bible/status/123, but NOT x.com/swift_bibleXYZ)
    return u == e or u.startswith(e + '/') or u.startswith(e + '?')

data = json.load(sys.stdin)
pages = [t for t in data if t.get('type') == 'page' and t.get('id')]

close = []           # list of (id, url)
kept_for = {}        # essential -> True once a tab is kept for it
claimed = set()      # tab ids already decided

# Pass 1: keep ONE tab per essential (prefer exact match), close other matches.
for ess in essentials:
    cands = [t for t in pages if t.get('url') and matches(t['url'], ess)]
    if not cands:
        continue
    cands.sort(key=lambda t: 0 if norm(t['url']) == norm(ess) else 1)
    keeper = cands[0]
    kept_for[ess] = True
    claimed.add(keeper['id'])
    for t in cands[1:]:
        if t['id'] not in claimed:
            close.append((t['id'], t['url']))
            claimed.add(t['id'])

# Pass 2: close any remaining page tab that matched no essential (but never a
# browser-internal tab — closing those can collapse the window).
for t in pages:
    tid, url = t['id'], t.get('url', '')
    if tid in claimed:
        continue
    if not url or any(url.startswith(s) for s in INTERNAL):
        continue
    close.append((tid, url))
    claimed.add(tid)

reopen = [e for e in essentials if not kept_for.get(e)]

lines = ['C\t' + tid + '\t' + url for tid, url in close]
lines += ['O\t' + url for url in reopen]
print('\n'.join(lines))
" "$BRAND_CONFIG" || true)

CLOSED=0
OPENED=0
while IFS=$'\t' read -r KIND F1 F2; do
  case "$KIND" in
    C)
      if curl -sS -m 5 "http://127.0.0.1:${PORT}/json/close/${F1}" >/dev/null 2>&1; then
        echo "reconcile_tabs: closed $F2" >&2
        CLOSED=$((CLOSED + 1))
      else
        echo "reconcile_tabs: failed to close $F2 (id=$F1)" >&2
      fi
      ;;
    O)
      if agent-browser tab new "$F1" >/dev/null 2>&1; then
        echo "reconcile_tabs: reopened missing essential $F1" >&2
        OPENED=$((OPENED + 1))
        sleep 1
      else
        echo "reconcile_tabs: failed to reopen $F1 (agent-browser unavailable?)" >&2
      fi
      ;;
  esac
done <<< "$PLAN"

echo "reconcile_tabs: closed $CLOSED, reopened $OPENED — open tabs now match the essential set" >&2
