#!/bin/bash
# x_switch_account.sh <target_handle>
#
# Switch X (Twitter) to the given account if not already active.
# Caller MUST have already attached to an x.com tab (e.g. via switch_to_platform_tab.sh).
# Probes [data-testid=AppTabBar_Profile_Link] for the active handle; if mismatch,
# clicks SideNav_AccountSwitcher_Button → finds the matching UserCell → clicks it.
#
# Exits:
#   0 - already on target OR successfully switched
#   2 - target account not in the switcher popover (user must sign in to it manually)
#   3 - switch attempted but the active handle didn't change
#
# Usage: bash scripts/x_switch_account.sh swift_bible
#        bash scripts/x_switch_account.sh @vanities   # @ stripped automatically

set -e

TARGET="${1:?usage: x_switch_account.sh <handle>}"
TARGET="${TARGET#@}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

current_handle() {
  agent-browser eval "(()=>{const a=document.querySelector('[data-testid=AppTabBar_Profile_Link]');return a?a.getAttribute('href').replace(/^\//,''):'unknown'})()" 2>&1 | tail -1 | tr -d '"'
}

CURRENT="$(current_handle)"
echo "[x-switch] current=$CURRENT target=$TARGET"

if [ "$CURRENT" = "$TARGET" ]; then
  echo "[x-switch] already on @$TARGET; no switch needed"
  exit 0
fi

# Open switcher popover
agent-browser eval "document.querySelector('[data-testid=SideNav_AccountSwitcher_Button]')?.click(); 'opened'" 2>&1 | tail -1
agent-browser wait "$(bash "${REPO_ROOT}/scripts/jitter.sh" 600 1200)" 2>&1 | tail -1

# Click the UserCell matching @target. Filter out "Follow" suggestion cells —
# only signed-in accounts in this popover have no Follow text.
RESULT="$(agent-browser eval "(()=>{const cells=Array.from(document.querySelectorAll('[data-testid=UserCell]'));const c=cells.find(c=>c.textContent.includes('@${TARGET}')&&!c.textContent.includes('Follow'));if(!c)return 'not_found';c.click();return 'switched'})()" 2>&1 | tail -1 | tr -d '"')"
echo "[x-switch] click result: $RESULT"

if [ "$RESULT" != "switched" ]; then
  echo "[x-switch] ERROR: @$TARGET not present in account switcher. Sign in manually first."
  # try to dismiss the popover
  agent-browser eval "document.body.click()" >/dev/null 2>&1 || true
  exit 2
fi

# Wait for the SPA to re-render under the new account
sleep 3
agent-browser wait --load networkidle 2>&1 | tail -1 || true

NEW_CURRENT="$(current_handle)"
echo "[x-switch] post-switch current=$NEW_CURRENT"
if [ "$NEW_CURRENT" != "$TARGET" ]; then
  echo "[x-switch] ERROR: still on @$NEW_CURRENT after switch attempt"
  exit 3
fi

echo "[x-switch] OK switched to @$TARGET"
