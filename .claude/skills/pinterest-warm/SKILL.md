---
name: pinterest-warm
description: Run a single warming pass on Pinterest (swiftbible) — scroll the home feed, save 1-3 pins, react (heart) on 1-2, optionally follow one creator. Reads cadence from config/engagement-schedule.json and respects the daily budget + min-gap stored in ~/.social-agents/state/engagement-state.json. Use when the user says "warm pinterest", "engage on pinterest", or runs /pinterest-warm. Also called by /warm-all on a schedule.
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

Pinterest's action space (see config): `scroll`, `save`, `react`, `follow`. Each warm pass = **1 scroll up front (always), then 2–3 weighted engagement actions** (saves/reacts/follows). 2026-05-05 user feedback: warm passes should land 2–3 engagement actions per fire, not 0–1.

```bash
ENG_COUNT=$(( (RANDOM % 2) + 2 ))   # 2 or 3

# Weighted bag of ENGAGEMENT actions only (no scroll, no comment).
# Default save:4 react:3 follow:1.
ENG_BAG=()
for action in save react follow; do
  WEIGHT=$(jq -r ".platforms.pinterest.actions.$action.weight // 0" "$CFG")
  for _ in $(seq 1 "$WEIGHT"); do ENG_BAG+=("$action"); done
done

PICKS=("scroll")
for _ in $(seq 1 "$ENG_COUNT"); do
  PICKS+=("${ENG_BAG[$((RANDOM % ${#ENG_BAG[@]}))]}")
done

# Comment add-on: ALWAYS 1 + 50% chance of a 2nd. Outside the engagement bag —
# ride a separate cadence so comments stay rare AND deterministic per pass.
# Target: 1-2 Pinterest comments/day (Pinterest is picked ~1 of 3 cron fires).
PICKS+=("comment")
[ $((RANDOM % 100)) -lt 50 ] && PICKS+=("comment")

echo "Planned actions: ${PICKS[*]}"
```

**Per-action caps still apply.** `save` has max_per_run=4 so 2-3 saves are fine; `react` max_per_run=3 same; `follow` has max_per_run=1, so if it's drawn twice, drop the duplicate and replace with `save` or `react`. `comment` has max_per_run=2.

## Step 4: Switch to Pinterest tab, ensure home feed

```bash
# Switch to the Pinterest tab via curl-based discovery (NEVER `agent-browser
# tab list` — auto-spawn risk). Helper does find + switch + URL-verify +
# tab-new fallback in one step. See feedback_no_agent_browser_in_cron_guard.md.
bash scripts/switch_to_platform_tab.sh "pinterest.com" "https://www.pinterest.com/"
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

The home feed shows pins as `button "Pin card"` elements. Save buttons are NOT in the DOM until you click into the pin detail. The reliable flow is **pick a pin URL via DOM scan → navigate → save from detail → navigate back**.

**Topic filter (mandatory, set 2026-05-06)**: NEVER save a random pin. Pinterest's home feed mixes commerce / lifestyle / off-brand content. Pick a pin whose visible title/description matches the brand voice (Christian content for swiftbible). Pre-fetch each candidate's metadata via `/json/list`-style scraping is overkill — instead, navigate to a candidate, check title/heading text against the keyword regex, save if match, otherwise back to feed and try a different pin. Try at most 5 candidates before skipping the save action.

```bash
# 1. Pull candidate pin URLs from the home feed
CANDIDATES=$(agent-browser eval "Array.from(document.querySelectorAll('a[href*=\"/pin/\"]')).slice(0,12).map(a=>a.href.match(/\\/pin\\/[0-9]+/)?.[0]).filter(Boolean)" 2>&1 | tail -20 | grep '/pin/' | tr -d '"', | sort -u)

CHOSEN_PIN=""
for cand in $(echo "$CANDIDATES" | shuf | head -5); do
  agent-browser open "https://www.pinterest.com${cand}/"
  agent-browser wait --load networkidle
  agent-browser wait $(bash scripts/jitter.sh 1500 3000)
  # Brand filter: check pin title + description for religious keywords
  ON_BRAND=$(agent-browser eval "(()=>{const re=/\\b(bible|jesus|christ|god|gospel|scripture|verse|psalm|prayer|faith|amen|lord|holy|blessed|salvation|cross|kingdom|grace|saved|worship|devotion)\\b/i;return re.test(document.body.innerText||'')?'yes':'no'})()" 2>&1 | tail -1 | tr -d '"')
  if [ "$ON_BRAND" = "yes" ]; then
    CHOSEN_PIN="$cand"
    break
  fi
  echo "skipping $cand (not Bible-themed)"
done

if [ -z "$CHOSEN_PIN" ]; then
  echo "no Bible-themed pin in 5 candidates; skipping save action"
  # fall through to next planned action
else
  # 2. Find Save button on detail page (typically @e34) — re-snapshot
  agent-browser snapshot -i 2>&1 | grep -E '"Save".*\[ref=' | head -3
  agent-browser click "@<SAVE_REF>"
  agent-browser wait $(bash scripts/jitter.sh 2000 5000)
  # A "Pin Saved" toast and an "Undo Saved Pin" button confirm the save.

  # 3. Optionally pick a specific board: click "Select a board to save to: <X>" (@e33),
  #    pick from the dropdown that opens, THEN click Save.
  #    For warming, accepting the default (usually "Profile") is fine.

  # 4. Navigate back to feed for next action
  agent-browser open https://www.pinterest.com/
  agent-browser wait --load networkidle
  agent-browser wait $(bash scripts/jitter.sh 1000 2000)
fi
```

