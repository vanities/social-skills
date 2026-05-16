---
name: linkedin-post
description: Post a media + caption to LinkedIn. Pass `personal` to post to your own feed, or a numeric company id to post AS that company page (find your id in the page admin URL). Use when the user says "post X to linkedin" or runs /linkedin-post.
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
# Switch to the LinkedIn tab via curl-based discovery (NEVER `agent-browser
# tab list` — auto-spawn risk). Helper does find + switch + URL-verify +
# tab-new fallback in one step. See feedback_no_agent_browser_in_cron_guard.md.
bash scripts/switch_to_platform_tab.sh "linkedin.com" "https://www.linkedin.com/feed/"
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

**Personal-feed regression caught 2026-05-15**: the sidebar "Start a post" element is a `<div role="button">` (NOT a `<button>`). Both `agent-browser click @<ref>` (synthesized event) AND a real `mouse move/down/up` on its bbox center **failed to open the modal** — clicks acknowledged, no dialog appeared. Company-page admin pages use a real `<button>` that works as before; only personal-feed is broken.

**Reliable path for both contexts: deep-link to `?shareActive=true`.**

```bash
# Try the conventional click path first; fall back to deep-link if no modal opens.
START_REF=$(agent-browser snapshot -i 2>&1 | grep -E 'button "Start a post"' | head -1 | grep -oE 'ref=e[0-9]+' | sed 's/ref=/@/')
if [ -n "$START_REF" ]; then
  agent-browser click "$START_REF"
  agent-browser wait $(bash scripts/jitter.sh 1500 2500)
fi
HAS_MODAL=$(agent-browser eval "(()=>{const f=document.querySelector('iframe[src*=preload]');try{const ed=f?.contentDocument.querySelector('[aria-label=\"Text editor for creating content\"]');return ed?'open':'closed';}catch(e){return 'closed';}})()" 2>&1 | tail -1 | tr -d '"')

if [ "$HAS_MODAL" != "open" ]; then
  echo "[li-post] Start-a-post click no-op'd — using deep-link fallback" >&2
  agent-browser open "https://www.linkedin.com/feed/?shareActive=true"
  agent-browser wait --load networkidle
  sleep 3
fi
```

If a "Create" menu opens (event / hiring / article options) instead of the compose modal, click **"Start a post"** in that menu.

The modal opens with:
- Audience switcher button (text contains the page name + "Post to Anyone")
- Text editor textbox (label `Text editor for creating content`) — **lives inside `iframe[src*=preload]`'s contentDocument**, so `snapshot -i` does NOT see it (Step 6 accesses it via iframe.contentDocument)
- "Add media" / toolbar buttons (also in the iframe — see Step 7b for the toolbar-icon programmatic-click limitation)
- "Post" button (disabled until content)

## Step 5: Verify audience

For company posts, verify the audience switcher reads **"<Company Name> … Post to Anyone"**. If it reads the user's personal name, the wrong context is loaded — abort and re-navigate to the admin URL.

## Step 6: Type the caption

The editor lives inside `iframe[src*=preload]`'s contentDocument and is **not surfaced by `snapshot -i`** (personal feed at least, 2026-05-15). Focus via `iframe.contentDocument.querySelector` and use `agent-browser keyboard type` (preserves newlines, sends real Enter keystrokes that LinkedIn's editor converts to proper paragraph breaks):

```bash
agent-browser eval "(()=>{const f=document.querySelector('iframe[src*=preload]');const ed=f.contentDocument.querySelector('[aria-label=\"Text editor for creating content\"], [contenteditable=\"true\"]');if(!ed)return 'no-editor';ed.focus();return 'focused'})()"
agent-browser wait $(bash scripts/jitter.sh 300 700)
agent-browser keyboard type "$2"
agent-browser wait $(bash scripts/jitter.sh 800 1600)

# Verify text landed (textContent collapses newlines so length will be slightly < source):
agent-browser eval "(()=>{const f=document.querySelector('iframe[src*=preload]');const ed=f.contentDocument.querySelector('[aria-label=\"Text editor for creating content\"]');return JSON.stringify({len:ed?ed.textContent.length:0,tail:ed?ed.textContent.slice(-80):''})})()"
```

## Step 7: Add media

### 7a: Handle any auto-attached link cards first

If the caption contains a URL (e.g. `github.com/...`, a blog post, etc.), LinkedIn often auto-fetches an Open Graph link card and **occupies the single media slot with it**. You'll see `Edit media preview` + `Remove media` buttons in the compose modal even though you haven't uploaded anything. To attach your own screenshot, click **Remove media** first to free the slot — the URL stays clickable in the caption text.

