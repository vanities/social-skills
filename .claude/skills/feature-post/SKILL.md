---
name: feature-post
description: Orchestrate a cross-platform launch post for an iOS app feature. Drives the iOS simulator to capture screenshots / video, pads them, drafts platform-tailored captions (announcement-style for LinkedIn / IG / X; search-rewritten how-to for Pinterest), gets user approval, then cross-posts to enabled platforms. First arg is the feature description; second is optional brand slug; third is comma-separated platforms (default all). Use when the user says "feature post X", "post about the new Y feature", or runs /feature-post.
argument-hint: [feature-description] [brand-slug] [platforms]
allowed-tools: Bash(*) Bash(agent-browser *) Bash(xcrun simctl *) Bash(jq *) Bash(date *) Bash(mkdir *) Bash(cp *) Bash(test *) Bash(ls *) Read(*) Write(*) Skill(linkedin-post *) Skill(instagram-post *) Skill(x-post *) Skill(pinterest-post *)
---

# Feature post — cross-platform launch from iOS simulator

`$1`: feature description (1–2 sentences). If empty, ask the user.
`$2`: optional brand slug. Empty → uses `.default_brand` from `config/brand.json`.
`$3`: comma-separated subset of `linkedin,instagram,x,pinterest` (default: all four).

## Configuration (tune via `config/brand.json`)

| Bucket | brand.json key | Used for |
|---|---|---|
| **default_brand** | `default_brand` | Resolved when `$2` is empty. |
| **linkedin_company_id** | `org.linkedin_company_id` | First arg to `/linkedin-post`. If null → posts to your personal feed instead of a company page. |
| **instagram default_account** | `brands.<slug>.instagram.default_account` | First arg to `/instagram-post`. |
| **x default_handle** | `brands.<slug>.x.default_handle` | First arg to `/x-post` (the X account-switcher resolves the right session before composing). |
| **pinterest default_account / feature_board** | `brands.<slug>.pinterest.default_account`, `…feature_board` | Pinterest user + the board feature pins land in. `feature_board` is intentionally distinct from `default_board` — Pinterest's algorithm wants evergreen daily content separated from how-to / explainer content. |
| **brand metadata** | `brands.<slug>.brand.{name,url,voice}` | Caption drafting — name is referenced in caption boilerplate, url is the destination link auto-included in posts, voice tones the caption draft. |

This skill composes:
- **XcodeBuildMCP** (tap, screenshot, snapshot_ui) — sim navigation + capture
- `scripts/pad_ios_screenshot.sh` — pads tall screenshots to 4:5 (IG / LinkedIn / X)
- `scripts/pad_ios_video.sh` — pads tall video to 9:16 (IG Reels / LinkedIn / X video)
- `/linkedin-post`, `/instagram-post`, `/x-post`, `/pinterest-post` — platform skills

## Step 0: Resolve brand + load config

```bash
BRAND=config/brand.json
test -f "$BRAND" || { echo "MISSING $BRAND — copy from brand.example.json (see PERSONAL.md)"; exit 1; }

SLUG="${2:-$(jq -r '.default_brand // empty' "$BRAND")}"
[ -n "$SLUG" ] || { echo "MISSING brand slug — pass as 2nd arg or set .default_brand in $BRAND"; exit 1; }

LINKEDIN_TARGET=$(jq -r '.org.linkedin_company_id // "personal"' "$BRAND")
IG_ACCOUNT=$(jq -r ".brands.\"$SLUG\".instagram.default_account // empty" "$BRAND")
X_HANDLE=$(jq -r ".brands.\"$SLUG\".x.default_handle // empty" "$BRAND")
PIN_BOARD=$(jq -r ".brands.\"$SLUG\".pinterest.feature_board // empty" "$BRAND")
BRAND_NAME=$(jq -r ".brands.\"$SLUG\".brand.name // empty" "$BRAND")
BRAND_URL=$(jq -r ".brands.\"$SLUG\".brand.url // empty" "$BRAND")
BRAND_VOICE=$(jq -r ".brands.\"$SLUG\".brand.voice // empty" "$BRAND")

for v in IG_ACCOUNT X_HANDLE PIN_BOARD BRAND_NAME BRAND_URL; do
  [ -n "${!v}" ] || { echo "MISSING brand value: $v not found under brands.$SLUG in $BRAND"; exit 1; }
done

echo "[feature-post] brand=$SLUG ig=$IG_ACCOUNT x=@$X_HANDLE linkedin=$LINKEDIN_TARGET pinterest_board=$PIN_BOARD"
```

## Step 1: Confirm the feature description

If `$1` is empty, ask:

> What feature shipped? Give me a 1–2 sentence description.

Save the description for use in caption drafting. Slugify it for the screenshot directory:

```bash
SLUG_FILE=$(echo "$DESC" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//' | cut -c1-40)
DATE=$(date +%Y-%m-%d)
SCREENSHOT_DIR=~/.social-skills/screenshots/feature-posts/${DATE}-${SLUG_FILE}
mkdir -p "$SCREENSHOT_DIR"
```

## Step 2: Capture screenshots

