---
name: instagram-post
description: Post a media file to Instagram with a caption. Operates against the shared headed Chrome — finds the existing Instagram tab if one is open, otherwise opens one. Use when the user says "post X to Instagram" or runs /instagram-post.
argument-hint: [account] [media-path] [caption]
allowed-tools: Bash(agent-browser *) Bash(test *) Bash(ls *) Bash(date *) Bash(grep *)
---

# Post to Instagram

Account: `$0`
Media:   `$1`
Caption: `$2`

Reference: `docs/platforms/instagram.md`.

## Step 1: Sanity checks

```!
test -f "$1" && echo "media ok" || echo "MEDIA MISSING at $1"
```

If the media is missing, abort.

## Step 1a: Resolve the actual IG handle (URL slug)

`$0` is the **env-var label** that maps to `.env` credentials (e.g., `INSTAGRAM_SWIFTBIBLE_USERNAME`). The actual IG handle that appears in profile URLs is often different — e.g., the label `swiftbible` ↔ the handle `@swift_bible` (with underscore). Step 8b's post-publish verification needs the handle to build the right URL; using the label sends us to `instagram.com/<label>/` which is a different (or non-existent) profile.

Resolve from `config/brand.json`: find the brand whose `instagram.default_account` matches `$0`, then take that brand's `instagram.own_handle`. Falls back to `$0` if brand.json isn't readable or `own_handle` isn't set.

```!
IG_HANDLE=$(jq -r --arg label "$0" '.brands | to_entries[] | select(.value.instagram.default_account == $label) | .value.instagram.own_handle // empty' config/brand.json 2>/dev/null)
[ -z "$IG_HANDLE" ] && IG_HANDLE="$0"
echo "IG_HANDLE=$IG_HANDLE (label=$0)"
```

## Step 1b: Pre-pad tall iPhone media

Instagram aggressively crops content that doesn't match the aspect it expects (4:5 for feed photos, 9:16 for Reels). Pad before uploading.

**Image (feed post → 4:5)**:

```bash
PADDED=$(bash scripts/pad_ios_screenshot.sh "$1" "" edge)
# Modes: edge (default, seamless) | blur (Apple-style blurred bg) | random (curated palette) | #RRGGBB (solid)
# No-ops if the image is already 4:5 or wider.
```

For an aesthetic feature post, prefer `blur` — polished album-art-style frame.

**Video (Reel → 9:16)**:

```bash
PADDED=$(bash scripts/pad_ios_video.sh "$1" "" blur)
# Modes: blur (default) | black | #RRGGBB
# Outputs 1080x1920 h264 + AAC + faststart. Re-encodes even if already 9:16 (HEVC → h264).
```

IG auto-converts vertical video uploads to Reels (web shows "Video posts are now shared as reels"). The flow below covers both image-feed-post and video-Reel paths; differences are called out per step.

Use `$PADDED` instead of `$1` for the upload step. The original file is left untouched.

## Step 2: Find or open the Instagram tab

```bash
# Switch to the IG tab via curl-based discovery (NEVER `agent-browser tab list`
# — auto-spawn risk). Helper does find + switch + URL-verify + tab-new
# fallback in one step. See feedback_no_agent_browser_in_cron_guard.md.
bash scripts/switch_to_platform_tab.sh "instagram.com" "https://www.instagram.com/"
agent-browser wait --load networkidle
```
- After switching/opening, run `agent-browser wait --load networkidle`.

If the page is on a login wall, abort and tell the user to run `/instagram-login $0` first. The persistent browser should already be logged in; if not, state at `~/.config/agent-browser/instagram-$0.json` can be loaded.

## Step 3: Snapshot the home feed

```!
agent-browser snapshot -i 2>&1 | head -40
```

## Step 4: Click "Create" (new post)

From the snapshot, find the **"Create"** / **"New post"** link (usually labeled `New post Create` in the left sidebar). Click its `@ref`. After the click:

```bash
agent-browser wait $(bash scripts/jitter.sh 700 1500)
```

Then re-snapshot.

## Step 5: Upload the media

When the upload dialog is reachable, find the underlying `<input type=file>`:

