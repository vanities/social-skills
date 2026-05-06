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

IG action space: `scroll`, `like`. Each warm pass = **1 scroll up front (always), then 2–3 likes** (the only engagement action available). 2026-05-05 user feedback: warm passes should land 2–3 engagement actions per fire, not 0–1.

```bash
ENG_COUNT=$(( (RANDOM % 2) + 2 ))   # 2 or 3
PICKS=$(printf "scroll\n"; printf "like\n%.0s" $(seq 1 "$ENG_COUNT"))
```

(IG only exposes `like` as a non-comment, non-follow engagement; the "weighted bag" of one action degenerates to N likes. Cap is `max_per_run: 3`, so 2–3 fits.)

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

IG's home feed renders posts as a vertical stack. Each post has a Like button rendered as an **`<svg aria-label="Like">` inside a `<div role="button">`**. The accessibility tree presents these as `button "Like"`, but the actual clickable target is the parent div, NOT the SVG itself. The aria-label flips to `Unlike` after a successful like.

**Critical**: agent-browser's snapshot @e refs for these "Like" buttons frequently fail to register a click — IG's React handler ignores synthesized clicks on elements that are off-screen. Use this pattern instead:

1. Find all Like SVGs via `querySelectorAll('svg[aria-label="Like"]')`
2. Walk up to the nearest `[role=button]` ancestor — that's the clickable
3. Mark it with a unique id via eval
4. **`scrollIntoView({block:'center'})` BEFORE clicking** — this is what made the live test pass after several no-ops
5. `agent-browser click "#<id>"` — now the click triggers the React handler
6. Verify by checking the SVG's aria-label flipped to `Unlike`

```bash
# Step 1-3: pick a random Like target, mark it
agent-browser eval "(()=>{const ss=Array.from(document.querySelectorAll('svg[aria-label=\"Like\"]'));const i=Math.floor(Math.random()*ss.length);let e=ss[i];while(e&&e.getAttribute('role')!=='button'&&e.parentElement)e=e.parentElement;e.id='ig-like-target';return {i,marked:e?.id}})()"

# Step 4: scroll into view (REQUIRED — without this the click silently fails)
agent-browser eval "document.querySelector('#ig-like-target')?.scrollIntoView({block:'center',behavior:'smooth'})"
agent-browser wait $(bash scripts/jitter.sh 1500 2500)

# Step 5: click
agent-browser click "#ig-like-target"
agent-browser wait $(bash scripts/jitter.sh 4000 10000)

# Step 6: verify — SVG aria-label should now read "Unlike"
agent-browser eval "document.querySelector('#ig-like-target svg')?.getAttribute('aria-label')"
# expected output: "Unlike"
```

Increment `state.instagram.actions_today.like` by 1 only after the verify step confirms the flip; if it still says "Like", retry once with another scroll-into-view, otherwise log skip and don't increment.

To filter out own posts before selecting, find the author handle by walking up to the enclosing `<article>` and reading the post header text. For day-1 warming, the random pick is fine — odds of hitting your own post in a feed of 9+ are low.

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
