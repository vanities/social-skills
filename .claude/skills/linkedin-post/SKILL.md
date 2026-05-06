---
name: linkedin-post
description: Post a media + caption to LinkedIn. Pass `personal` to post as the user, or a company id (e.g. `104970470` for AM2 LLC) to post AS that company page. Use when the user says "post X to linkedin" or runs /linkedin-post.
disable-model-invocation: true
argument-hint: [personal|<company-id>] [media-path] [caption]
allowed-tools: Bash(agent-browser *) Bash(test *) Bash(date *) Bash(ls *) Bash(grep *)
---

# LinkedIn post

Audience: `$0`  (`personal` or a numeric company id)
Media:    `$1`
Caption:  `$2`

Reference: `docs/platforms/linkedin.md`.

## Step 1: Sanity checks

```!
test -f "$1" && echo "media ok" || echo "MEDIA MISSING at $1"
```

Abort if media missing.

## Step 2: Find or open the LinkedIn tab

```bash
# Find the LinkedIn tab via curl-only — NEVER `agent-browser tab list`.
# See feedback_no_agent_browser_in_cron_guard.md for the why.
TAB_INDEX=$(bash scripts/find_platform_tab.sh "linkedin.com" 2>/dev/null || true)
if [ -n "$TAB_INDEX" ]; then
  agent-browser tab "$TAB_INDEX"
else
  agent-browser tab new "https://www.linkedin.com/feed/"
fi
agent-browser wait --load networkidle
```

If `agent-browser get url` returns `/login`, abort and tell the user to run `/linkedin-login`.

## Step 3: Navigate to the right composer

If `$0` == `personal`:

```!
agent-browser open https://www.linkedin.com/feed/
```

Else (company id):

```bash
agent-browser open "https://www.linkedin.com/company/$0/admin/"
```

`agent-browser wait --load networkidle` after.

## Step 4: Open the compose modal

Snapshot. Find the **"+ Create"** button (sidebar) or **"Start a post"** entry — `agent-browser click @<ref>`. After click, `wait $(bash scripts/jitter.sh 700 1500)` and re-snapshot.

If a "Create" menu opens (event / hiring / article options), click **"Start a post"**.

The modal opens with:
- Audience switcher button (text contains the page name + "Post to Anyone")
- Text editor textbox (label `Text editor for creating content`)
- "Add media" button
- "Post" button (disabled until content)

## Step 5: Verify audience

For company posts, verify the audience switcher reads **"<Company Name> … Post to Anyone"**. If it reads the user's personal name, the wrong context is loaded — abort and re-navigate to the admin URL.

## Step 6: Type the caption

```bash
agent-browser click @<editor-ref> && \
agent-browser wait $(bash scripts/jitter.sh 300 700) && \
agent-browser type @<editor-ref> "$2" && \
agent-browser wait $(bash scripts/jitter.sh 800 1600)
```

## Step 7: Add media

### 7a: Handle any auto-attached link cards first

If the caption contains a URL (e.g. `github.com/...`, a blog post, etc.), LinkedIn often auto-fetches an Open Graph link card and **occupies the single media slot with it**. You'll see `Edit media preview` + `Remove media` buttons in the compose modal even though you haven't uploaded anything. To attach your own screenshot, click **Remove media** first to free the slot — the URL stays clickable in the caption text.

```bash
agent-browser snapshot -i 2>&1 | grep -E '(Remove media|Edit media preview).*ref'
agent-browser click "@<REMOVE_MEDIA_REF>"
agent-browser wait $(bash scripts/jitter.sh 700 1500)
```

### 7b: Click Add media + upload

Click the **Add media** button. A media editor opens with an "Upload from computer" entry. **The compose modal lives inside an iframe (`https://www.linkedin.com/preload/`)** — `document.querySelectorAll('input[type=file]')` against the top document returns `[]`. The reliable upload pattern is to target the visible "Upload from computer" button by its snapshot @e ref:

```bash
agent-browser snapshot -i 2>&1 | grep -E '"Upload from computer".*ref'
agent-browser upload "@<UPLOAD_BUTTON_REF>" "$1"          # single image OR video
# or for a multi-image carousel:
agent-browser upload "@<UPLOAD_BUTTON_REF>" path1.jpg path2.jpg path3.jpg
```

`agent-browser upload @<ref>` correctly resolves the click target across iframes even when querySelector via the top doc does not. The same code path handles video — LinkedIn's media editor accepts `.mp4` (and re-encodes if needed). For an iPhone screen recording, prefer `scripts/pad_ios_video.sh` first to land at 1080×1920 h264 (smaller upload, no HEVC re-transcode).

Wait for the preview to render (`agent-browser wait $(bash scripts/jitter.sh 1500 3000)`), then click **Next** in the media editor to return to the compose modal with the image(s) attached. For videos, the editor renders a `region "Video player"` with a Play button + a "Video title" / "Captions" / "Video thumbnail" toolbar — Next is still the same button.

## Step 8: Post

```bash
agent-browser wait $(bash scripts/jitter.sh 1500 3500) && \
agent-browser click @<post-ref> && \
agent-browser wait 4000
```

## Step 8b: Dismiss the post-publish upsell

After publishing, LinkedIn often shows an **"Auto-invite people to follow your Page when they engage with your posts"** promo (Premium upsell, "Redeem 1 month for $0"). Snapshot, find the **"No thanks"** button, click it. Skipping this leaves the modal blocking later automation.

```bash
agent-browser snapshot -i 2>&1 | head -10
agent-browser click @<no-thanks-ref>
agent-browser wait 1500
```

The snapshot at this point also includes a **"View post"** link — capture its href if you want a permalink for the run log.

## Step 9: Verify and write the run log

```!
agent-browser screenshot /tmp/linkedin-post-$0-$(date +%Y-%m-%dT%H%M%S).png
```

Use `Write` to create `~/.social-agents/logs/post/linkedin-$0-<timestamp>.json`:

```json
{
  "ts_start": "...",
  "ts_end":   "...",
  "platform": "linkedin",
  "audience": "$0",
  "action":   "post",
  "outcome":  "success | failed",
  "media":    "$1",
  "caption":  "...",
  "tab_strategy": "switched | opened-new",
  "form_fields_used": {
    "create_button":      "@<ref>",
    "start_post_link":    "@<ref>",
    "audience_switcher":  "@<ref>",
    "text_editor":        "@<ref>",
    "add_media_button":   "@<ref>",
    "file_input_selector": "input[type=file]",
    "post_button":        "@<ref>"
  },
  "verification_screenshot": "/tmp/linkedin-post-$0-<timestamp>.png"
}
```

## Step 10: Report

Outcome, screenshot path, run log path. **Do not close the tab.**