```bash
agent-browser eval "Array.from(document.querySelectorAll('input[type=file]')).map(e=>({accept:e.accept,multiple:e.multiple}))"
# accept includes "image/avif,image/jpeg,image/png,image/heic,image/heif,video/mp4,video/quicktime"
```

The IG file input has `multiple=true` — pass multiple paths to `agent-browser upload` for a carousel post:

```bash
agent-browser upload "input[type=file]" "$PADDED"                 # single image OR video
# or for an image carousel (each path padded individually first):
agent-browser upload "input[type=file]" "$PADDED1" "$PADDED2"
```

Wait jitter after:

```bash
agent-browser wait $(bash scripts/jitter.sh 1500 3500)   # videos take longer to ingest than images
```

**For video uploads only**: IG shows a "Video posts are now shared as reels" notice. Snapshot, find OK, click. The post will be a Reel even though we entered via "New post" / "Create".

```bash
agent-browser snapshot -i 2>&1 | grep -E '(OK|Learn more about Reels).*ref' | head -3
agent-browser click "@<OK_REF>"
agent-browser wait $(bash scripts/jitter.sh 1500 3000)
```

## Step 6: Crop / Edit screens

**`agent-browser snapshot -i` does NOT reliably surface the contents of IG's `[role=dialog]` modals (Crop, Edit, Sharing). Use `eval` to find and click buttons inside them.**

Pattern for each modal — get the active dialog's label, then enumerate buttons:

```bash
agent-browser eval "(()=>{const dialogs=document.querySelectorAll('[role=dialog]');return Array.from(dialogs).map(d=>({label:d.getAttribute('aria-label'),visible:d.offsetParent!==null}))})()"
# → [{ "label": "Crop", "visible": true }]

agent-browser eval "(()=>{const d=document.querySelector('[role=dialog][aria-label=Crop]');return Array.from(d.querySelectorAll('button,[role=button]')).map(b=>(b.textContent||b.getAttribute('aria-label')||'').trim())})()"
# → ["Back", "Next", "Select crop", "Open media gallery", ...]
```

### 6a: Crop dialog — pick the right aspect ratio

The Crop dialog defaults to **Original** (which IG often interprets as 1:1 for ambiguous content). Vertical Reels need **9:16 / Mobile**, padded feed photos want **4:5**. Image gets aggressively cropped if the wrong aspect goes through; the only recovery is to back out and re-upload.

**Critical**: the "Select crop" button is the only step in this whole flow that does **not** respond to JS `click()`. IG's React listens for real pointer events on this control. Programmatic `click()` will NOT open the popover. Use `agent-browser mouse move/down/up` at the button's bbox center.

```bash
# Find the Select crop button's bbox (always visible in the Crop dialog footer)
read -r SC_X SC_Y < <(agent-browser eval "(()=>{const d=document.querySelector('[role=dialog][aria-label=Crop]');const sc=Array.from(d.querySelectorAll('button')).find(b=>b.textContent.trim()==='Select crop');const r=sc.getBoundingClientRect();return Math.round(r.x+r.width/2)+' '+Math.round(r.y+r.height/2)})()" 2>&1 | tail -1 | tr -d '"')
echo "Select crop at ($SC_X, $SC_Y)"

# Real mouse click — opens the popover
agent-browser mouse move "$SC_X" "$SC_Y" && \
  agent-browser wait 200 && \
  agent-browser mouse down && \
  agent-browser wait 100 && \
  agent-browser mouse up
agent-browser wait $(bash scripts/jitter.sh 600 1200)
```

After the popover renders, the aspect options DO surface in `agent-browser snapshot -i`:

```bash
agent-browser snapshot -i 2>&1 | grep -E '(Original|1:1|4:5|16:9).*ref' | head -5
# - button "Original Photo outline icon" [ref=eXX]
# - button "1:1 Crop square icon"        [ref=eXX]
# - button "4:5 Crop portrait icon"      [ref=eXX]
# - button "16:9 Crop landscape icon"    [ref=eXX]
# (Reels flow may show a 9:16 / Mobile option in addition to or instead of 16:9.)

# For a vertical Reel: click 9:16 / Mobile
# For a 4:5 padded image: click 4:5
agent-browser click "@<ASPECT_REF>"
agent-browser wait $(bash scripts/jitter.sh 600 1200)
```

