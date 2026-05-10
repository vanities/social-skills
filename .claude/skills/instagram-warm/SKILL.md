---
name: instagram-warm
description: Run a single warming pass on Instagram — scroll the home feed, like 1-3 posts. First arg is an optional brand slug (defaults to default_brand in config/brand.json). Reads cadence from config/engagement-schedule.json, brand tunables (own handle, topic regex) from config/brand.json. Use when the user says "warm instagram", "engage on ig", or runs /instagram-warm. Also called by /warm-all on a schedule.
argument-hint: [brand-slug]
allowed-tools: Bash(*) Bash(agent-browser *) Bash(jq *) Bash(date *) Bash(grep *) Bash(awk *) Bash(test *) Bash(mkdir *) Bash(shuf *) Bash(seq *) Read(*) Write(*)
---

# Instagram warming pass — feed-level engagement

**Skip auto-comments AND auto-follows** — IG is the most aggressive about bot-detection signals. Stay scroll-only + like; ramp up only after observing how the cadence is received over weeks.

`$0`: optional brand slug. Empty → uses `.default_brand` from `config/brand.json`.

## Configuration (tune via `config/brand.json` under `brands.<slug>.instagram`)

| Bucket | brand.json key | Purpose |
|---|---|---|
| **own_handle** | `brands.<slug>.instagram.own_handle` | Your IG handle for this brand (no `@`). Used to skip your own posts in the feed. |
| **topic_filter_regex** | `brands.<slug>.instagram.topic_filter_regex` | Optional. If present, likes only fire on posts whose visible text matches. Falls back to `brands.<slug>.x.topic_filter_regex` if the IG-specific one isn't set, since most users want one regex per brand domain. |

If `brand.json` is missing or this brand has no IG config, the skill aborts with a setup hint.

## Step 0: Resolve brand + load config

```bash
BRAND=config/brand.json
test -f "$BRAND" || { echo "MISSING $BRAND — copy from brand.example.json (see PERSONAL.md)"; exit 1; }

SLUG="${1:-$(jq -r '.default_brand // empty' "$BRAND")}"
[ -n "$SLUG" ] || { echo "MISSING brand slug — pass as first arg or set .default_brand in $BRAND"; exit 1; }

# Raw values for shell use:
OWN_HANDLE=$(jq -r ".brands.\"$SLUG\".instagram.own_handle // empty" "$BRAND")
TOPIC_RE=$(jq -r ".brands.\"$SLUG\".instagram.topic_filter_regex // .brands.\"$SLUG\".x.topic_filter_regex // empty" "$BRAND")
# JSON-encoded values for JS eval interpolation (jq -c emits a JSON string
# literal that's also a valid JS string literal). Falls back to x's regex
# if instagram doesn't have its own.
OWN_HANDLE_JS=$(jq -c ".brands.\"$SLUG\".instagram.own_handle // null" "$BRAND")
TOPIC_RE_JS=$(jq -c ".brands.\"$SLUG\".instagram.topic_filter_regex // .brands.\"$SLUG\".x.topic_filter_regex // null" "$BRAND")

[ -n "$OWN_HANDLE" ] || { echo "MISSING brands.$SLUG.instagram.own_handle in $BRAND"; exit 1; }
[ -n "$TOPIC_RE" ]   || { echo "MISSING topic_filter_regex (instagram or x) for brands.$SLUG in $BRAND"; exit 1; }
echo "[ig-warm] brand=$SLUG own_handle=@$OWN_HANDLE"
```

## Step 1: Read engagement config + state

Same shape as `/x-warm`, with `instagram` keys in `engagement-schedule.json` and `engagement-state.json`.

## Step 2: Should-run gate

Same gates: active hours, min gap, daily budget for IG (default `min: 3, max: 6` — tightest of the three; IG punishes high volume).

## Step 3: Plan actions

IG action space: `scroll`, `like`. Each warm pass = **1 scroll up front (always), then 2–3 likes** (the only engagement action available).

```bash
ENG_COUNT=$(( (RANDOM % 2) + 2 ))   # 2 or 3
PICKS=$(printf "scroll\n"; printf "like\n%.0s" $(seq 1 "$ENG_COUNT"))
```

(IG only exposes `like` as a non-comment, non-follow engagement; the "weighted bag" of one action degenerates to N likes. Cap is `max_per_run: 3`, so 2–3 fits.)

## Step 4: Switch to IG tab, ensure home feed

