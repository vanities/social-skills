---
name: post-daily-content
description: Capture today's content from an iOS simulator (or any source you wire up), draft platform-tailored captions, and fan out to your enabled platforms. Sample composite that's intended to be copied + edited per brand. Use when the user says "post today's content", "publish daily", or runs /post-daily-content.
allowed-tools: Bash(xcrun simctl*) Bash(agent-browser *) Bash(bash *) Bash(test *) Bash(date *) Bash(ls *) Bash(cat *) Bash(jq *) Bash(mkdir *) Bash(cp *) Bash(sleep *) Read(*) Write(*) Skill(instagram-post *) Skill(x-post *) Skill(pinterest-post *) Skill(linkedin-post *) mcp__XcodeBuildMCP__tap mcp__XcodeBuildMCP__session_set_defaults mcp__XcodeBuildMCP__snapshot_ui
---

# Post today's content to enabled platforms

> **Sample skill — copy + edit.** This file lives in `personal.example/skills/post-daily-content/` and is intended to be copied to `.claude/skills/post-daily-content/` (gitignored) and customized for your brand. The shape — capture → pad → extract → caption per platform → fan-out → log — is reusable; the iOS-app-driving + content-extraction steps are domain-specific.

Reads `config/brand.json` for handles, default boards, and brand metadata.

## Step 0: Load brand config

```bash
BRAND=config/brand.json
test -f "$BRAND" || { echo "MISSING $BRAND — copy from brand.example.json and fill in your values"; exit 1; }

IG_ACCOUNT=$(jq -r '.instagram.default_account' "$BRAND")
X_HANDLE=$(jq -r '.x.default_handle' "$BRAND")
PINTEREST_BOARD=$(jq -r '.pinterest.default_board' "$BRAND")
BRAND_NAME=$(jq -r '.brand.name' "$BRAND")
BRAND_URL=$(jq -r '.brand.url' "$BRAND")
```

## Step 1: Verify simulator booted (if your flow drives an iOS app)

```!
xcrun simctl list devices | grep -q '(Booted)' && echo "ok" || echo "NO BOOTED SIMULATOR — abort"
```

If your daily content comes from somewhere else (RSS, a CMS, a static file, an LLM-generated draft, etc.), replace this whole block.

## Step 2: Launch your iOS app and navigate to the content view

Replace `com.example.yourapp` with your bundle identifier and update the tap targets for your app's UI. SwiftUI tab bars usually expose `Tab Bar` group with empty `children` — fall back to coordinate taps.

```bash
xcrun simctl launch booted com.example.yourapp
sleep 3   # SpringBoard handoff + first-frame render
```

Probe + dismiss any onboarding / donation modal that might be in the way:

```
mcp__XcodeBuildMCP__session_set_defaults({simulatorId: "<booted-udid>"})
mcp__XcodeBuildMCP__tap({label: "Not now"})   # safe to call; errors silently if absent
```

Tap the destination view. Coordinates below assume iPhone 17 (402pt wide); adjust for your device. The screenshot grabs the full screen so framing matters here.

```
mcp__XcodeBuildMCP__tap({x: 170, y: 825})
sleep 2
```

## Step 3: Capture + pad

```bash
DATE=$(date +%Y-%m-%d)
RAW="/tmp/daily-content-${DATE}.png"
PADDED="/tmp/daily-content-${DATE}-4x5.jpg"
xcrun simctl io booted screenshot "$RAW"
# 4:5 padding for IG feed. Modes: edge | blur | random | #RRGGBB | gradient |
# bloom | sparkle | cosmic | divine | holy | lovely | dream | surprise.
# `surprise` rolls one of the fancy decorated modes (great for visually-rich
# content; subdued modes like `edge` or `blur` work for text-heavy screens).
bash scripts/pad_ios_screenshot.sh "$RAW" "$PADDED" surprise
ls -lh "$RAW" "$PADDED"
```

`$RAW` is the original tall screenshot — best for Pinterest (which prefers vertical 2:3 / taller content). `$PADDED` is 4:5 — required for IG, used for X for consistency.

## Step 4: Extract today's content

Use the `Read` tool on `$RAW` to see the screenshot. Identify whatever fields make sense for your content (verse + reflection, tip + summary, headline + body, etc.). Write to a tiny JSON for downstream steps:

```bash
cat > /tmp/daily-content.json <<JSON
{
  "date": "${DATE}",
  "title": "<short title>",
  "body":  "<1-2 sentence summary>",
  "hashtags": ["#YourBrand", "#YourTopic"]
}
JSON
```

## Step 5: Draft platform-tailored captions

Each platform has a different audience and constraint set. Write one draft per platform; let the user review later if you want a confirmation step.

### Instagram (long, descriptive)

```bash
cat > /tmp/dc-ig-caption.txt <<CAPTION
Today from ${BRAND_NAME} — <title>:

<body>

✦ New every day.

#YourBrand #YourTopic #ContentType
CAPTION
```

### X / Twitter (≤280 chars, single tweet or reply chain)

```bash
cat > /tmp/dc-x-thread.json <<JSON
[{
  "text": "Today from ${BRAND_NAME} — <title>:\n\n<body — TIGHT, ≤90 chars>\n\n#YourBrand",
  "media": ["${PADDED}"]
}]
JSON
```

Verify the tweet length: `jq -r '.[].text' /tmp/dc-x-thread.json | wc -c` ≤ 281.

### Pinterest (search-friendly title + description)

Pinterest is a **search engine, not a feed**. Title and description should read like search-result content, not a status update.

```bash
cat > /tmp/dc-pinterest.json <<JSON
{
  "media": "${RAW}",
  "title": "<title> — ${BRAND_NAME}",
  "description": "Today from ${BRAND_NAME}. <body> Visit ${BRAND_URL}.",
  "board": "${PINTEREST_BOARD}",
  "link": "${BRAND_URL}"
}
JSON
```

Title ≤100 chars. Description ≤500 chars. Front-load keywords your audience would actually google.

## Step 6: Fan out

Sequentially invoke each platform skill. **Continue on failure** — log the error and move to the next platform.

```bash
# Instagram
/instagram-post "$IG_ACCOUNT" "$PADDED" "$(cat /tmp/dc-ig-caption.txt)"

# X — explicit handle prevents posting to the wrong account if the browser
# was left signed into a different X identity.
/x-post "$X_HANDLE" /tmp/dc-x-thread.json

# Pinterest
/pinterest-post /tmp/dc-pinterest.json
```

Skip LinkedIn here if your daily content isn't worth posting to a professional / company-page audience (most "daily" content isn't). Reserve LinkedIn for `/feature-post` style ships.

## Step 7: Roll-up run log

Write `~/.social-skills/logs/daily-content-fanout-<date>.json` with per-platform outcomes + run-log paths.

## Step 8: Report

Per-platform outcome with permalinks if available. If any platform reported a STATE MISSING / login-required error, tell the user to run the relevant `/<platform>-login` skill.

## Cron

```cron
# Match what's in personal.example/scripts/daily_content.sh
0 12 * * * /bin/bash /absolute/path/to/social-skills/scripts/daily_content.sh
```

The wrapper handles browser/sim health checks before invoking this skill.