If the snapshot returns no aspect options, the popover didn't open — retry the real-mouse click (sometimes the first attempt times out on slow machines).

### 6b: Click Next through Crop → Edit → caption screen

```bash
# Crop → Edit
agent-browser eval "(()=>{const d=document.querySelector('[role=dialog][aria-label=Crop]');const next=Array.from(d.querySelectorAll('button,[role=button]')).find(b=>b.textContent.trim()==='Next');next.click();return 'crop next'})()"
agent-browser wait $(bash scripts/jitter.sh 1500 2500)

# Edit → caption
agent-browser eval "(()=>{const d=document.querySelector('[role=dialog][aria-label=Edit]');const next=Array.from(d.querySelectorAll('button,[role=button]')).find(b=>b.textContent.trim()==='Next');next.click();return 'edit next'})()"
agent-browser wait $(bash scripts/jitter.sh 2000 3500)   # video transcode handshake takes longer
```

Confirm the active dialog is now `Create new post` before continuing.

## Step 7: Enter the caption

The caption textbox is `textbox "Write a caption..."` inside the `Create new post` dialog. **Capture its ref correctly, abort if missing, verify length AND Lexical commit-state after typing, then blur to force Lexical to flush.** `keyboard type` into a focus that didn't take produces no caption AND fires keystrokes into something else (it pops a "Discard post?" dialog). Confirmed live 2026-05-10 and 2026-05-11.

**Critical grep gotcha**: `agent-browser snapshot -i` outputs refs as `[ref=e15]`, NOT `@e15`. The `@e15` form is what we PASS to `agent-browser focus/click`. Many people (and earlier versions of this skill) wrote `grep -oE '@e[0-9]+'` which never matches anything in the snapshot — the script then focuses on an empty ref, typing bubbles, Discard pops. Use `ref=e[0-9]+` then prefix with `@`.