```bash
# Switch to the IG tab via curl-based discovery (NEVER `agent-browser tab list` —
# it auto-spawns a fresh Chrome on CDP attach failure even when HTTP is healthy).
bash scripts/switch_to_platform_tab.sh "instagram.com" "https://www.instagram.com/"
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

**Critical**: agent-browser's snapshot @e refs for these "Like" buttons frequently fail to register a click — IG's React handler ignores synthesized clicks on elements that are off-screen. Use this pattern:

1. Find an on-topic Like target via `querySelectorAll('article')` + topic regex (NOT random)
2. Skip ads (header contains "Sponsored" / "Promoted") and own posts
3. Walk up to the nearest `[role=button]` ancestor — that's the clickable
4. Mark it with a unique id via eval
5. **`scrollIntoView({block:'center'})` BEFORE clicking** — required, off-screen synthetic clicks no-op
6. `agent-browser click "#<id>"` — triggers the React handler
7. Verify by checking the SVG's aria-label flipped to `Unlike`

**Topic filter (mandatory)**: NEVER like a random feed post. The IG home feed is heavily algorithm-driven and serves ads + off-brand content. Filter to posts whose visible text matches `topic_filter_regex` (from `config/brand.json`) AND skip Sponsored posts.

```bash
agent-browser eval "(()=>{
  const own = ${OWN_HANDLE_JS}.toLowerCase();
  const topicRe = new RegExp(${TOPIC_RE_JS}, 'i');
  const articles = Array.from(document.querySelectorAll('article'));
  const candidates = [];
  for (const a of articles) {
    const header = (a.querySelector('header')?.textContent || '').toLowerCase();
    if (header.includes('sponsored') || header.includes('promoted')) continue;     // skip ads
    if (header.includes(own)) continue;                                              // skip own posts
    const likeSvg = a.querySelector('svg[aria-label=\"Like\"]');                     // already-liked are 'Unlike' — implicitly skipped
    if (!likeSvg) continue;
    const text = (a.textContent || '');
    if (!topicRe.test(text)) continue;                                               // topic filter
    candidates.push({ svg: likeSvg, sample: text.slice(0, 100).replace(/\\s+/g, ' ').trim() });
  }
  if (candidates.length === 0) return { ok: false, reason: 'no on-topic unliked posts in current viewport' };
  const pick = candidates[Math.floor(Math.random() * candidates.length)];
  let e = pick.svg;
  while (e && e.getAttribute('role') !== 'button' && e.parentElement) e = e.parentElement;
  e.id = 'ig-like-target';
  return { ok: true, sample: pick.sample, candidate_count: candidates.length };
})()"
```

If the eval returns `ok: false`, scroll once and retry up to 2 times. If still no candidates, **skip the like action for this run** — don't fall through to a random pick. Decrement the planned action count and continue.

```bash
# Required: scroll into view before click — without this, the click silently no-ops
agent-browser eval "document.querySelector('#ig-like-target')?.scrollIntoView({block:'center',behavior:'smooth'})"
agent-browser wait $(bash scripts/jitter.sh 1500 2500)

# Click
agent-browser click "#ig-like-target"
agent-browser wait $(bash scripts/jitter.sh 4000 10000)

# Verify — SVG aria-label should now read "Unlike"
agent-browser eval "document.querySelector('#ig-like-target svg')?.getAttribute('aria-label')"
# expected output: "Unlike"
```

Increment `state.instagram.actions_today.like` by 1 only after the verify step confirms the flip; if it still says "Like", retry once with another scroll-into-view, otherwise log skip and don't increment.

After each action, persist state immediately via `command mv -f` (macOS aliases `mv` to `mv -i`):

```bash
jq --arg now "$NOW_ISO" --argjson plus 1 \
   ".instagram.last_run_iso = \$now | .instagram.actions_today.<ACTION> += \$plus" \
   "$STATE" > /tmp/engagement-state.json.tmp && command mv -f /tmp/engagement-state.json.tmp "$STATE"
```

## Step 6: Run log

`~/.social-skills/logs/warm/instagram-default-<timestamp>.json` — same shape as `/x-warm`'s log. Record the post author and handle for each `like`.

## Step 7: Report

One line: actions executed, today's total, what's left in the daily budget.

**Do not close the IG tab.**

## Failure modes

- **No Like buttons in snapshot** (e.g. you landed on Stories not feed): `agent-browser open https://www.instagram.com/` to force-route to the home feed, re-snapshot.
- **Already-liked posts only** (every visible Like is actually "Unlike"): scroll once and re-snapshot.
- **Story / Reels promo overlay**: dismiss any "Watch Reels" / "See Stories" prompt before snapshotting (usually a small "Not now" or `X` close button).
- **Shell is zsh**: `arr=($var)` does NOT word-split — use `shuf`. **macOS aliases `mv` to `mv -i`**: always use `command mv -f`.
- **IG is the strictest** about bot patterns: keep daily budget low (3-6) and DO NOT add follow / comment to this skill without observing how the existing scroll+like cadence is received first.
