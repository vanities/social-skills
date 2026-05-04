---
name: feature-post
description: Orchestrate a cross-platform launch post for an iOS app feature. Drives the iOS simulator to capture screenshots, pads them, drafts platform-tailored captions, gets user approval, then cross-posts to LinkedIn (AM2 LLC), Instagram (swiftbible), and X (swift_bible). Use when the user says "feature post X", "post about the new Y feature", or runs /feature-post.
disable-model-invocation: true
argument-hint: [feature-description] [platforms]
allowed-tools: Bash(*) Bash(agent-browser *) Bash(xcrun simctl *) Bash(jq *) Bash(date *) Bash(mkdir *) Bash(cp *) Bash(test *) Bash(ls *) Read(*) Write(*) Skill(linkedin-post *) Skill(instagram-post *) Skill(x-post *)
---

# Feature post — cross-platform launch from iOS simulator

`$1`: feature description (1–2 sentences). If empty, ask the user.
`$2`: comma-separated subset of `linkedin,instagram,x` (default: all three).

This skill composes:
- **XcodeBuildMCP** (tap, screenshot, snapshot_ui) — sim navigation + capture
- `scripts/pad_ios_screenshot.sh` — pads tall screenshots to 4:5
- `/linkedin-post 104970470 <media...> <caption>` — AM2 LLC company page
- `/instagram-post swiftbible <padded-media> <caption>` — swift_bible IG
- `/x-post <thread-json>` — @swift_bible reply chain

Defaults are baked for the Swift Bible app. Override platform target args (LinkedIn company id, IG account) inline if posting for a different brand.

## Step 1: Confirm the feature description

If `$1` is empty, ask:

> What feature shipped? Give me a 1–2 sentence description.

Save the description for use in caption drafting. Slugify it for the screenshot directory:

```bash
SLUG=$(echo "$DESC" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//' | cut -c1-40)
DATE=$(date +%Y-%m-%d)
SCREENSHOT_DIR=~/.social-agents/screenshots/feature-posts/${DATE}-${SLUG}
mkdir -p "$SCREENSHOT_DIR"
```

## Step 2: Capture screenshots

Verify XcodeBuildMCP is configured with `XCODEBUILDMCP_ENABLED_WORKFLOWS=simulator,device,debugging,ui-automation` (see CLAUDE.md "Known issues" if `tap`/`snapshot_ui` aren't surfaced). Confirm a simulator is booted.

Ask the user one question:

> Should I drive the simulator (you describe the screens), or do you want to navigate and tell me when to screenshot?

**Path A — agent drives the sim**: ask for the screen sequence ("More tab, then tap History"). For each screen:

1. `mcp__XcodeBuildMCP__snapshot_ui` to read the view hierarchy
2. Find the target element by AXLabel / coordinates (SwiftUI tab bars often expose `Tab Bar` with empty `children` — fall back to coordinate taps; tab centers ≈ 50/150/250/350 at y≈832 on iPhone 17)
3. `mcp__XcodeBuildMCP__tap` (label preferred, coordinates as fallback)
4. `mcp__XcodeBuildMCP__screenshot returnFormat=path` and copy the result to `$SCREENSHOT_DIR/0N-<screen-name>.jpg`

**Path B — user drives**: when the user types "now" / "screenshot", capture and save to `$SCREENSHOT_DIR/0N-<screen>.jpg`. Repeat until they say done.

Show each screenshot inline (Read tool) so the user can confirm framing before moving on.

## Step 3: Pad each screenshot to 4:5

```bash
for shot in $SCREENSHOT_DIR/*.jpg; do
  bash scripts/pad_ios_screenshot.sh "$shot" "${shot%.jpg}-4x5.jpg" edge
done
```

Use `edge` (seamless) by default. Suggest `blur` mode if the post is hero/aesthetic-leaning ("a polished album-art frame around the screenshot — want that style instead?").

## Step 4: Draft captions per platform

**LinkedIn (AM2 LLC, professional/builder tone)**:
- Hook: 1 sentence stating what shipped + why it matters
- Detail: 1–2 paragraphs on the user-facing change and the design choice
- Reflection: 1 sentence on the *why* behind the work
- 3–5 hashtags (`#iOSApp #IndieDev #SwiftUI` + content-specific)

**Instagram (swift_bible audience — Bible-app users)**:
- Same body as LinkedIn (or slightly tightened)
- IG-friendly hashtags: `#SwiftBible #BibleApp #ChristianApp` + content-specific (8 hashtags is fine)

**X (3-tweet reply chain on @swift_bible)**:
- T1 (hook, ≤280 chars, 1 image): "Shipped … today — <feature one-liner>"
- T2 (detail, ≤280 chars, 1 image): the user-facing experience
- T3 (closing, ≤280 chars, no media): the reflection + hashtags
- Or a single tweet if the feature is simple

Write the X thread to `/tmp/x-thread-${SLUG}.json` in the `[{text, media?}, ...]` format `/x-post` expects.

## Step 5: Show drafts and get approval

Lay all three drafts inline with character counts (X) and image attachments listed. Ask:

> Approve all three, change something, or skip a platform?

Wait for explicit approval before any posting.

## Step 6: Cross-post

Default order: LinkedIn → Instagram → X. (LinkedIn first because the AM2 LLC posts are the primary "company news" channel; X last because the reply chain is more clicks.)

For each enabled platform in `$2`:

- **LinkedIn**: `/linkedin-post 104970470 <padded-screenshot-1> [<padded-screenshot-2> ...] "<caption>"` — pass multiple media paths for a carousel.
- **Instagram**: `/instagram-post swiftbible <padded-screenshot-1> [<padded-screenshot-2> ...] "<caption>"` — same multi-file convention.
- **X**: `/x-post /tmp/x-thread-${SLUG}.json` — `/x-post` posts T0 standalone then replies through T1, T2, ...

Wait for each skill's run log before starting the next. If one fails, ask before continuing — the user may want to fix and re-run that platform only.

## Step 7: Report

Summarize per platform:
- Outcome (success / failed at step N)
- Live URL (LinkedIn post URL if available, Instagram permalink, X status URLs)
- Run log path
- Verification screenshot

Recommend any follow-ups: cross-post review, X graduated-access engagement (likes/follows from `@swift_bible` to push the account toward graduating out of soft-restriction).

**Do not close any browser tab.**