```bash
# Re-snapshot AFTER Edit→Next finished. Lexical needs a moment to mount the
# textbox. Don't proceed until we've confirmed the ref exists.
CAPTION_REF=""
for try in 1 2 3; do
  CAPTION_REF=$(agent-browser snapshot -i 2>&1 | grep -E 'Write a caption' | grep -oE 'ref=e[0-9]+' | head -1 | sed 's/ref=/@/')
  [ -n "$CAPTION_REF" ] && break
  agent-browser wait 1500
done
if [ -z "$CAPTION_REF" ]; then
  echo "[ig-post] caption textbox not found after 3 snapshots — aborting" >&2
  exit 1
fi

agent-browser focus "$CAPTION_REF"
agent-browser wait 400
agent-browser keyboard type "$CAPTION"   # $CAPTION can contain literal \n — keyboard type sends Enter for each newline
agent-browser wait $(bash scripts/jitter.sh 800 1600)

# If keyboard input fired into the wrong target it pops a "Discard post?"
# dialog. Click Cancel to recover, then re-find the caption ref and retry once.
DISCARD=$(agent-browser eval "(()=>{const d=Array.from(document.querySelectorAll('[role=dialog],div')).find(x=>(x.textContent||'').startsWith('Discard post?'));return d?'yes':'no'})()" 2>&1 | tail -1 | tr -d '"')
if [ "$DISCARD" = "yes" ]; then
  echo "[ig-post] Discard dialog popped — Cancelling and retrying caption" >&2
  agent-browser eval "(()=>{const btns=Array.from(document.querySelectorAll('button'));const cancel=btns.find(b=>b.textContent.trim()==='Cancel');if(cancel)cancel.click();return 'cancelled'})()"
  agent-browser wait 1000
  CAPTION_REF=$(agent-browser snapshot -i 2>&1 | grep -E 'Write a caption' | grep -oE 'ref=e[0-9]+' | head -1 | sed 's/ref=/@/')
  agent-browser focus "$CAPTION_REF"
  agent-browser wait 400
  agent-browser keyboard type "$CAPTION"
  agent-browser wait $(bash scripts/jitter.sh 800 1600)
fi

# Verify length AND Lexical commit-state. textContent showing the typed text
# is NOT sufficient — Lexical's editorState may not have committed yet, and
# Share will publish the post without the caption text. Confirmed live
# 2026-05-11 cron: textContent.length was 639 chars at Share time, but the
# server-side post had no caption. Check data-lexical-text spans to confirm
# Lexical's internal model has the text.
COMMIT=$(agent-browser eval "(()=>{const ca=document.querySelector('[role=dialog][aria-label=\"Create new post\"]')?.querySelector('[aria-label=\"Write a caption...\"]');if(!ca)return{found:false};return{textLen:ca.textContent.length,lexicalSpans:ca.querySelectorAll('[data-lexical-text]').length}})()" 2>&1 | tail -10)
echo "$COMMIT"

LEN=$(echo "$COMMIT" | grep -oE '"textLen": [0-9]+' | grep -oE '[0-9]+')
SPANS=$(echo "$COMMIT" | grep -oE '"lexicalSpans": [0-9]+' | grep -oE '[0-9]+')
if [ -z "$LEN" ] || [ "$LEN" = "0" ] || [ -z "$SPANS" ] || [ "$SPANS" = "0" ]; then
  echo "[ig-post] caption not committed to Lexical (len=$LEN spans=$SPANS) — retrying" >&2
  agent-browser focus "$CAPTION_REF"
  agent-browser wait 400
  agent-browser keyboard type "$CAPTION"
  agent-browser wait $(bash scripts/jitter.sh 800 1600)
fi

# Force Lexical to flush its editorState to data-lexical-text spans BEFORE
# Share. Lexical commits on blur. Without this step, Share can fire while
# the typed text is still in Lexical's in-memory buffer and never reaches
# the post payload — the post lands captionless even though textContent
# read 639 chars a moment earlier. Confirmed live 2026-05-11.
agent-browser eval "(()=>{const ca=document.querySelector('[role=dialog][aria-label=\"Create new post\"]')?.querySelector('[aria-label=\"Write a caption...\"]');if(ca)ca.blur();return 'blurred'})()"
agent-browser wait 800
```

**Why `keyboard type` and not `type @ref`**: IG's caption editor is a Lexical contenteditable div. `agent-browser type @ref "multi\nline"` swallows newlines and produces one run-on paragraph. `keyboard type` sends real Enter keystrokes, which Lexical converts to proper `<br><br>` paragraph breaks AND auto-styles `#hashtags` with the correct `class="x7l2uk3 xt0e3qv"` link spans.

## Step 8: Share

The dialog's Share button isn't disambiguated in `snapshot -i` (it gets confused with feed Share buttons). Click via eval:

```bash
agent-browser wait $(bash scripts/jitter.sh 1500 3500)
agent-browser eval "(()=>{const d=document.querySelector('[role=dialog][aria-label=\"Create new post\"]');const sh=Array.from(d.querySelectorAll('button,[role=button]')).find(b=>b.textContent.trim()==='Share');sh.click();return 'clicked Share'})()"
```

Then poll the dialog label until it transitions Sharing → Post shared (videos take longer):

```bash
for i in 1 2 3 4 5 6 7 8; do
  agent-browser wait 3000
  STATE=$(agent-browser eval "(()=>{const d=document.querySelectorAll('[role=dialog]')[0];return d?d.getAttribute('aria-label'):'closed'})()" 2>&1 | tail -1)
  echo "[$i] $STATE"
  echo "$STATE" | grep -q 'Post shared' && break
done

# Dismiss the success dialog
agent-browser eval "(()=>{const d=document.querySelector('[role=dialog][aria-label=\"Post shared\"]');d.querySelector('[role=button]').click();return 'done'})()"
```

## Step 8b: Post-publish caption verification + Edit recovery

Even with the Step 7 blur-to-flush, Lexical commit can still desync under load. Verify the live post received the caption; if not, recover via the post's Edit info dialog (which persists reliably — proven 2026-05-10 + 2026-05-11).

