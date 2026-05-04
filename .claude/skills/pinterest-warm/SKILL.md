---
name: pinterest-warm
description: Run a single warming pass on Pinterest (swiftbible) — scroll the home feed, save 1-3 pins, optionally follow one creator. Reads cadence from config/engagement-schedule.json and respects the daily budget + min-gap stored in ~/.social-agents/state/engagement-state.json. Use when the user says "warm pinterest", "engage on pinterest", or runs /pinterest-warm. Also called by /warm-all on a schedule.
disable-model-invocation: true
allowed-tools: Bash(*) Bash(agent-browser *) Bash(jq *) Bash(date *) Bash(grep *) Bash(awk *) Bash(test *) Bash(mkdir *) Bash(shuf *) Bash(seq *) Read(*) Write(*)
---

# Pinterest warming pass — feed-level engagement

Single run targeting `pinterest.com/swiftbible`. **Skip auto-comments.**

## Step 1: Read config + state

Same shape as `/x-warm` but with `pinterest` instead of `x`:

```bash
CFG=config/engagement-schedule.json
STATE=~/.social-agents/state/engagement-state.json
NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TODAY=$(date +%Y-%m-%d)
HOUR=$(date +%H | sed 's/^0*//'); HOUR=${HOUR:-0}

ENABLED=$(jq -r '.platforms.pinterest.enabled' "$CFG")
[ "$ENABLED" = "true" ] || exit 0
```

## Step 2: Should-run gate

Same gates as `/x-warm`: active hours, min gap since any platform's last run, daily budget for Pinterest. Keys: `state.pinterest.last_run_iso`, `state.pinterest.actions_today.{scroll,save,follow}`. Reset counts on date rollover.

## Step 3: Plan actions

Pinterest's action space (see config): `scroll`, `save`, `follow`. Action weights default to `5/4/1`. Plan 1–3 actions per run via shuf:

```bash
RUN_COUNT=$(( (RANDOM % 3) + 1 ))
PICKS=$(printf "scroll\n%.0s" $(seq 1 5); printf "save\n%.0s" $(seq 1 4); printf "follow\n%.0s" $(seq 1 1) | shuf -n "$RUN_COUNT")
```

## Step 4: Switch to Pinterest tab, ensure home feed

```bash
agent-browser tab list 2>&1 | head -10
# Switch into the pinterest.com tab. If none: tab new https://www.pinterest.com/.
agent-browser open https://www.pinterest.com/
agent-browser wait --load networkidle
agent-browser wait $(bash scripts/jitter.sh 1500 3000)
```

## Step 5: Execute each planned action

Between every action, wait `jitter.between_actions_in_run` (4–18s).

### scroll
- `agent-browser eval "window.scrollBy({top: 600 + Math.random()*500, behavior: 'smooth'})"`
- Wait 2–6s, repeat `items_to_view.min` to `items_to_view.max` times (8–20).
- One scroll *pass* = 1 action.

### save (THE main Pinterest engagement signal)

The home feed shows pins as `button "Pin card"` elements with refs `@e14`, `@e15`, …. Save buttons are NOT in the DOM until you hover or click into the pin detail. The reliable flow is **click pin → save from detail page → navigate back**.

```bash
# 1. Snapshot, find pin card refs
agent-browser snapshot -i 2>&1 | grep -E 'button "Pin card" \[ref=' | head -20

# 2. Pick one randomly
PICK_REF=$(grep -oE 'ref=e[0-9]+' /tmp/pin-cards.txt | shuf -n 1 | cut -d= -f2)
agent-browser click "@$PICK_REF"
agent-browser wait $(bash scripts/jitter.sh 1500 3000)   # land on /pin/<id>/

# 3. Find Save button on detail page (typically @e34) — re-snapshot
agent-browser snapshot -i 2>&1 | grep -E '"Save".*\[ref=' | head -3
agent-browser click "@<SAVE_REF>"
agent-browser wait $(bash scripts/jitter.sh 2000 5000)
# A "Pin Saved" toast and an "Undo Saved Pin" button confirm the save.

# 4. Optionally pick a specific board: click "Select a board to save to: <X>" (@e33),
#    pick from the dropdown that opens, THEN click Save.
#    For warming, accepting the default (usually "Profile") is fine.

# 5. Navigate back to feed for next action
agent-browser open https://www.pinterest.com/
agent-browser wait --load networkidle
agent-browser wait $(bash scripts/jitter.sh 1000 2000)
```

Increment `state.pinterest.actions_today.save` by 1.

### follow
- Pinterest exposes a Follow button on the pin's creator panel. From a pin detail page, the creator's profile link + Follow button are usually adjacent.
- Click Follow, wait jitter, increment `follow`.
- For first runs, **skip follow** (`max_per_run: 1`, `weight: 1` — it'll happen rarely anyway).

After each action, persist state immediately via `command mv -f`:

```bash
jq --arg now "$NOW_ISO" \
   --argjson plus 1 \
   ".pinterest.last_run_iso = \$now | .pinterest.actions_today.<ACTION> += \$plus" \
   "$STATE" > /tmp/engagement-state.json.tmp && command mv -f /tmp/engagement-state.json.tmp "$STATE"
```

## Step 6: Run log

`~/.social-agents/logs/warm/pinterest-default-<timestamp>.json` — same shape as the `/x-warm` log. Capture `pin_id` (extracted from the URL after click) for each `save` action, plus the board it landed in.

## Step 7: Report

One line: actions executed, today's total, what's left in the daily budget, board(s) saved into.

**Do not close the Pinterest tab.**

## Failure modes

- **Pin click navigates to a different pin domain** (rare — ads, partner pins): just go back to the feed and skip this action.
- **Save button doesn't appear** (slow render): re-snapshot once, retry; if still missing, navigate away and skip.
- **Already saved**: the Save button reads "Saved" instead of "Save" — skip and pick another pin.
- **macOS aliases `mv` to `mv -i`**: always use `command mv -f`, otherwise the skill stalls on overwrite prompts.
- **Shell is zsh**: `arr=($var)` does NOT word-split — use `shuf` over heredoc'd line lists.