Increment `state.pinterest.actions_today.save` by 1 only on a successful save (skip increment if the action was filtered out).

### react (the heart / love reaction — Pinterest's closest analog to a "like")

Pinterest exposes a heart-shaped reaction button on the pin detail page. Tapping it gives a positive engagement signal (similar to an IG/X like) without the friction of saving (no board picker). **Topic filter applies** — same brand-relevance rule as `save`. Reach a pin detail page, verify Bible content, react.

**First-discovery 2026-05-06**: Pinterest's React button is a **single-tap toggle**, NOT a popover. `aria-pressed` flips `false → true` on first click — no reaction picker opens. Skip the post-click picker step that earlier versions of this skill described.

```bash
# 1. Pick + navigate + brand-filter (same loop as save)
CANDIDATES=$(agent-browser eval "Array.from(document.querySelectorAll('a[href*=\"/pin/\"]')).slice(0,12).map(a=>a.href.match(/\\/pin\\/[0-9]+/)?.[0]).filter(Boolean)" 2>&1 | tail -20 | grep '/pin/' | tr -d '"', | sort -u)

CHOSEN_PIN=""
for cand in $(echo "$CANDIDATES" | shuf | head -5); do
  agent-browser open "https://www.pinterest.com${cand}/"
  agent-browser wait --load networkidle
  agent-browser wait $(bash scripts/jitter.sh 1500 3000)
  ON_BRAND=$(agent-browser eval "(()=>{const re=/\\b(bible|jesus|christ|god|gospel|scripture|verse|psalm|prayer|faith|amen|lord|holy|blessed|salvation|cross|kingdom|grace|saved|worship|devotion)\\b/i;return re.test(document.body.innerText||'')?'yes':'no'})()" 2>&1 | tail -1 | tr -d '"')
  if [ "$ON_BRAND" = "yes" ]; then
    CHOSEN_PIN="$cand"
    break
  fi
done

if [ -z "$CHOSEN_PIN" ]; then
  echo "no Bible-themed pin in 5 candidates; skipping react action"
else
  # 2. Find the heart/react button. Snapshot first to discover its ref.
  #    Pinterest labels this control with aria-labels like "React to Pin",
  #    "Add reaction", or just a heart icon — search defensively.
  agent-browser snapshot -i 2>&1 | grep -iE '(react|heart|love).*ref' | head -5

  # 3. Click the react button (single-tap toggle — no picker opens).
  agent-browser click "@<REACT_REF>"
  agent-browser wait $(bash scripts/jitter.sh 1500 3000)

  # 4. Verify aria-pressed flipped from 'false' → 'true' on the button.

  # 5. Navigate back to the feed for the next action
  agent-browser open https://www.pinterest.com/
  agent-browser wait --load networkidle
  agent-browser wait $(bash scripts/jitter.sh 1000 2000)
fi
```

Increment `state.pinterest.actions_today.react` by 1.

**Already-reacted handling**: if the button's aria-label reads "Reacted" / shows the user's existing reaction, skip — don't toggle off (that'd register as a NEGATIVE engagement signal). Pick a different pin and retry, or fall through to the next planned action.

**First-discovery note (2026-05-05)**: the exact React button selector hasn't been pinned in our run logs yet. The first execution should snapshot the pin detail page broadly (`agent-browser snapshot -i 2>&1 | head -80`) and capture the actual `@ref` for the React button into the run log so future runs can update this section with the canonical selector.

### comment (added 2026-05-05 — corpus + per-char typing)

