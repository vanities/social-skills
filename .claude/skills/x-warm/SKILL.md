---
name: x-warm
description: Run a single warming pass on X (@swift_bible) — scroll the home feed, like 1-3 tweets, optionally repost one. Reads cadence from config/engagement-schedule.json and respects the daily budget + min-gap stored in ~/.social-agents/state/engagement-state.json. Use when the user says "warm x", "engage on x", or runs /x-warm. Also called by /warm-all on a schedule.
disable-model-invocation: true
allowed-tools: Bash(*) Bash(agent-browser *) Bash(jq *) Bash(date *) Bash(grep *) Bash(awk *) Bash(test *) Bash(mkdir *) Bash(shuf *) Bash(seq *) Read(*) Write(*)
---

# X warming pass — feed-level engagement

Single run targeting `@swift_bible`. **Skip auto-comments** — they're the highest-risk bot-detection signal on X.

## Step 1: Read config + state

```bash
CFG=config/engagement-schedule.json
STATE=~/.social-agents/state/engagement-state.json
test -f "$CFG" && test -f "$STATE" || { echo "MISSING config or state"; exit 1; }

ENABLED=$(jq -r '.platforms.x.enabled' "$CFG")
[ "$ENABLED" = "true" ] || { echo "x is disabled in $CFG; exiting"; exit 0; }

NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TODAY=$(date +%Y-%m-%d)
HOUR=$(date +%H | sed 's/^0*//')   # strip leading zeros
HOUR=${HOUR:-0}                     # 00 → empty after strip → default 0
```

## Step 2: Should-run gate

Three conditions must hold:

a. **Active hours**: `global.active_hours.start ≤ HOUR ≤ global.active_hours.end`.
b. **Min gap**: `last_run_iso` (any platform) is more than `min_gap_minutes_between_platforms` ago, OR null.
c. **Budget**: today's `actions_today` total < `daily_action_budget.max` for the X platform; reset to zero if `actions_today.date` ≠ today.

```bash
START_H=$(jq -r '.global.active_hours.start' "$CFG")
END_H=$(jq -r '.global.active_hours.end' "$CFG")
if [ "$HOUR" -lt "$START_H" ] || [ "$HOUR" -gt "$END_H" ]; then
  echo "outside active hours ($HOUR not in $START_H-$END_H); exiting"; exit 0
fi

MIN_GAP=$(jq -r '.global.min_gap_minutes_between_platforms' "$CFG")
LAST_ANY=$(jq -r '[.x.last_run_iso, .pinterest.last_run_iso, .instagram.last_run_iso] | map(select(. != null)) | max // empty' "$STATE")
if [ -n "$LAST_ANY" ]; then
  GAP_SECONDS=$(( $(date -u +%s) - $(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$LAST_ANY" +%s 2>/dev/null || echo 0) ))
  if [ "$GAP_SECONDS" -lt $((MIN_GAP * 60)) ]; then
    echo "min-gap not met (${GAP_SECONDS}s < $((MIN_GAP * 60))s); exiting"; exit 0
  fi
fi

# Reset today's counts if the date rolled over
STORED_DATE=$(jq -r '.x.actions_today.date // empty' "$STATE")
if [ "$STORED_DATE" != "$TODAY" ]; then
  jq --arg t "$TODAY" '.x.actions_today = {"date": $t, "scroll": 0, "like": 0, "repost": 0}' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
fi

DONE_TOTAL=$(jq -r '[.x.actions_today.scroll, .x.actions_today.like, .x.actions_today.repost] | add' "$STATE")
MAX_BUDGET=$(jq -r '.platforms.x.daily_action_budget.max' "$CFG")
if [ "$DONE_TOTAL" -ge "$MAX_BUDGET" ]; then
  echo "daily budget exhausted ($DONE_TOTAL >= $MAX_BUDGET); exiting"; exit 0
fi
```

## Step 3: Plan this run's actions

Each warm pass = **1 scroll up front (always), then 2–3 weighted engagement actions** (likes/reposts). Scroll is the cheap browsing signal; engagement is what we're warming the account with. Without the dedicated engagement bag, the weighted sampler often lands on scroll in single-action runs and warming achieves nothing — the prior shape was 1–3 actions including scroll, which usually meant "1 scroll, no engagement". 2026-05-05 user feedback: "should we do like 2-3?" — yes.

```bash
# Always 1 scroll, then 2-3 engagement actions
ENG_COUNT=$(( (RANDOM % 2) + 2 ))   # 2 or 3
RUN_COUNT=$(( ENG_COUNT + 1 ))
REMAINING=$((MAX_BUDGET - DONE_TOTAL))
[ "$RUN_COUNT" -gt "$REMAINING" ] && RUN_COUNT=$REMAINING && ENG_COUNT=$((RUN_COUNT - 1))

# Build a weighted bag of ENGAGEMENT actions only (no scroll).
BAG=()
for action in like repost; do
  WEIGHT=$(jq -r ".platforms.x.actions.$action.weight // 0" "$CFG")
  for _ in $(seq 1 "$WEIGHT"); do BAG+=("$action"); done
done
PLANNED=("scroll")
for _ in $(seq 1 "$ENG_COUNT"); do
  PLANNED+=("${BAG[$((RANDOM % ${#BAG[@]}))]}")
done
echo "Planned actions: ${PLANNED[*]}"
```