**Critical (set 2026-05-07)**: `agent-browser click "@<REMOVE_MEDIA_REF>"` silently no-ops on this button — sometimes 4+ attempts return `✓ Done` but the link card stays attached. LinkedIn's React handler ignores synthesized clicks here, same pattern as IG's Select crop button. **Use a real mouse event** (`mouse move/down/up` at the button's bbox center):

```bash
# Get the Remove media button's bbox center
read -r MX MY < <(agent-browser eval "(()=>{const b=Array.from(document.querySelectorAll('button')).find(b=>(b.getAttribute('aria-label')||b.textContent||'').trim()==='Remove media');const r=b.getBoundingClientRect();return Math.round(r.x+r.width/2)+' '+Math.round(r.y+r.height/2)})()" 2>&1 | tail -1 | tr -d '"')
# Real mouse click — opens nothing fancy, just removes the link card
agent-browser mouse move "$MX" "$MY" && \
  agent-browser wait 200 && \
  agent-browser mouse down && \
  agent-browser wait 100 && \
  agent-browser mouse up
agent-browser wait $(bash scripts/jitter.sh 700 1500)
# Verify by re-snapshot — "Remove media" should be gone, "Add media" should be present
```

### 7b: Click Add media + upload

**Critical personal-feed limitation (2026-05-15)**: the toolbar icons in the compose modal (image-frame / video / event / "+") are NOT reachable via `iframe.contentDocument.querySelectorAll('button')` — that query returns 0 buttons in the modal's bottom toolbar area, even though they're visible on-screen. They appear to render in a portal/layer the contentDocument access can't see. Company-page admin posts didn't hit this. Interactive mode: prompt the user to click the image-frame icon manually, then continue from the media editor. Cron / fully-automated: this leg fails — for now, /feature-post LinkedIn leg should prefer the company-page route (which uses a real `<button>` that responds to clicks).

Once the user has clicked the image icon and the media editor is open: the full-screen "Upload from computer" button **is** surfaced by `snapshot -i` and `agent-browser upload @<ref>` works. From here the flow proceeds as documented below.

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

If after the wait the compose modal is still open (the @ref click silently no-op'd — confirmed live 2026-05-10 on X and Pinterest with the same publish-button-render-race), fall back to eval-find-button-by-text:

```bash
DIALOG=$(agent-browser eval "(()=>{const d=document.querySelector('[role=dialog]');return d?'open':'closed'})()" 2>&1 | tail -1 | tr -d '"')
if [ "$DIALOG" != "closed" ]; then
  echo "[li-post] Post click no-op'd — retrying via eval" >&2
  agent-browser eval "(()=>{const post=Array.from(document.querySelectorAll('button')).find(b=>b.textContent.trim()==='Post'&&!b.disabled);if(post){post.click();return 'clicked'}return 'no btn'})()"
  agent-browser wait 4000
fi
```

## Step 8b: Dismiss the post-publish upsell

After publishing, LinkedIn often shows an **"Auto-invite people to follow your Page when they engage with your posts"** promo (Premium upsell, "Redeem 1 month for $0"). Snapshot, find the **"No thanks"** button, click it. Skipping this leaves the modal blocking later automation.

```bash
agent-browser snapshot -i 2>&1 | head -10
agent-browser click @<no-thanks-ref>
agent-browser wait 1500
```

The snapshot at this point also includes a **"View post"** link — capture its href for the run log AND for Step 8c.

```bash
POST_URL=$(agent-browser eval "(()=>{const a=Array.from(document.querySelectorAll('a')).find(a=>(a.textContent||'').trim()==='View post');return a?a.href:''})()" 2>&1 | tail -1 | tr -d '"')
echo "POST_URL=$POST_URL"
```

## Step 8c (optional): First-comment URL

LinkedIn's algorithm deranks post bodies that contain external URLs. The well-known workaround is to keep the body URL-free and drop the link as the **first comment** on your own post: algorithm sees engagement, humans see the link top-of-comments. Verified live 2026-05-15 on a personal-feed DocVault round-up post.

Run this step when the caller wants a first-comment URL — e.g. the caption is link-free intentionally and the GitHub / app store / blog URL should be added immediately as a comment. Skip otherwise.

```bash
# URL-encode the urn colons — agent-browser's CDP open errors on raw `urn:li:share:`.
POST_URL_ENC=$(echo "$POST_URL" | sed 's/urn:li:share:/urn%3Ali%3Ashare%3A/')
agent-browser open "$POST_URL_ENC"
agent-browser wait --load networkidle
sleep 3

# Click the engagement-action Comment button (opens the inline comment composer).
COMMENT_OPEN_REF=$(agent-browser snapshot -i 2>&1 | grep -E 'button "Comment"' | head -1 | grep -oE 'ref=e[0-9]+' | sed 's/ref=/@/')
agent-browser click "$COMMENT_OPEN_REF"
agent-browser wait $(bash scripts/jitter.sh 800 1500)

# The comment editor shares its aria-label with the post composer:
# [role=textbox][aria-label="Text editor for creating content"]. Scroll it into view, focus, type.
agent-browser eval "(()=>{const e=Array.from(document.querySelectorAll('[role=textbox]')).find(el=>el.getAttribute('aria-label')==='Text editor for creating content'&&el.offsetParent!==null);if(!e)return 'not-found';e.scrollIntoView({block:'center'});e.focus();return 'scrolled+focused'})()"
agent-browser wait 800
agent-browser keyboard type "$COMMENT_TEXT"
agent-browser wait $(bash scripts/jitter.sh 800 1500)

# Submit. There are TWO visible buttons with text "Comment": the engagement-action one (aria="Comment", above the editor) and the submit one (no aria, below the editor). eval-find by absence of aria-label:
agent-browser eval "(()=>{const buttons=Array.from(document.querySelectorAll('button')).filter(b=>b.offsetParent!==null&&(b.textContent||'').trim()==='Comment');const submit=buttons.find(b=>b.getAttribute('aria-label')!=='Comment');if(!submit)return 'no-submit';submit.click();return 'clicked'})()"
agent-browser wait 4000

# Verify live
agent-browser eval "(()=>{const live=Array.from(document.querySelectorAll('span,p,div')).find(e=>(e.textContent||'').trim()===\$COMMENT_TEXT&&e.offsetParent!==null);return JSON.stringify({foundLiveComment:!!live})})()"
```

## Step 9: Verify and write the run log

```!
agent-browser screenshot /tmp/linkedin-post-$0-$(date +%Y-%m-%dT%H%M%S).png
```

Use `Write` to create `~/.social-skills/logs/post/linkedin-$0-<timestamp>.json`:

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
