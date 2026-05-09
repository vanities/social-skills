---
name: instagram-warm
description: Run a single warming pass on Instagram (swift_bible) — scroll the home feed, like 1-3 posts. Reads cadence from config/engagement-schedule.json and respects the daily budget + min-gap stored in ~/.social-skills/state/engagement-state.json. Use when the user says "warm instagram", "engage on ig", or runs /instagram-warm. Also called by /warm-all on a schedule.
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
# Switch to the IG tab via curl-based discovery (NEVER `agent-browser tab list` —
# it auto-spawns a fresh Chrome on CDP attach failure even when HTTP is healthy).
# The helper finds the tab via /json/list, switches via `agent-browser tab N`,
# verifies the URL, and falls back to `tab new` if the index was wrong.
# /json/list array order can drift from agent-browser's tab-bar indexing
# (caught 2026-05-06). See feedback_no_agent_browser_in_cron_guard.md.
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

**Critical**: agent-browser's snapshot @e refs for these "Like" buttons frequently fail to register a click — IG's React handler ignores synthesized clicks on elements that are off-screen. Use this pattern instead:

1. Find a Bible-related Like target via `querySelectorAll('article')` + caption regex (NOT random)
2. Skip ads (header contains "Sponsored" / "Promoted") and own posts (`@swift_bible`)
3. Walk up to the nearest `[role=button]` ancestor — that's the clickable
4. Mark it with a unique id via eval
5. **`scrollIntoView({block:'center'})` BEFORE clicking** — what made the live test pass after several no-ops
6. `agent-browser click "#<id>"` — triggers the React handler
7. Verify by checking the SVG's aria-label flipped to `Unlike`

**Topic filter (mandatory, set 2026-05-06)**: NEVER like a random feed post. The IG home feed is heavily algorithm-driven and serves ads + off-brand content. Hit 2026-05-06: random pick liked a Ford ad. User: "we don't need that. This is for Swift Bible, so it should only do Bible stuff." The eval below filters to posts whose visible text contains religious keywords AND skips Sponsored posts.

```bash
# Step 1-4: find a Bible-relevant, non-ad Like target and mark it
agent-browser eval "(()=>{
  const articles = Array.from(document.querySelectorAll('article'));
  const religiousRe = /\\b(bible|jesus|christ|god|gospel|scripture|verse|psalm|prayer|faith|amen|lord|holy|blessed|salvation|cross|kingdom|grace|saved|worship|devotion)\\b/i;
  const candidates = [];
  for (const a of articles) {
    const header = (a.querySelector('header')?.textContent || '').toLowerCase();
    if (header.includes('sponsored') || header.includes('promoted')) continue;     // skip ads
    if (header.includes('swift_bible')) continue;                                    // skip own posts
    const likeSvg = a.querySelector('svg[aria-label=\"Like\"]');                     // already-liked are 'Unlike' — implicitly skipped
    if (!likeSvg) continue;
    const text = (a.textContent || '');
    if (!religiousRe.test(text)) continue;                                           // topic filter
    candidates.push({ svg: likeSvg, sample: text.slice(0, 100).replace(/\\s+/g, ' ').trim() });
  }
  if (candidates.length === 0) return { ok: false, reason: 'no Bible-content unliked posts in current viewport' };
  const pick = candidates[Math.floor(Math.random() * candidates.length)];
  let e = pick.svg;
  while (e && e.getAttribute('role') !== 'button' && e.parentElement) e = e.parentElement;
  e.id = 'ig-like-target';
  return { ok: true, sample: pick.sample, candidate_count: candidates.length };
})()"
```

If the eval returns `ok: false`, scroll once and retry up to 2 times. If still no candidates, **skip the like action for this run** (don't fall through to a random pick — the topic filter is mandatory). Decrement the planned action count and continue with the rest of the run.

```bash
# Step 5: scroll into view (REQUIRED — without this the click silently fails)
agent-browser eval "document.querySelector('#ig-like-target')?.scrollIntoView({block:'center',behavior:'smooth'})"
agent-browser wait $(bash scripts/jitter.sh 1500 2500)

# Step 6: click
agent-browser click "#ig-like-target"
agent-browser wait $(bash scripts/jitter.sh 4000 10000)

# Step 7: verify — SVG aria-label should now read "Unlike"
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
