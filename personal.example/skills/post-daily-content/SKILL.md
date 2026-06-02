---
name: post-daily-content
description: Capture today's content from an iOS simulator (or any source you wire up), draft platform-tailored captions, and fan out to your enabled platforms. Sample composite that's intended to be copied + edited per brand. Use when the user says "post today's content", "publish daily", or runs /post-daily-content.
allowed-tools: Bash(xcrun simctl*) Bash(agent-browser *) Bash(bash *) Bash(test *) Bash(date *) Bash(ls *) Bash(cat *) Bash(jq *) Bash(mkdir *) Bash(cp *) Bash(sleep *) Read(*) Write(*) Skill(instagram-post *) Skill(x-post *) Skill(pinterest-post *) Skill(linkedin-post *) mcp__XcodeBuildMCP__tap mcp__XcodeBuildMCP__session_set_defaults mcp__XcodeBuildMCP__snapshot_ui
---

# Post today's content to enabled platforms

> **Sample skill — copy + edit.** This file lives in `personal.example/skills/post-daily-content/` and is intended to be copied to `skills/post-daily-content/` (gitignored; surfaced to Claude through `.claude/skills`) and customized for your brand. The shape — capture → pad → extract → caption per platform → fan-out → log — is reusable; the iOS-app-driving + content-extraction steps are domain-specific.

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

## Step 1: Resolve target simulator UDID (if your flow drives an iOS app)

Pin to a specific UDID instead of `booted` — when multiple sims are booted (Xcode often leaves duplicates alive after device-pane changes), `simctl ... booted` errors with ambiguity and silently hangs the skill. Edit the preference list below to match the sims you actually use; `xcrun simctl list devices` shows what's available.

Uses `grep`/`sed` regex extraction rather than `awk -v var=$NAME` — the harness's `!`-block bash exec drops shell vars before they reach awk's `-v` flag (the var arrives empty), so the awk-based version silently fell through to the fallback branch.

```!
SIM_UDID=""
BOOTED=$(xcrun simctl list devices | grep "(Booted)" || true)
for NAME in "iPhone 17 Pro" "iPhone 17"; do
  LINE=$(echo "$BOOTED" | grep -E "^[[:space:]]+${NAME} \(" | head -1)
  if [ -n "$LINE" ]; then
    SIM_UDID=$(echo "$LINE" | grep -oE '[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}' | head -1)
    [ -n "$SIM_UDID" ] && { echo "Resolved: $NAME ($SIM_UDID)"; break; }
  fi
done
if [ -z "$SIM_UDID" ]; then
  SIM_UDID=$(echo "$BOOTED" | grep -oE '[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}' | head -1)
  [ -n "$SIM_UDID" ] && echo "Fallback (first booted): $SIM_UDID"
fi
[ -n "$SIM_UDID" ] || { echo "NO BOOTED SIMULATOR — abort"; exit 1; }
```

If your daily content comes from somewhere else (RSS, a CMS, a static file, an LLM-generated draft, etc.), replace this whole block.

## Step 2: Launch your iOS app and navigate to the content view

Replace `com.example.yourapp` with your bundle identifier and `yourapp://...` with a deep-link your app registers (check your `Info.plist` `CFBundleURLSchemes`).

```bash
xcrun simctl launch "$SIM_UDID" com.example.yourapp
# Wait for your launch splash to fully clear before deep-linking — openurl
# silently no-ops if it fires during the splash animation.
sleep 8
```

Probe + dismiss any onboarding / donation modal that might be in the way:

```
mcp__XcodeBuildMCP__session_set_defaults({simulatorId: "<value of $SIM_UDID printed by Step 1>"})
mcp__XcodeBuildMCP__tap({label: "Not now"})   # safe to call; errors silently if absent
```

**Navigate by URL-scheme deep-link, NOT by tapping the tab bar.** SwiftUI tab bars expose a `Tab Bar` group with empty `children`, so XcodeBuildMCP can't tap a tab by label, and a coordinate `tap({x, y})` needs **idb** — which a headless cron host (e.g. a Mac Mini) typically lacks, where tapping the tab bar can flail for many minutes. If your app registers a deep-link to the destination view, jump straight there — no idb, accessibility, or on-screen window required:

```bash
# PRIMARY: deep-link to the content view (define this route in your app).
xcrun simctl openurl "$SIM_UDID" yourapp://content
sleep 3   # view transition
```

Verify before screenshotting:

