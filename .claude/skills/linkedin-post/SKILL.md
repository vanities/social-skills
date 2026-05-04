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

```!
agent-browser tab list 2>&1
```

- If a LinkedIn tab is open, switch to it.
- Else: `agent-browser tab new https://www.linkedin.com/feed/`.

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

Click the **Add media** button. A media editor opens with an "Upload from computer" entry. Find the underlying file input — LinkedIn uses `id=media-editor-file-selector__file-input` with `multiple=true`, accepting images and video.

```bash
agent-browser eval "Array.from(document.querySelectorAll('input[type=file]')).map(e=>({accept:e.accept,name:e.name,multiple:e.multiple}))"
```

Upload via the file input selector. **`agent-browser upload` accepts multiple file paths** as positional args — pass all of them in a single call to attach a multi-image post:

```bash
agent-browser upload "input[type=file]" "$1"           # single image
# or
agent-browser upload "input[type=file]" path1.jpg path2.jpg path3.jpg   # multi-image post
```

Wait for the preview to render (`agent-browser wait $(bash scripts/jitter.sh 1500 3000)`), then click **Next** in the media editor (typically `@e6` after upload) to return to the compose modal with the image(s) attached.

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
