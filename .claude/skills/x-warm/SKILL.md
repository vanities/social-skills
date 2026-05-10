---
name: x-warm
description: Run a single warming pass on X — scroll the home feed, like 1-3 tweets, optionally repost one. First arg is an optional brand slug (defaults to default_brand in config/brand.json). Reads cadence from config/engagement-schedule.json, brand tunables (own handle, topic regex, parody-risk handles) from config/brand.json, and respects the daily budget + min-gap stored in ~/.social-skills/state/engagement-state.json. Use when the user says "warm x", "engage on x", or runs /x-warm. Also called by /warm-all on a schedule.
argument-hint: [brand-slug]
allowed-tools: Bash(*) Bash(agent-browser *) Bash(jq *) Bash(date *) Bash(grep *) Bash(awk *) Bash(test *) Bash(mkdir *) Bash(shuf *) Bash(seq *) Read(*) Write(*)
---

# X warming pass — feed-level engagement

**Skip auto-comments** — they're the highest-risk bot-detection signal on X. This skill does scroll + like + repost only.

`$0`: optional brand slug. If empty, uses `.default_brand` from `config/brand.json`. Use this when you maintain multiple X accounts under separate brands — `/x-warm myproject` warms `brands.myproject` settings instead of the default.

## Configuration (tune via `config/brand.json` under `brands.<slug>.x`)

| Bucket | brand.json key | Purpose |
|---|---|---|
| **own_handle** | `brands.<slug>.x.own_handle` | Your X handle for this brand (no `@`). Used to skip your own tweets in the feed AND to switch the X session before warming (multi-account safe). |
| **topic_filter_regex** | `brands.<slug>.x.topic_filter_regex` | Case-insensitive regex matched against each tweet's visible text. Likes only fire on tweets that match — keeps the warming on-brand. Tune to your content domain (faith, productivity, design, indie-dev, …). |
| **exclude_handles_substring** | `brands.<slug>.x.exclude_handles_substring` | Comma-separated list of substrings; any tweet whose author handle includes one of these is skipped. Use for parody / impersonation risk. Empty string disables the filter. |

If `brand.json` is missing or the resolved brand has no `x` config, the skill aborts with a setup hint — see `config/brand.example.json` and `PERSONAL.md`.

## Step 0: Resolve brand + load config

```bash
BRAND=config/brand.json
test -f "$BRAND" || { echo "MISSING $BRAND — copy from brand.example.json (see PERSONAL.md)"; exit 1; }

# Resolve which brand this run targets: $0 if given, else default_brand from config.
SLUG="${1:-$(jq -r '.default_brand // empty' "$BRAND")}"
[ -n "$SLUG" ] || { echo "MISSING brand slug — pass as first arg or set .default_brand in $BRAND"; exit 1; }

# Pull this brand's X config.
# Raw values for shell use:
OWN_HANDLE=$(jq -r ".brands.\"$SLUG\".x.own_handle // empty" "$BRAND")
TOPIC_RE=$(jq -r ".brands.\"$SLUG\".x.topic_filter_regex // empty" "$BRAND")
# JSON-encoded values for direct interpolation into JS eval (jq -c emits a
# JSON string literal that is ALSO a valid JS string literal — no extra
# encoding needed). Using `jq -Rn --arg re ... tojson` instead would add an
# extra layer of quoting and break the regex.
OWN_HANDLE_JS=$(jq -c ".brands.\"$SLUG\".x.own_handle // null" "$BRAND")
TOPIC_RE_JS=$(jq -c ".brands.\"$SLUG\".x.topic_filter_regex // null" "$BRAND")
EXCLUDE_SUBS_JS=$(jq -c ".brands.\"$SLUG\".x.exclude_handles_substring // \"\"" "$BRAND")

[ -n "$OWN_HANDLE" ] || { echo "MISSING brands.$SLUG.x.own_handle in $BRAND"; exit 1; }
[ -n "$TOPIC_RE" ]   || { echo "MISSING brands.$SLUG.x.topic_filter_regex in $BRAND"; exit 1; }
echo "[x-warm] brand=$SLUG own_handle=@$OWN_HANDLE"

# If you maintain multiple X accounts in the same shared Chrome, switch to the
# right one before warming. The helper is a no-op when already on target.
test -x scripts/x_switch_account.sh && bash scripts/x_switch_account.sh "$OWN_HANDLE" || true
```

## Step 1: Read engagement config + state

