---
name: post-daily-devotional
description: Capture the iOS simulator's daily devotional, draft platform-tailored captions, and fan out to Instagram (swiftbible) + X (@swift_bible) + Pinterest (swiftbible). Skips LinkedIn (LinkedIn = feature posts only). Use when the user says "post the devotional", "publish today's devotional", or runs /post-daily-devotional. Cron-fired daily at 12:00 local.
disable-model-invocation: true
allowed-tools: Bash(xcrun simctl*) Bash(agent-browser *) Bash(test *) Bash(date *) Bash(ls *) Bash(cat *) Bash(mkdir *) Bash(cp *) Read(*) Write(*) Skill(instagram-post *) Skill(x-post *) Skill(pinterest-post *)
---

# Post today's daily devotional to IG + X + Pinterest

Default account: `swiftbible` (override via `$SOCIAL_AGENTS_IG_ACCOUNT`).
Skips LinkedIn — that channel is reserved for feature ships, not daily content.

## Step 1: Verify simulator booted

```!
xcrun simctl list devices | grep -q '(Booted)' && echo "ok" || echo "NO BOOTED SIMULATOR"
```

Abort if not booted.

## Step 2: Capture + pad

```!
DATE=$(date +%Y-%m-%d)
RAW="/tmp/daily-devotional-${DATE}.png"
PADDED="/tmp/daily-devotional-${DATE}-4x5.jpg"
xcrun simctl io booted screenshot "$RAW"
bash scripts/pad_ios_screenshot.sh "$RAW" "$PADDED" edge
ls -lh "$RAW" "$PADDED"
```

`$RAW` is the original tall screenshot (good for Pinterest, which loves tall content). `$PADDED` is 4:5 (required for IG, used for X for consistency).

## Step 3: Read the screenshot to extract today's content

Use the `Read` tool on `$RAW` so you can see the page. Identify:

- **Book + verse reference** (e.g. "James 2:12", "Psalm 23:1-3")
- **Verse text** (the green-italic block)
- **Theme** — a short phrase you'd put on a poster (e.g. "The Law of Liberty", "The Lord is my Shepherd")
- **Brief reflection** (1-2 sentences from the body — usually the first paragraph after the verse)

Write these to a tiny JSON for downstream use:

```bash
cat > /tmp/daily-devotional-content.json <<JSON
{
  "date": "${DATE}",
  "reference": "<book + verse>",
  "theme": "<short theme phrase>",
  "verse_text": "<verse text in quotes>",
  "reflection": "<1-2 sentence summary>"
}
JSON
```

## Step 4: Draft platform-tailored captions

### Instagram (long, descriptive)

Honor `~/.social-agents/daily-devotional-caption.txt` if present (manual override). Otherwise auto-generate to `/tmp/dd-ig-caption.txt`:

```
Today's reading from the Swift Bible app — <reference>:

"<verse text>"

<reflection — full 1-2 sentences>

✦ New devotional every day at noon.

#DailyDevotional #Bible #ChristianApp #Faith #SwiftBible
```

### X / Twitter (≤280 chars, single tweet)

Write `/tmp/dd-x-thread.json`:

```json
[{
  "text": "Today's reading from the Swift Bible app — <reference>:\n\n\"<verse text>\"\n\n<reflection — TIGHT, ≤90 chars>\n\n#DailyDevotional #Bible",
  "media": ["<padded screenshot path>"]
}]
```

Hard 280-char limit; trim the reflection if needed. Verify with `jq -r '.[].text' /tmp/dd-x-thread.json | wc -c` (cap at 281 including trailing newline).

### Pinterest (search-friendly title + description)

Write `/tmp/dd-pinterest.json`:

```json
{
  "media": "<RAW path — tall, no padding>",
  "title": "<reference> — <theme> | Daily Bible Devotional",
  "description": "Today's devotional from the Swift Bible app. \"<verse text>\" (<reference>) <reflection>. New devotional every day at noon. ✦",
  "board": "Daily Devotionals",
  "link": "https://am2.biz/swiftbible"
}
```

Title ≤100 chars. Description ≤500 chars.

## Step 5: Fan out

Sequentially invoke each platform skill. **Continue on failure** — log the error and move to the next platform. The full devotional shouldn't be blocked by a single platform issue.

```bash
# 1. Instagram (long-running first because it's the most reliable)
/instagram-post swiftbible "$PADDED" "$(cat /tmp/dd-ig-caption.txt)"
IG_OUTCOME=$?

# 2. X
/x-post /tmp/dd-x-thread.json
X_OUTCOME=$?

# 3. Pinterest
/pinterest-post /tmp/dd-pinterest.json
P_OUTCOME=$?
```

In practice, invoke each via the Skill tool so the agent can read each skill's run log.

## Step 6: Roll-up run log

Write `~/.social-agents/logs/daily-devotional-fanout-<date>.json`:

```json
{
  "date": "...",
  "screenshot_raw": "...",
  "screenshot_padded": "...",
  "content_extracted": { ... },
  "instagram": { "outcome": "...", "run_log": "..." },
  "x":         { "outcome": "...", "run_log": "..." },
  "pinterest": { "outcome": "...", "run_log": "..." }
}
```

## Step 7: Report

Per-platform outcome with permalinks if available. If any platform reported a STATE MISSING / login-required error, tell the user to run the relevant `/<platform>-login` skill.

## Cron

```cron
0 12 * * * /bin/bash /Users/vanities/git/work/me/social-agents/scripts/daily_devotional.sh
```

The `daily_devotional.sh` wrapper just `cd`s into the repo and runs `claude --print "/post-daily-devotional"`. Logs go to `~/.social-agents/logs/cron/<date>.log`.

## Failure modes

- **Simulator not booted**: skill aborts at step 1; cron run fails clean.
- **One platform fails, others should still post**: the skill explicitly continues on failure; partial success is better than no post.
- **Caption file missing for IG override**: fall back to auto-generated caption (no error).
- **X graduated-access modal after first post**: harmless; `/x-post` already handles dismissal.