```
mcp__XcodeBuildMCP__snapshot_ui({})   # confirm the content view is showing, not the splash
```

If it's still on the splash, the app wasn't ready when the URL fired — `sleep 3` and re-issue the `openurl` once.

**Fallback (idb-capable hosts only, e.g. an interactive Mac):** tap the destination tab by coordinate (iPhone 17 ≈ 402pt wide; adjust for your device), then `sleep 2`:

```
mcp__XcodeBuildMCP__tap({x: 170, y: 825})
sleep 2
```

## Step 3: Capture + pad

```bash
DATE=$(date +%Y-%m-%d)
RAW="/tmp/daily-content-${DATE}.png"
xcrun simctl io "$SIM_UDID" screenshot "$RAW"
ls -lh "$RAW"
```

`$RAW` is the original tall screenshot — best for Pinterest (which prefers vertical 2:3 / taller content). The 4:5 padded version comes after Step 4 (after we know the theme — see Step 4b).

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

## Step 4b: Pick a padding mode that fits the theme, then pad

`pad_ios_screenshot.sh` fills the side gaps when a tall iPhone screenshot is converted to 4:5 for IG. Decorated modes scatter SVG elements (hearts, crosses, sparkles, scripture words) into those gaps with a coloured gradient. **Choose deliberately based on what you extracted in Step 4 — do NOT default to `surprise` (random)**. A wrong vibe (e.g. pink hearts under content about danger or warning) reads as tone-deaf.

| Content theme / mood | Mode | Look |
|---|---|---|
| Love, grace, family, kindness, mothers | `mother` | Rose-pink hearts + "mom/mama/love/blessed/nurturing" |
| Fatherhood, leadership, strength, refuge, provider | `father` | Deep navy + golden crosses + "father/strong/refuge/provider/shepherd" |
| Romance, affection, tenderness | `lovely` | Hearts + "love/grace/joy/blessed/beloved" |
| Light, glory, praise, joy, victory | `divine` | Golden crosses + "amen/blessed/grace" |
| Worship, devotion, sacred space | `holy` | Divine + doves + Bibles |
| Hope, dreams, peace, rest, quiet | `dream` | Faded words over a soft blur |
| Awe, mystery, vastness, beauty | `cosmic` | Nebula orbs + sparkle dust |
| Wonder, celebration, sparkles | `sparkle` | Dense sparkles + light words |
| Renewal, growth, blooming | `bloom` | Petal-like orbs + warm gradient |
| Warning, evil, deception, judgment, darkness | `shadow` | Deep slate/black + dim crosses + cautionary words |
| Grief, mourning, lament, sorrow, hard seasons | `lament` | Cool slate-blue + dim orbs + "comfort/restore/hear/weep" |
| **Easter / Resurrection / cross / sacrifice** | `easter` | Sunrise gradient + golden crosses + "risen/alive/finished" |
| **Christmas / Advent / Nativity / Star of Bethlehem** | `christmas` | Night-sky → amber gradient + stars + "noel/joy/peace/savior" |
| **Pentecost / Holy Spirit / fire / boldness** | `pentecost` | Flame gradient + doves + "fire/spirit/breath/wind" |
| Generic / text-heavy / when nothing fits | `gradient`, `edge`, or `blur` | Subdued, no decorations |

**Calendar awareness**: prefer event modes near their dates even if the day's content doesn't lead with that theme — Easter week → `easter`, Advent (Dec 1-25) → `christmas`, Pentecost Sunday → `pentecost`.

Plain modes for non-Bible brands: `edge` (seamless extension), `blur` (Apple-style blurred background), `random` (curated palette colours), or a literal `#RRGGBB` hex.

```bash
PADDED="/tmp/daily-content-${DATE}-4x5.jpg"
# Replace <chosen-mode> with the one that fits.
MODE=<chosen-mode>
bash scripts/pad_ios_screenshot.sh "$RAW" "$PADDED" "$MODE"
ls -lh "$PADDED"
```

`$PADDED` is 4:5 — required for IG, used for X for consistency.

## Step 5: Draft platform-tailored captions

> **Drafting playbook**: Before writing copy, re-read [`docs/social-strategy.md`](../../../docs/social-strategy.md) — specifically the **Drafting checklist** (10 items) and the per-platform sections for the platforms you enabled. Walk the checklist explicitly while drafting (reply-bait question? DM-share framing? video qualifies for VQV? no slop signals?).

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
