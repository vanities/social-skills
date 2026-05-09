#!/usr/bin/env bash
# Launch the persistent shared headed Chrome with the dedicated automation profile.
#
# Run once at the start of a work session. agent-browser commands afterwards
# attach to the running daemon, so skills don't need to re-pass --profile.
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
ENV_FILE="$(dirname "$0")/../.env"
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

# --disable-blink-features=AutomationControlled removes the navigator.webdriver
# flag IG and others use to detect automation. Other flags are anti-noise.
agent-browser \
  --executable-path "$CHROME_BIN" \
  --profile "$PROFILE" \
  --headed \
  --args "--disable-blink-features=AutomationControlled,--disable-features=ChromeWhatsNewUI" \
  open https://www.instagram.com/

echo
echo "Browser is up. Profile:  $PROFILE"
echo "Chrome binary:          $CHROME_BIN"
echo "Daemon-attached commands now use this Chrome + profile automatically."
echo
echo "Next:"
echo "  - Install uBlock Origin from chrome web store (one-time, persists)."
echo "  - If IG isn't already signed in:"
echo "      agent-browser state load ~/.config/agent-browser/instagram-<your-account>.json"
echo "      agent-browser open https://www.instagram.com/"
