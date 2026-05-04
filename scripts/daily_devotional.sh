#!/usr/bin/env bash
# Daily-devotional pipeline: screenshot the booted iOS simulator, post to Instagram.
#
# Prereq: a simulator booted and showing the devotional view of choice.
# Run a one-time login first:
#   uv run social-agents login --platform instagram --account "$SOCIAL_AGENTS_IG_ACCOUNT"

set -euo pipefail

# --- config ---
ACCOUNT="${SOCIAL_AGENTS_IG_ACCOUNT:-adam}"
TODAY="$(date +%Y-%m-%d)"
SCREENSHOT="${TMPDIR:-/tmp}/daily-devotional-${TODAY}.png"
CAPTION_FILE="${HOME}/.social-agents/daily-devotional-caption.txt"

# --- screenshot the simulator ---
if ! xcrun simctl list devices | grep -q '(Booted)'; then
  echo "[error] no booted simulator. Open one in Xcode first." >&2
  exit 1
fi
xcrun simctl io booted screenshot "$SCREENSHOT"
echo "[ok] screenshot saved: $SCREENSHOT"

# --- caption (optional) ---
caption=""
if [ -f "$CAPTION_FILE" ]; then
  caption="$(cat "$CAPTION_FILE")"
fi

# --- post via the agent ---
cd "$(dirname "$0")/.."
uv run social-agents post \
  --platform instagram \
  --account "$ACCOUNT" \
  --media "$SCREENSHOT" \
  --caption "$caption"