Comments ride the strictest pipeline of any warming action because *what* you say is part of the bot signature, not just *that* you engaged. NEVER deviate from these rules.

```bash
TOUCHED_PINS=()   # within-run set; populated by save/react execution above
COMMENT_HISTORY=~/.social-agents/state/comment-history.json
CORPUS=config/comment-corpus.json
TYPE_HUMAN=scripts/type_human.sh

# --- Step 1: pick a target pin from the home feed ---
# Must NOT be in TOUCHED_PINS (the one-engagement-per-target rule), must NOT have
# the same target_url already in comment-history.json (no double-commenting ever),
# must NOT be authored by us. We try up to 5 candidates before giving up the action.
agent-browser open https://www.pinterest.com/
agent-browser wait --load networkidle
agent-browser wait $(bash scripts/jitter.sh 1500 3000)

CANDIDATES=$(agent-browser eval "Array.from(document.querySelectorAll('a[href*=\"/pin/\"]')).slice(0,20).map(a=>a.href.match(/\\/pin\\/[0-9]+/)?.[0]).filter(Boolean)" 2>&1 | tail -30 | grep '/pin/' | tr -d '"', | sort -u)

CHOSEN_PIN=""
for cand in $(echo "$CANDIDATES" | shuf | head -10); do
  PIN_ID="${cand##*/}"
  TARGET_URL="https://www.pinterest.com${cand}/"

  # Skip if we already touched this pin this run
  for touched in "${TOUCHED_PINS[@]}"; do [ "$touched" = "$PIN_ID" ] && continue 2; done

  # Skip if we ever commented on this URL before
  if jq -e --arg url "$TARGET_URL" '.entries[] | select(.target_url == $url)' "$COMMENT_HISTORY" >/dev/null 2>&1; then
    continue
  fi

  CHOSEN_PIN="$cand"
  break
done

[ -z "$CHOSEN_PIN" ] && { echo "no eligible pin for comment; skipping"; continue; }

# --- Step 2: navigate to the pin, screen for prompt-style content, read author handle ---
agent-browser open "https://www.pinterest.com${CHOSEN_PIN}/"
agent-browser wait --load networkidle
agent-browser wait $(bash scripts/jitter.sh 2000 4000)

# Skip targets that ask for a specific reply word. Generic corpus phrases land as
# obviously-bot when the post says "reply with amen" / "comment AMEN below" /
# "type 11:11 to manifest" — set 2026-05-05 after first X test got caught by
# exactly this pattern.
PROMPT_HIT=$(agent-browser eval "(()=>{const t=document.body.innerText||'';const re=/(reply with|comment\\s+[\"']?[A-Za-z]{2,12}[\"']?\\s+below|type\\s+[\"']?[A-Za-z]{2,12}[\"']?|say\\s+.{1,20}\\s+below)/i;return re.test(t)?'PROMPT_DETECTED':'ok'})()" 2>&1 | tail -1 | tr -d '"')
if [ "$PROMPT_HIT" = "PROMPT_DETECTED" ]; then
  echo "skipping — pin contains a reply-prompt pattern; corpus phrase would look off"
  continue
fi

# Author detection on Pinterest is selector-fragile. Best effort: try several
# data-test-id patterns; fall back to "unknown" and proceed (Pinterest is
# lenient enough that the 30-day author cooldown is nice-to-have, not critical).
AUTHOR=$(agent-browser eval "(()=>{const sels=['[data-test-id=\"creator-card-name\"]','[data-test-id=\"closeup-creator-name\"]','[data-test-id=\"creator-handle\"]','a[data-test-id=\"creator-profile-name\"]'];for(const s of sels){const e=document.querySelector(s);if(e&&e.textContent.trim()){return e.textContent.trim().slice(0,40)}}return 'unknown'})()" 2>&1 | tail -1 | tr -d '"')

# Skip if author handle includes 'bible' or 'swiftbible' (might be us / parody)
if echo "$AUTHOR" | grep -qiE '(bible|swiftbible)'; then
  echo "skipping comment — author '$AUTHOR' matches bible/swiftbible filter"
  continue
fi

# Skip if we commented on this author within author_repeat_cooldown_days (30)
if [ "$AUTHOR" != "unknown" ]; then
  CUTOFF=$(date -u -v -30d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%SZ)
  if jq -e --arg a "$AUTHOR" --arg c "$CUTOFF" '.entries[] | select(.target_author_handle == $a and .ts > $c)' "$COMMENT_HISTORY" >/dev/null 2>&1; then
    echo "skipping — author $AUTHOR commented within 30 days"
    continue
  fi
fi

# --- Step 3: pick a phrase honoring the 7-day per-platform repeat rule ---
CUTOFF7=$(date -u -v -7d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ)
RECENT_PHRASES=$(jq -r --arg c "$CUTOFF7" '.entries[] | select(.platform=="pinterest" and .ts > $c) | .phrase' "$COMMENT_HISTORY")

# Default to universal category. (TODO: detect post theme via title/description and
# pick from scripture_response / testimony_response / teaching_response when matching.)
PHRASE=""
for try in $(seq 1 10); do
  CAND=$(jq -r '.categories.universal[]' "$CORPUS" | shuf -n 1)
  if ! echo "$RECENT_PHRASES" | grep -qxF "$CAND"; then
    PHRASE="$CAND"
    break
  fi
done

[ -z "$PHRASE" ] && { echo "couldn't find an unused phrase in 10 tries — universal pool exhausted? skipping"; continue; }
echo "Comment plan: phrase=\"$PHRASE\" target=$CHOSEN_PIN author=$AUTHOR"

# --- Step 4: open comment box, type via type_human.sh, submit ---
# The comment combobox has aria-label "Add a comment". On the pin detail page,
# scrolling it into view makes it findable in snapshot.
agent-browser snapshot -i 2>&1 | grep -E '"Add a comment".*ref' | head -1
COMBOBOX_REF=$(agent-browser snapshot -i 2>&1 | grep -E 'combobox "Add a comment".*ref=' | grep -oE 'ref=e[0-9]+' | head -1 | cut -d= -f2)
[ -z "$COMBOBOX_REF" ] && { echo "no comment combobox found on this pin — skip"; continue; }

agent-browser scrollintoview "@$COMBOBOX_REF"
agent-browser wait $(bash scripts/jitter.sh 600 1200)
agent-browser click "@$COMBOBOX_REF"
agent-browser wait $(bash scripts/jitter.sh 400 900)

# Verify the contenteditable is focused before typing — without focus, type_human.sh
# fires keystrokes into nothing.
FOCUSED=$(agent-browser eval "document.activeElement?.getAttribute('aria-label') || ''" 2>&1 | tail -1 | tr -d '"')
[ "$FOCUSED" != "Add a comment" ] && { echo "focus didn't land on Add a comment (got: $FOCUSED) — skip"; continue; }

bash "$TYPE_HUMAN" "$PHRASE"
agent-browser wait $(bash scripts/jitter.sh 800 1500)

# --- Step 5: submit via the Post button ---
POST_REF=$(agent-browser snapshot -i 2>&1 | grep -E '"Post".*ref=' | grep -oE 'ref=e[0-9]+' | head -1 | cut -d= -f2)
[ -z "$POST_REF" ] && { echo "no Post button found — skip"; continue; }
agent-browser wait $(bash scripts/jitter.sh 1500 3000)
agent-browser click "@$POST_REF"
agent-browser wait 4000

# Verify by querying for our just-posted comment in the comments list
LANDED=$(agent-browser eval "(()=>{const c=document.querySelectorAll('[data-test-id*=comment]');return Array.from(c).some(el=>(el.textContent||'').toLowerCase().includes('$PHRASE') && (el.textContent||'').toLowerCase().includes('just now'))})()" 2>&1 | tail -1)

if [ "$LANDED" = "true" ]; then
  # --- Step 6: append to comment-history.json ---
  TS_NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  PIN_ID="${CHOSEN_PIN##*/}"
  jq --arg ts "$TS_NOW" --arg phrase "$PHRASE" --arg url "https://www.pinterest.com${CHOSEN_PIN}/" --arg pid "$PIN_ID" --arg author "$AUTHOR" \
     '.entries += [{"ts": $ts, "platform": "pinterest", "phrase": $phrase, "category": "universal", "target_url": $url, "target_pin_id": $pid, "target_author_handle": $author, "typing_method": "type_human.sh", "manual_test": false}]' \
     "$COMMENT_HISTORY" > /tmp/ch.tmp && command mv -f /tmp/ch.tmp "$COMMENT_HISTORY"
  TOUCHED_PINS+=("$PIN_ID")
  echo "comment landed: \"$PHRASE\" on $CHOSEN_PIN"
else
  echo "comment did NOT land — $PHRASE not found in comments list. skip increment."
fi

# Navigate back to feed for next action
agent-browser open https://www.pinterest.com/
agent-browser wait --load networkidle
agent-browser wait $(bash scripts/jitter.sh 1000 2000)
```

Increment `state.pinterest.actions_today.comment` by 1 only after `LANDED=true`.

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