Verify XcodeBuildMCP is configured with `XCODEBUILDMCP_ENABLED_WORKFLOWS=simulator,device,debugging,ui-automation` (see CLAUDE.md "Known issues" if `tap` / `snapshot_ui` aren't surfaced). Confirm a simulator is booted.

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

Use `edge` (seamless) by default. Suggest `blur` mode if the post is hero / aesthetic-leaning ("a polished album-art frame around the screenshot — want that style instead?").

## Step 4: Draft captions per platform

Use `$BRAND_VOICE` (from brand.json) to tone all four drafts. The shape below is structural — what fields each platform wants — not voice. Match `$BRAND_VOICE` for tone.

**LinkedIn (professional / builder tone)**:
- Hook: 1 sentence stating what shipped + why it matters
- Detail: 1–2 paragraphs on the user-facing change and the design choice
- Reflection: 1 sentence on the *why* behind the work
- 3–5 hashtags (`#iOSApp #IndieDev #SwiftUI` + content-specific)

**Instagram**:
- Same body as LinkedIn (or slightly tightened)
- IG-friendly hashtags (8 is fine) — content-specific + brand-tagged

**X (single tweet OR 3-tweet reply chain)**:
- T1 (hook, ≤280 chars, 1 image): "Shipped … today — <feature one-liner>"
- T2 (detail, ≤280 chars, 1 image): the user-facing experience
- T3 (closing, ≤280 chars, no media): the reflection + hashtags
- Or a single tweet if the feature is simple (e.g. one screen recording tells the whole story)

Write the X thread to `/tmp/x-thread-${SLUG_FILE}.json` in the `[{text, media?}, ...]` format `/x-post` expects.

**Pinterest — SEARCH-REWRITTEN, not announcement-style**:

Pinterest is a search engine, not a feed. "We just shipped X" content does NOT surface — search-friendly how-to / explainer content does. **Reframe the same feature as something a user would search for**, then write a title + description rich in keywords.

Examples of the announcement → Pinterest rewrite:

| Announcement (LinkedIn / X / IG) | Pinterest search-rewrite |
|---|---|
| "Just shipped: AI Explain feature in <App>" | "How to chat with <content> using AI on iPhone" |
| "New History view: 9 eras of <topic>" | "<Topic> Timeline — Free iPhone App" |
| "Redesigned More tab" | "Best <App-category> Features for iPhone" |

Write `/tmp/pinterest-${SLUG_FILE}.json`:

```json
{
  "media":       "<TALL RAW screenshot path — NOT the 4:5 padded version; or pad_ios_video.sh output if it's a video feature>",
  "title":       "<search-rewritten title — under 100 chars — front-load keywords>",
  "description": "<3–5 sentences front-loaded with searchable phrases the user would actually google. End with the destination link mention. Up to 500 chars.>",
  "board":       "${PIN_BOARD}",
  "link":        "${BRAND_URL}"
}
```

**Board strategy**:
- `feature_board` (from brand.json) is the default for feature pins — broad keyword board users actually search.
- `default_board` is reserved for daily-content cron output — don't mix the two.
- The `/pinterest-post` skill handles board creation inline if the named board doesn't exist yet.

**Media for Pinterest**:
- For an image-based feature: use the **tall RAW iPhone screenshot** (Pinterest's algorithm prefers vertical 2:3 / taller; padding to 4:5 hurts reach).
- For a video feature: use the **`pad_ios_video.sh` output** (1080×1920 9:16) — same as IG / LinkedIn / X.
- Pinterest indexes alt-text-style descriptions, so the description should literally say what's in the image (e.g. "iPhone screen showing the <App> verse explainer with on-device AI chat").

## Step 5: Show drafts and get approval

Lay all four drafts inline with character counts (X) and image attachments listed. Ask:

> Approve all four, change something, or skip a platform?

Wait for explicit approval before any posting.

## Step 6: Cross-post

Default order: **LinkedIn → Instagram → X → Pinterest**. LinkedIn first because company-page posts are typically the primary "company news" channel; X last among the announcement platforms because the reply chain is more clicks; Pinterest at the end because it's a separate audience with a different content rewrite — it doesn't share the announcement caption.

For each enabled platform in `$3`:

- **LinkedIn**: `/linkedin-post "$LINKEDIN_TARGET" <padded-screenshot-1> [<padded-screenshot-2> ...] "<caption>"` — pass multiple media paths for a carousel.
- **Instagram**: `/instagram-post "$IG_ACCOUNT" <padded-screenshot-1> [<padded-screenshot-2> ...] "<caption>"` — same multi-file convention.
- **X**: `/x-post "$X_HANDLE" /tmp/x-thread-${SLUG_FILE}.json` — `/x-post` switches the X session to the right account (no-op if already there), then posts the thread.
- **Pinterest**: `/pinterest-post /tmp/pinterest-${SLUG_FILE}.json` — single pin in `$PIN_BOARD` with search-rewritten content.

Wait for each skill's run log before starting the next. If one fails, ask before continuing — the user may want to fix and re-run that platform only.

## Step 7: Report

Summarize per platform:
- Outcome (success / failed at step N)
- Live URL (LinkedIn post URL if available, Instagram permalink, X status URL, Pinterest pin URL)
- Run log path
- Verification screenshot

Recommend any follow-ups: cross-post review, X engagement (likes / follows from your handle to push the account toward graduating out of any soft-restriction state), Pinterest re-pin yourself from a different board if the pin would fit two themes.

**Do not close any browser tab.**