```bash
CFG=config/engagement-schedule.json
STATE=~/.social-skills/state/engagement-state.json
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

Each warm pass = **1 scroll up front (always), then 2–3 weighted engagement actions** (likes/reposts). Scroll is the cheap browsing signal; engagement is what we're warming the account with. Without the dedicated engagement bag, the weighted sampler often lands on scroll in single-action runs and warming achieves nothing.

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
# Switch to the X tab via curl-based discovery (NEVER `agent-browser tab list`
# — auto-spawn risk). Helper does find + switch + URL-verify + tab-new
# fallback in one step.
bash scripts/switch_to_platform_tab.sh "x.com" "https://x.com/home"
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

**Topic filter (mandatory)**: NEVER like a random feed tweet. The X home feed serves Promoted tweets and off-brand content. Like only tweets that:
- Pass `topic_filter_regex` on the visible text (from `config/brand.json`)
- Are NOT Promoted (X labels promoted tweets — check for `data-testid='promotedIndicator'` or "Promoted" text in the article)
- Are NOT authored by `$OWN_HANDLE` (own tweets)
- Are NOT authored by handles matching one of `exclude_handles_substring` (parody / impersonation risk)

Pick the target via querySelector + click via DOM `.click()`. **`agent-browser click @<ref>` does NOT fire** for X like buttons; eval-based DOM `.click()` is the only reliable path.

```bash
# Pass the brand-config values into the eval. Each ${...}_JS variable is a
# pre-encoded JSON string (via jq -c) — interpolating it as a bare token
# yields a valid JS string literal. Don't wrap them in extra quotes.
agent-browser eval "(()=>{
  const own = ${OWN_HANDLE_JS}.toLowerCase();
  const topicRe = new RegExp(${TOPIC_RE_JS}, 'i');
  const excludeSubs = ${EXCLUDE_SUBS_JS}.split(',').map(s => s.trim().toLowerCase()).filter(Boolean);
  const articles = Array.from(document.querySelectorAll('article'));
  const candidates = [];
  for (const a of articles) {
    // Skip Promoted (ads)
    if (a.querySelector('[data-testid=\"promotedIndicator\"]') || (a.textContent||'').includes('Promoted')) continue;
    // Skip already-liked (data-testid is 'unlike' on liked tweets)
    if (!a.querySelector('[data-testid=\"like\"]')) continue;
    // Author handle
    const handleEl = a.querySelector('[data-testid=\"User-Name\"]');
    const handle = (handleEl?.textContent || '').match(/@([a-zA-Z0-9_]{1,15})/)?.[1] || '';
    // Skip own
    if (handle.toLowerCase() === own) continue;
    // Skip parody / impersonation risk
    if (excludeSubs.some(s => handle.toLowerCase().includes(s))) continue;
    // Topic filter
    const text = a.textContent || '';
    if (!topicRe.test(text)) continue;
    candidates.push({ article: a, handle: '@' + handle, sample: text.slice(0, 80).replace(/\\s+/g, ' ').trim() });
  }
  if (candidates.length === 0) return { ok: false, reason: 'no on-topic unliked non-Promoted tweets in current viewport' };
  const pick = candidates[Math.floor(Math.random() * candidates.length)];
  const btn = pick.article.querySelector('[data-testid=\"like\"]');
  btn.click();
  return { ok: true, handle: pick.handle, sample: pick.sample, candidate_count: candidates.length };
})()"
```

If the eval returns `ok: false`, scroll once and retry up to 2 times. If still no candidates, **skip the like action for this run** — don't fall through to a random pick.

Verify by re-querying — `data-testid` should flip from `like` to `unlike`:
```bash
agent-browser eval "(()=>{const a=document.querySelector('article [data-testid=\"unlike\"]');return a?'OK liked':'still like'})()"
```

Wait jitter (4–18s) before next action. Increment `state.x.actions_today.like` by 1 only after the verify confirms the flip.

### repost
- Re-snapshot. Find `button "<N> reposts. Repost"` refs (the dropdown trigger).
- Filter out own tweets (handle equals `$OWN_HANDLE`).
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

After all actions, write `~/.social-skills/logs/warm/x-default-<timestamp>.json`:

```json
{
  "ts_start": "...",
  "ts_end":   "...",
  "platform": "x",
  "account":  "default",
  "x_handle": "@${OWN_HANDLE}",
  "outcome":  "success | partial | failed",
  "planned_actions":  ["scroll", "like"],
  "executed_actions": [
    {"type": "scroll", "items_viewed": 8, "duration_s": 32},
    {"type": "like",   "tweet_author": "@example", "tweet_id": "..."}
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