**Per-action caps still apply.** If `PLANNED` accumulates more `repost`s than `actions.repost.max_per_run` (default 1), drop the extras and replace with `like`. (Likes have `max_per_run: 3` so 2-3 likes per run is fine.)

## Step 4: Switch to X tab, ensure home

```bash
agent-browser tab list 2>&1 | head -10
# Find the x.com tab index, switch into it. If none: tab new https://x.com/home.
# Then:
agent-browser open https://x.com/home   # safe even on existing tab; refreshes feed
agent-browser wait --load networkidle
agent-browser wait $(bash scripts/jitter.sh 1500 3000)
```

If `agent-browser get url` returns `/i/flow/login`, abort and tell user to run `/x-login`.

## Step 5: Execute each planned action

Between every action, wait `jitter.between_actions_in_run` (4–18s). This is the most important anti-bot signal: humans don't fire actions back-to-back.

### scroll
- `agent-browser eval "window.scrollBy({top: 800 + Math.random()*400, behavior: 'smooth'})"`
- Wait `jitter.between_scroll_pauses` (2–6s).
- Repeat `items_to_view.min` to `items_to_view.max` times.
- Increment `state.x.actions_today.scroll` by 1 (one scroll PASS = 1 action, not N).

### like
- Re-snapshot. Find `button "<N> Likes. Like"` refs (NOT `Liked` — those are already-liked).
- Filter out tweets authored by `@swift_bible` (the article aria-label includes the author handle).
- Pick a random ref from the remaining set.
- **Click via eval, NOT `agent-browser click @<ref>`**. 2026-05-05 live test: `agent-browser click @<ref>` returned `✓ Done` for X like buttons but the click event didn't fire — count and aria-label stayed unchanged. Eval-based DOM `.click()` worked first try on both attempted likes. Stale-ref problem: the feed re-renders frequently and X's React handler ignores synthesized clicks on stale refs.
  ```bash
  # Find the chosen tweet's article via the like button's text. Get a stable handle
  # via querySelector with data-testid="like" inside the article, then click.
  agent-browser eval "(()=>{const arts=Array.from(document.querySelectorAll('article'));const a=arts.find(x=>!(x.textContent||'').match(/@swift_bible/i)&&x.querySelector('[data-testid=\"like\"]'));if(!a)return 'no candidate';const btn=a.querySelector('[data-testid=\"like\"]');btn.click();return {author:(a.querySelector('[data-testid=\"User-Name\"] a')?.textContent||'').slice(0,40),clicked:true}})()"
  ```
- Verify by re-querying the same article — `data-testid` should flip from `like` to `unlike`, and the count number should increment by 1.
  ```bash
  agent-browser eval "(()=>{const a=document.querySelector('article [data-testid=\"unlike\"]');return a?'OK liked':'still like'})()"
  ```
- Wait jitter (4–18s) before next action.
- Increment `state.x.actions_today.like` by 1. **One like = one action.** Do NOT like multiple tweets in a single planned `like` slot — re-plan for that.

### repost
- Re-snapshot. Find `button "<N> reposts. Repost"` refs (the dropdown trigger).
- Filter out own tweets.
- Click the chosen ref. A menu opens with "Repost" / "Quote".
- Click the **"Repost"** menu item (NOT Quote).
- Wait jitter.
- Increment `state.x.actions_today.repost` by 1.

After each action, persist state immediately (so a crash mid-run doesn't lose budget tracking). **Use `command mv -f`** — macOS aliases `mv` to `mv -i` which prompts for overwrite and stalls the skill:

```bash
jq --arg now "$NOW_ISO" \
   --argjson plus 1 \
   ".x.last_run_iso = \$now | .x.actions_today.<ACTION> += \$plus" \
   "$STATE" > /tmp/engagement-state.json.tmp && command mv -f /tmp/engagement-state.json.tmp "$STATE"
```

**Shell gotcha**: this project's shell is zsh, not bash — `arr=($var)` does NOT word-split. To pick a random element from a list, use `shuf` over a heredoc'd line list, NOT a bash-style array:

```bash
PICK=$(printf "%s\n" "ref1:author1" "ref2:author2" "ref3:author3" | shuf -n 1)
LIKE_REF="@$(echo "$PICK" | cut -d: -f1)"
```

## Step 6: Run log

After all actions, write `~/.social-agents/logs/warm/x-default-<timestamp>.json`:

```json
{
  "ts_start": "...",
  "ts_end":   "...",
  "platform": "x",
  "account":  "default",
  "x_handle": "@swift_bible",
  "outcome":  "success | partial | failed",
  "planned_actions":  ["scroll", "like"],
  "executed_actions": [
    {"type": "scroll", "items_viewed": 8, "duration_s": 32},
    {"type": "like",   "tweet_author": "@JoyceMeyer", "tweet_id": "..."}
  ],
  "actions_today_after": {"scroll": 1, "like": 1, "repost": 0},
  "skipped_reason": null
}
```

## Step 7: Report

One line: which actions ran, today's total, what's left in the daily budget.

**Do not close the X tab.**

## Failure modes to handle

- **No actionable tweets found** (rare — feed always has content): skip the action, log skip reason, don't crash the run.
- **Repost dropdown didn't open** (UI lag): re-snapshot once, retry; if still failing, skip the action.
- **State file corrupt** (very rare): write log entry with `outcome: failed`, do not auto-recover — let the user inspect.
- **Quoted-Repost vs plain Repost**: only ever click the menu option labeled exactly `Repost`, never `Quote`. Quoting requires a typed comment which we explicitly skip.
