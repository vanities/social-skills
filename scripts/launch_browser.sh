#!/usr/bin/env bash
# Launch the persistent shared headed Chrome with the dedicated automation profile.
#
# Run once at the start of a work session, OR after a crash to restore your tabs.
# Idempotent: if Chrome is already running with this profile, the essential-tabs
# verifier just adds anything missing.
#
# After Chrome boots:
#   1. Chrome's --restore-last-session flag replays the previous tab set
#      (clean shutdown OR crash — no "Restore?" prompt to click).
#   2. We probe Chrome's /json/list and verify every URL listed in
#      `essential_tabs` (config/brand.json) is open. Any missing one is opened
#      via `agent-browser tab new`. Pin them in Chrome once and they stay
#      pinned across restarts.
#
# agent-browser commands afterwards attach to the running daemon, so skills
# don't need to re-pass --profile.
#
# Defaults to your installed Google Chrome (more stable than Chrome for Testing,
# supports real extensions like uBlock via the web store, and behaves like a
# normal browser when you click into chrome:// pages).
#
# Overridable env:
#   SOCIAL_SKILLS_CHROME_PROFILE  — profile dir (default: ~/.social-skills/chrome-profile)
#   SOCIAL_SKILLS_CHROME_BINARY   — Chrome executable (default: /Applications/Google Chrome.app/...)

set -euo pipefail

# Resolution order for both vars: shell env → .env file → hardcoded default.
# Single-var greps (never `source`) so passwords with $ in .env stay literal.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"
if [[ -f "$ENV_FILE" ]]; then
  : "${SOCIAL_SKILLS_CHROME_PROFILE:=$(grep -m1 '^SOCIAL_SKILLS_CHROME_PROFILE=' "$ENV_FILE" | cut -d= -f2-)}"
  : "${SOCIAL_SKILLS_CHROME_BINARY:=$(grep -m1 '^SOCIAL_SKILLS_CHROME_BINARY=' "$ENV_FILE" | cut -d= -f2-)}"
fi
PROFILE="${SOCIAL_SKILLS_CHROME_PROFILE:-$HOME/.social-skills/chrome-profile}"
CHROME_BIN="${SOCIAL_SKILLS_CHROME_BINARY:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
PROFILE="${PROFILE/#\~/$HOME}"

mkdir -p "$PROFILE"

if [ ! -x "$CHROME_BIN" ]; then
  echo "[error] Chrome binary not found at: $CHROME_BIN" >&2
  echo "Install Google Chrome from https://www.google.com/chrome/ or set SOCIAL_SKILLS_CHROME_BINARY." >&2
  exit 1
fi

BRAND_JSON="$REPO_ROOT/config/brand.json"

# --disable-blink-features=AutomationControlled removes the navigator.webdriver
# flag IG and others use to detect automation.
# --restore-last-session forces Chrome to replay the previous tab set on every
# launch (including post-crash) — no "Restore?" infobar to click. Combined with
# pinned tabs in Chrome, your platform tabs come back automatically.
# --disable-features=ChromeWhatsNewUI suppresses the "What's New" pop on first
# run after a Chrome update.
CHROME_ARGS="--disable-blink-features=AutomationControlled,--restore-last-session,--disable-features=ChromeWhatsNewUI"

# We boot Chrome with about:blank rather than a specific platform URL so
# --restore-last-session has room to replay the previous session without our
# launch URL fighting for tab ordering. The essential-tabs verifier below adds
# any missing tabs after Chrome settles.
agent-browser \
  --executable-path "$CHROME_BIN" \
  --profile "$PROFILE" \
  --headed \
  --args "$CHROME_ARGS" \
  open about:blank

echo
echo "Browser is up. Profile:  $PROFILE"
echo "Chrome binary:           $CHROME_BIN"

