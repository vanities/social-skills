#!/usr/bin/env bash
# close_spawned_tabs.sh
#
# Compare the current tab set against a baseline (produced by
# `tab_baseline_save.sh`) and close any NEW tabs whose host isn't in
# `essential_tabs` from config/brand.json. Platform tabs are always safe;
# only incidentally-spawned tabs (post-detail views, redirect targets,
# external link previews) get cleaned up.
#
# Usage: bash scripts/close_spawned_tabs.sh [baseline-path]
#   Default baseline: ~/.social-skills/state/tab-baseline.json
#
# Honors `keep_tabs_open` in config/brand.json — if true, exits 0 without
# touching anything. Default in the example schema is `false` (= close).
#
# NEVER uses agent-browser — curl only. Closing happens via Chrome's
# DevTools HTTP endpoint `/json/close/<targetId>`.

set -euo pipefail

BASELINE="${1:-$HOME/.social-skills/state/tab-baseline.json}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BRAND_CONFIG="${REPO_ROOT}/config/brand.json"
if [ ! -f "$BRAND_CONFIG" ]; then
  echo "close_spawned_tabs: $BRAND_CONFIG missing — skipping (no config to read)" >&2
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
  echo "close_spawned_tabs: keep_tabs_open=true — leaving spawned tabs alone" >&2
  exit 0
fi

if [ ! -f "$BASELINE" ]; then
  echo "close_spawned_tabs: no baseline at $BASELINE — nothing to diff against" >&2
  exit 0
fi

PROFILE="${SOCIAL_SKILLS_CHROME_PROFILE:-$HOME/.social-skills/chrome-profile}"
PROFILE="${PROFILE/#\~/$HOME}"

PORT=$(head -1 "$PROFILE/DevToolsActivePort" 2>/dev/null || echo "")
if [ -z "$PORT" ]; then
  echo "close_spawned_tabs: no DevToolsActivePort — skipping" >&2
  exit 0
fi

TAB_JSON=$(curl -sS -m 3 "http://127.0.0.1:${PORT}/json/list" 2>/dev/null || echo "")
if [ -z "$TAB_JSON" ]; then
  echo "close_spawned_tabs: Chrome unreachable on port $PORT — skipping" >&2
  exit 0
fi

# Compute the list of tab IDs to close.
# - Filter to type=page
# - Skip tabs whose ID is in the baseline (existed before the skill)
# - Skip tabs whose host matches any essential_tabs host (platform tabs)
# - Skip browser-internal URLs (about:*, chrome://*, chrome-extension://*,
#   devtools://*, view-source:*). Closing these auto-collapses the window
#   and they're never skill-spawned anyway.
TO_CLOSE=$(echo "$TAB_JSON" | python3 -c "
import json, sys
from urllib.parse import urlparse

baseline = set(json.load(open(sys.argv[1])))
cfg = json.load(open(sys.argv[2]))
essential_hosts = {urlparse(u).hostname for u in cfg.get('essential_tabs', []) if u}
def normalize(h):
    return h[4:] if h and h.startswith('www.') else (h or '')
essential_norm = {normalize(h) for h in essential_hosts}

INTERNAL_SCHEMES = ('about:', 'chrome:', 'chrome-extension:', 'devtools:', 'view-source:')

data = json.load(sys.stdin)
ids = []
for t in data:
    if t.get('type') != 'page':
        continue
    tid = t.get('id')
    if not tid or tid in baseline:
        continue
    url = t.get('url', '')
    if any(url.startswith(s) for s in INTERNAL_SCHEMES) or not url:
        continue
    host = normalize(urlparse(url).hostname)
    if host in essential_norm:
        continue
    ids.append(tid + '\t' + url)
print('\n'.join(ids))
" "$BASELINE" "$BRAND_CONFIG")

if [ -z "$TO_CLOSE" ]; then
  echo "close_spawned_tabs: no spawned tabs to close" >&2
  exit 0
fi

CLOSED=0
while IFS=$'\t' read -r ID URL; do
  [ -z "$ID" ] && continue
  if curl -sS -m 3 "http://127.0.0.1:${PORT}/json/close/${ID}" >/dev/null 2>&1; then
    echo "close_spawned_tabs: closed $URL" >&2
    CLOSED=$((CLOSED + 1))
  else
    echo "close_spawned_tabs: failed to close $URL (id=$ID)" >&2
  fi
done <<< "$TO_CLOSE"

echo "close_spawned_tabs: closed $CLOSED tab(s)" >&2
