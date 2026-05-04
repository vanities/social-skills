#!/usr/bin/env bash
# Launch the persistent shared headed Chrome with the dedicated automation profile.
#
# Run once at the start of a work session. agent-browser commands afterwards
# attach to the running daemon, so skills don't need to re-pass --profile.
#
# Profile path is overridable via SOCIAL_AGENTS_CHROME_PROFILE.

set -euo pipefail

PROFILE="${SOCIAL_AGENTS_CHROME_PROFILE:-$HOME/.social-agents/chrome-profile}"
mkdir -p "$PROFILE"

# Open IG by default. Other platforms (TikTok, LinkedIn, X) can be opened
# manually as new tabs.
agent-browser --profile "$PROFILE" --headed open https://www.instagram.com/

echo
echo "Browser is up. Profile: $PROFILE"
echo "Daemon-attached commands now use this profile automatically."
echo
echo "Next:"
echo "  - Install uBlock Origin (one-time, persists in this profile)."
echo "  - If IG isn't already signed in:"
echo "      agent-browser state load ~/.config/agent-browser/instagram-swiftbible.json"
echo "      agent-browser open https://www.instagram.com/"