# --- Essential-tabs verification ---------------------------------------------
# Wait for Chrome to settle (session restore takes a moment), then probe the
# list of currently-open tabs via plain HTTP and add any missing essentials.
# This NEVER calls agent-browser tab list — that path can auto-spawn a fresh
# Chrome on CDP attach failure (see AGENTS.md "Known issues").

ensure_essential_tabs() {
  if [ ! -f "$BRAND_JSON" ]; then
    echo "[essential-tabs] no $BRAND_JSON — skipping (copy from brand.example.json to enable)"
    return 0
  fi

  local count
  count=$(jq -r '.essential_tabs // [] | length' "$BRAND_JSON" 2>/dev/null || echo 0)
  if [ "$count" = "0" ]; then
    echo "[essential-tabs] no .essential_tabs in $BRAND_JSON — skipping"
    return 0
  fi

  # Wait up to ~10s for Chrome's DevTools port file to appear + tabs to settle.
  local port=""
  for i in 1 2 3 4 5 6 7 8 9 10; do
    if [ -f "$PROFILE/DevToolsActivePort" ]; then
      port=$(head -1 "$PROFILE/DevToolsActivePort" 2>/dev/null || true)
      [ -n "$port" ] && break
    fi
    sleep 1
  done
  if [ -z "$port" ]; then
    echo "[essential-tabs] Chrome's DevTools port didn't appear in 10s — skipping verifier"
    return 0
  fi

  # Give session restore another beat to finish replaying tabs.
  sleep 2

  # Snapshot currently-open URLs.
  local current
  current=$(curl -sS -m 5 "http://127.0.0.1:${port}/json/list" 2>/dev/null \
    | jq -r '.[] | select(.type=="page") | .url' 2>/dev/null || true)

  echo "[essential-tabs] checking $count expected URLs against $(echo "$current" | grep -c . || echo 0) open tabs..."

  # We match by HOST (domain), not URL. Two reasons:
  #   1. A pinned tab restored after crash sits at whatever URL the user last
  #      navigated to (Chrome remembers per-tab URLs across restarts). So an
  #      IG tab pinned to /swift_bible/ might show /explore/ after restore —
  #      same tab, different path. Domain match treats it as present.
  #   2. Avoids creating duplicate tabs when the user has navigated within a
  #      site during a session.
  # Trade-off: if you really want a SECOND tab on the same domain (e.g. two
  # different X handles), the verifier won't add it on launch. Pin both in
  # Chrome and they'll be restored by --restore-last-session anyway.
  local open_hosts
  open_hosts=$(echo "$current" | sed -E 's#^https?://([^/]+)/?.*$#\1#' | sort -u)

  local missing=0
  while IFS= read -r url; do
    [ -z "$url" ] && continue
    local host
    host=$(echo "$url" | sed -E 's#^https?://([^/]+)/?.*$#\1#')
    if echo "$open_hosts" | grep -qxF "$host"; then
      echo "  ✓ host already open: $host  ($url)"
    else
      echo "  + opening: $url"
      agent-browser tab new "$url" >/dev/null 2>&1 || echo "    (tab new failed for $url)"
      missing=$((missing + 1))
      sleep 1
    fi
  done < <(jq -r '.essential_tabs[]?' "$BRAND_JSON")

  if [ "$missing" -gt 0 ]; then
    echo "[essential-tabs] opened $missing missing tab(s). Pin them in Chrome (right-click → Pin) so they stick across restarts."
  else
    echo "[essential-tabs] all expected tabs present."
  fi
}

ensure_essential_tabs

echo
echo "Daemon-attached commands now use this Chrome + profile automatically."
echo
echo "Next:"
echo "  - Install uBlock Origin from chrome web store (one-time, persists)."
echo "  - Pin essential tabs (right-click tab → Pin) so they're easy to spot AND"
echo "    survive accidental close. Pinned tabs are restored by --restore-last-session."
echo "  - Add platform login state via /<platform>-login skills if any are missing."