```bash
agent-browser open "https://www.instagram.com/${IG_HANDLE}/"
agent-browser wait --load networkidle
agent-browser wait 2000
LATEST=$(agent-browser eval "(()=>{const a=document.querySelectorAll('a[href*=\"/p/\"]');return a[0]?a[0].getAttribute('href'):''})()" 2>&1 | tail -1 | tr -d '"')
[ -z "$LATEST" ] && { echo "[ig-post] no recent post link found at /${IG_HANDLE}/ — manual check needed" >&2; exit 0; }

agent-browser open "https://www.instagram.com${LATEST}"
agent-browser wait --load networkidle
agent-browser wait 2000

CAPTION_HEAD=$(echo "$CAPTION" | head -c 40 | tr -d '"')
LIVE=$(agent-browser eval "(()=>{const main=document.querySelector('main');return main?main.textContent:''})()" 2>&1 | tail -1 | tr -d '"')

if ! echo "$LIVE" | grep -qF "$CAPTION_HEAD"; then
  echo "[ig-post] live post is missing the caption — recovering via Edit dialog" >&2

  # Open More options → Edit
  MORE_REF=$(agent-browser snapshot -i 2>&1 | grep -E 'More options' | grep -oE 'ref=e[0-9]+' | head -1 | sed 's/ref=/@/')
  agent-browser click "$MORE_REF"
  agent-browser wait $(bash scripts/jitter.sh 600 1100)
  EDIT_REF=$(agent-browser snapshot -i 2>&1 | grep -E '^\s*-?\s*button "Edit"' | grep -oE 'ref=e[0-9]+' | head -1 | sed 's/ref=/@/')
  agent-browser click "$EDIT_REF"
  agent-browser wait $(bash scripts/jitter.sh 1200 2000)

  # Type caption into Edit dialog's caption box (same Lexical editor)
  EDIT_CAP_REF=$(agent-browser snapshot -i 2>&1 | grep -E 'Write a caption' | grep -oE 'ref=e[0-9]+' | head -1 | sed 's/ref=/@/')
  agent-browser focus "$EDIT_CAP_REF"
  agent-browser wait 400
  agent-browser keyboard type "$CAPTION"
  agent-browser wait $(bash scripts/jitter.sh 800 1500)

  # Blur to force Lexical commit before clicking Done
  agent-browser eval "(()=>{const ca=document.querySelector('[role=dialog][aria-label=\"Edit info\"]')?.querySelector('[aria-label=\"Write a caption...\"]');if(ca)ca.blur();return 'blurred'})()"
  agent-browser wait 600

  # Click Done
  DONE_REF=$(agent-browser snapshot -i 2>&1 | grep -E '^\s*-?\s*button "Done"' | grep -oE 'ref=e[0-9]+' | head -1 | sed 's/ref=/@/')
  agent-browser click "$DONE_REF"
  agent-browser wait 4000
  echo "[ig-post] caption recovered via Edit info dialog" >&2
fi
```

## Step 9: Verify and write the run log

```!
agent-browser screenshot /tmp/instagram-post-$0-$(date +%Y-%m-%dT%H%M%S).png
```

Use the `Write` tool to create `~/.social-skills/logs/post/instagram-$0-<timestamp>.json`:

```json
{
  "ts_start": "...",
  "ts_end":   "...",
  "platform": "instagram",
  "account":  "$0",
  "action":   "post",
  "outcome":  "success | failed",
  "media":    "$1",
  "caption":  "...",
  "tab_strategy": "switched | opened-new",
  "form_fields_used": {
    "create_button":  "@<ref>",
    "select_file":    "@<ref>",
    "next_buttons":   ["@<ref>", "@<ref>"],
    "caption_field":  "@<ref>",
    "share_button":   "@<ref>"
  },
  "verification_screenshot": "/tmp/instagram-post-$0-<timestamp>.png"
}
```

Substitute `<timestamp>` with `date +%Y-%m-%dT%H-%M-%S`.

**Do not close the tab** — leave the browser as the user left it. The shared-browser model means the user may want to inspect the result.

## Step 10: Report

Tell the user:

- Outcome.
- Verification screenshot path.
- Run log path.
- If failed, the snapshot of the failing step and a guess at the cause.
