---
name: instagram-warm
description: Run a single warming pass on Instagram (swift_bible) — scroll the home feed, like 1-3 posts. Reads cadence from config/engagement-schedule.json and respects the daily budget + min-gap stored in ~/.social-agents/state/engagement-state.json. Use when the user says "warm instagram", "engage on ig", or runs /instagram-warm. Also called by /warm-all on a schedule.
disable-model-invocation: true
allowed-tools: Bash(*) Bash(agent-browser *) Bash(jq *) Bash(date *) Bash(grep *) Bash(awk *) Bash(test *) Bash(mkdir *) Bash(shuf *) Bash(seq *) Read(*) Write(*)
---

# Instagram warming pass — feed-level engagement

Single run targeting `instagram.com/swift_bible`. **Skip auto-comments AND auto-follows** — IG is the most aggressive about bot-detection signals among the three. Start scroll-only + like, ramp up later if engagement is healthy.

## Step 1: Read config + state

Same shape as `/x-warm` and `/pinterest-warm`, with `instagram` keys.

## Step 2: Should-run gate

Same gates: active hours, min gap, daily budget for IG (default `min: 3, max: 6` — tightest of the three; IG punishes high volume).

## Step 3: Plan actions

IG action space: `scroll`, `like`. Default weights `6/3` (scroll-heavy). Plan 1–2 actions per run.

```bash
RUN_COUNT=$(( (RANDOM % 2) + 1 ))
PICKS=$(printf "scroll\n%.0s" $(seq 1 6); printf "like\n%.0s" $(seq 1 3) | shuf -n "$RUN_COUNT")
```

## Step 4: Switch to IG tab, ensure home feed

```bash
agent-browser tab list 2>&1 | head -10
# Switch into the instagram.com tab. If none: tab new https://www.instagram.com/.
agent-browser open https://www.instagram.com/
agent-browser wait --load networkidle
agent-browser wait $(bash scripts/jitter.sh 1500 3000)
```

## Step 5: Execute each planned action

Between every action, wait `jitter.between_actions_in_run` (4–18s).

### scroll
- `agent-browser eval "window.scrollBy({top: 700 + Math.random()*400, behavior: 'smooth'})"`
- Wait 2–6s, repeat 6–12 times.
- One scroll pass = 1 action.

### like

IG's home feed renders posts as a vertical stack. Each post has a Like button (heart icon) — its accessibility label is `Like` (or `Unlike` once liked). The Like button typically lives inside an article element with the post's author handle.

```bash
# 1. Snapshot, find Like buttons on visible posts
agent-browser snapshot -i 2>&1 | grep -E 'button "Like".*\[ref=' | head -10 > /tmp/ig-likes.txt
# Filter out posts authored by @swift_bible (own posts) — author appears in the surrounding article context.

# 2. Pick one randomly
PICK=$(grep -oE 'ref=e[0-9]+' /tmp/ig-likes.txt | shuf -n 1 | cut -d= -f2)
agent-browser click "@$PICK"
agent-browser wait $(bash scripts/jitter.sh 4000 12000)

# 3. Verify — re-snapshot and confirm the same ref's button is now "Unlike"
```

Increment `state.instagram.actions_today.like` by 1.

After each action, persist state immediately via `command mv -f` (macOS aliases `mv` to `mv -i`):

```bash
jq --arg now "$NOW_ISO" --argjson plus 1 \
   ".instagram.last_run_iso = \$now | .instagram.actions_today.<ACTION> += \$plus" \
   "$STATE" > /tmp/engagement-state.json.tmp && command mv -f /tmp/engagement-state.json.tmp "$STATE"
```

## Step 6: Run log

`~/.social-agents/logs/warm/instagram-default-<timestamp>.json` — same shape as `/x-warm`'s log. Record the post author and handle for each `like`.

## Step 7: Report

One line: actions executed, today's total, what's left in the daily budget.

**Do not close the IG tab.**

## Failure modes

- **No Like buttons in snapshot** (e.g. you landed on Stories not feed): `agent-browser open https://www.instagram.com/` to force-route to the home feed, re-snapshot.
- **Already-liked posts only** (every visible Like is actually "Unlike"): scroll once and re-snapshot.
- **Story / Reels promo overlay**: dismiss any "Watch Reels" / "See Stories" prompt before snapshotting (usually a small "Not now" or `X` close button).
- **Shell is zsh**: `arr=($var)` does NOT word-split — use `shuf`. **macOS aliases `mv` to `mv -i`**: always use `command mv -f`.
- **IG is the strictest** about bot patterns: keep daily budget low (3-6) and DO NOT add follow / comment to this skill without observing how the existing scroll+like cadence is received first.
