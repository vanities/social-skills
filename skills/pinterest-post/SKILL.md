---
name: pinterest-post
description: Post a pin to Pinterest. Reads a JSON spec with media, title, description, board, and optional destination link. Use when the user says "post to pinterest", "pin this", or runs /pinterest-post.
argument-hint: [pin-json]
allowed-tools: Bash(agent-browser *) Bash(test *) Bash(date *) Bash(grep *) Bash(jq *) Bash(cat *) Bash(mkdir *) Read(*) Write(*)
---

# Post a pin to Pinterest

`$1`: path to a JSON file describing the pin.

## Pin file format

```json
{
  "media":       "/abs/path/to/image.jpg",
  "title":       "Pin title (≤100 chars)",
  "description": "Pin description (≤500 chars). Hashtags work but Pinterest weights search keywords > hashtags — write naturally with relevant terms.",
  "board":       "Board name (must exist or will be created inline)",
  "link":        "https://example.com"
}
```

- `media` is required. JPEG / PNG / GIF / WebP / MP4. Tall (2:3 ≈ 1000×1500) gets the most reach. **iPhone screenshots fit natively** — no 4:5 padding needed for Pinterest.
- `title` is required. Up to 100 chars.
- `description` is required. Up to 500 chars.
- `board` is required. Pinterest blocks publish until a board is selected.
- `link` is optional but highly recommended — Pinterest's primary value is driving traffic.

## Step 0a: Snapshot tabs (for cleanup at end)

```bash
# Record the current tab set so the final step can close anything we spawn.
# No-op behaviorally when config/brand.json has keep_tabs_open: true.
# See AGENTS.md → "Spawned-tab cleanup".
TAB_BASELINE="${HOME}/.social-skills/state/tab-baseline-pinterest-post.json"
bash scripts/tab_baseline_save.sh "$TAB_BASELINE"
```

## Step 1: Sanity checks

```!
test -f "$1" && jq -e '.media and .title and .description and .board' "$1" > /dev/null && echo "pin spec ok" || echo "MISSING REQUIRED FIELDS"
MEDIA=$(jq -r '.media' "$1") && test -f "$MEDIA" && echo "media ok" || echo "MEDIA MISSING at $MEDIA"
echo "title=$(jq -r '.title' "$1" | wc -c) chars; description=$(jq -r '.description' "$1" | wc -c) chars"
```

Abort if any check fails. (`wc -c` includes trailing newline → effective max is 101 / 501.)

## Step 2: Find or open the Pinterest tab

```bash
# Switch to the Pinterest tab via curl-based discovery (NEVER `agent-browser
# tab list` — auto-spawn risk). Helper does find + switch + URL-verify +
# tab-new fallback in one step. See feedback_no_agent_browser_in_cron_guard.md.
bash scripts/switch_to_platform_tab.sh "pinterest.com" "https://www.pinterest.com/"
agent-browser wait --load networkidle
```

If `agent-browser get url` returns a login URL, abort and tell the user to run `/pinterest-login`.

## Step 3: Open the pin builder

Snapshot, find the **"Create"** sidebar button. Click. A dropdown opens with `Create Pin`, `Create Board`, `Create collage`. Click **"Create Pin"**.

```bash
# After the click, the URL becomes pinterest.com/pin-creation-tool/
agent-browser wait --load networkidle
```

The pin builder shows:
- A `File Upload` button — the underlying `<input type=file>` has `id="storyboard-upload-input"`, `accept` of common image/video MIME types, `multiple=true` (single image per pin is the typical case)
- A `Title` textbox (disabled until media uploaded)
- An `Add a detailed description` button (clicking opens a description editor)
- A `Link` textbox (under a `Link` label)
- A `Choose a board` dropdown (required for publish)
- Tagged topics, products, more options
- A `Create new Pin` button (top-right, disabled until form is valid)

## Step 4: Upload the media

```bash
MEDIA=$(jq -r '.media' "$1")
agent-browser upload "#storyboard-upload-input" "$MEDIA"
agent-browser wait $(bash scripts/jitter.sh 1500 3500)
```

Wait for the preview to render. Title / description / board fields become enabled.

## Step 5: Fill the title

Re-snapshot, find the `Title` textbox (now enabled).

```bash
TITLE=$(jq -r '.title' "$1")
agent-browser click @<TITLE_REF>
agent-browser wait $(bash scripts/jitter.sh 300 700)
agent-browser type @<TITLE_REF> "$TITLE"
agent-browser wait $(bash scripts/jitter.sh 400 1000)
```

## Step 6: Fill the description

The description field renders as a `button` element wrapping a `combobox` (`Add a detailed description`). **Click the combobox child, not the button wrapper** — the button click sometimes fails to focus the input properly. The combobox ref appears as a child of the button in the snapshot.

```bash
DESCRIPTION=$(jq -r '.description' "$1")
agent-browser click @<DESCRIPTION_COMBOBOX>   # the child combobox, not the button parent
agent-browser wait $(bash scripts/jitter.sh 400 900)
agent-browser type @<DESCRIPTION_COMBOBOX> "$DESCRIPTION"
agent-browser wait $(bash scripts/jitter.sh 400 1000)
```

## Step 7: Fill the link (if present)

```bash
LINK=$(jq -r '.link // empty' "$1")
if [ -n "$LINK" ]; then
  agent-browser click @<LINK_TEXTBOX>
  agent-browser wait $(bash scripts/jitter.sh 300 700)
  agent-browser type @<LINK_TEXTBOX> "$LINK"
  agent-browser wait $(bash scripts/jitter.sh 400 1000)
fi
```

## Step 8: Pick the board

The `Choose a board` button opens a dropdown. Click, then either:
- Click the existing board by name, or
- Click "Create board", type the board name, click Create

**Critical**: re-snapshot RIGHT before clicking the board button — refs shift after every field fill (title / description / link), and the board-button ref captured pre-fill silently no-ops or, worse, triggers Pinterest's **drafts sidebar** which then hijacks the form with another saved draft. Confirmed live 2026-05-15: clicked a stale board ref, drafts sidebar opened, an unrelated "Acts 1:9" draft was auto-loaded into the form on top of the just-typed Lamentations content. Recovery is expensive (reload pin-creation-tool, re-upload, re-fill).

```bash
BOARD=$(jq -r '.board' "$1")
# Pause briefly so Pinterest's auto-save commits before we change focus —
# clicking during an in-flight auto-save is one of the ways the drafts
# sidebar opens instead of the board dropdown.
agent-browser wait $(bash scripts/jitter.sh 800 1500)
# Re-snapshot to get the LIVE board-button ref (NOT the one captured post-upload)
BOARD_BTN_REF=""
for try in 1 2 3; do
  BOARD_BTN_REF=$(agent-browser snapshot -i 2>&1 | grep -E 'Open dropdown' | grep -iE 'board|choose' | head -1 | grep -oE 'ref=e[0-9]+' | sed 's/ref=/@/')
  [ -n "$BOARD_BTN_REF" ] && break
  agent-browser wait 800
done
[ -n "$BOARD_BTN_REF" ] || { echo "[pinterest-post] board button ref not found after 3 snapshots" >&2; exit 1; }
agent-browser click "$BOARD_BTN_REF"
agent-browser wait $(bash scripts/jitter.sh 700 1300)

# Sanity check: did the board dropdown open, or did the drafts sidebar
# hijack? The dropdown shows a 'Create board' button; the drafts sidebar
# shows a 'Pin drafts (N)' heading at the top of the left panel.
DROPDOWN_STATE=$(agent-browser eval "(()=>{const draft=Array.from(document.querySelectorAll('h2')).find(h=>(h.textContent||'').startsWith('Pin drafts'));const create=Array.from(document.querySelectorAll('button')).find(b=>(b.textContent||'').trim()==='Create board');return JSON.stringify({draftsSidebar:!!draft,boardDropdown:!!create})})()" 2>&1 | tail -1)
if echo "$DROPDOWN_STATE" | grep -q '"draftsSidebar":true'; then
  echo "[pinterest-post] click opened drafts sidebar (hijack!) — aborting, re-run /pinterest-post to retry" >&2
  exit 1
fi
```

**If no matching board exists** (fresh accounts have none — only "Create board" is offered), open the create-board form and type the name. **Pinterest assigns the board-name input a real DOM id of `boardEditName`** — type via the id selector, not the snapshot @ref (the @ref click sometimes fails to focus the input properly):

```bash
agent-browser click @<CREATE_BOARD>
agent-browser wait $(bash scripts/jitter.sh 600 1200)
agent-browser eval "document.querySelector('#boardEditName')?.focus(); 'focused'"
agent-browser type "#boardEditName" "$BOARD"
agent-browser wait $(bash scripts/jitter.sh 600 1300)
# Re-snapshot — Create button (was disabled) is now enabled
agent-browser click "@<CREATE_BOARD_SUBMIT>"
agent-browser wait $(bash scripts/jitter.sh 1500 3000)
# After board creates, dropdown closes; the board-button label changes to the new board name.
```

**For an existing board** (subsequent posts), just click the matching button in the dropdown. After selection the dropdown closes and the button label reads `<Board Name> Open dropdown`.

## Step 9: Publish

**The button labeled `Publish`** (top-right, red) is the publish action. Its ref shifts each render — re-snapshot. **Do NOT click `Create new Pin`** — that button starts a fresh draft and saves the current form as a *draft* (Pinterest auto-saves every form change to drafts; the sidebar shows `Pin drafts (N)`).

**Critical**: by the time you reach this step, the form has typically grown past one viewport and the Publish button (top-right of the form) is **scrolled off-screen** at a negative y. A click on a button at `y < 0` silently no-ops (or saves a draft) — you'll see "Pin drafts" increment instead of a published toast. Always scroll it into view before clicking.

**Click via `eval`-find-button-by-text, NOT `@<PUBLISH_REF>`.** Confirmed live 2026-05-10: `agent-browser click "@<PUBLISH_REF>"` (with the button visibly in viewport, not disabled, scrollintoview-d) silently saved the form as a draft instead of publishing — `Pin drafts (N+1)` incremented, no toast. Re-clicking via `agent-browser eval "...pub.click()"` published immediately. Same pattern as X's tweetButton.

```bash
agent-browser scrollintoview "@<PUBLISH_REF>"
agent-browser wait $(bash scripts/jitter.sh 700 1300)
# Sanity check the bbox is in viewport
agent-browser eval "(()=>{const pub=Array.from(document.querySelectorAll('button')).find(b=>b.textContent.trim()==='Publish'&&!b.disabled);if(!pub)return 'gone';const r=pub.getBoundingClientRect();return{disabled:pub.disabled,inViewport:r.y>=0&&r.y+r.height<=window.innerHeight}})()"

# Publish via eval — the @ref path saves drafts even when bbox is correct.
agent-browser eval "(()=>{const pub=Array.from(document.querySelectorAll('button')).find(b=>b.textContent.trim()==='Publish'&&!b.disabled);if(pub){pub.click();return 'clicked'}return 'no btn'})()"
agent-browser wait 8000   # publish takes 5–8s; the button text flips to "Publishing" mid-flight
```

After click, look for **"Your Pin has been published!"** in the next snapshot. If instead you see `Pin drafts (N+1)` (incremented) and the form still shown, the click no-op'd — re-scroll, re-snapshot, re-click.

After publish: the form clears, `Pin drafts (N)` decrements by one, and the new pin appears at `https://www.pinterest.com/<handle>/<board>/`. Verify by navigating to the board and confirming the pin count went up.

## Step 10: Verification screenshot + run log

```!
agent-browser screenshot /tmp/pinterest-post-default-$(date +%Y-%m-%dT%H%M%S).png
```

Use `Write` to create `~/.social-skills/logs/post/pinterest-default-<timestamp>.json`:

```json
{
  "ts_start": "...",
  "ts_end":   "...",
  "platform": "pinterest",
  "account":  "default",
  "action":   "post",
  "outcome":  "success | failed",
  "pin_file":   "$1",
  "media":      "...",
  "title":      "...",
  "description_chars": <n>,
  "board":      "...",
  "link":       "...",
  "pin_url":    "https://www.pinterest.com/pin/...",
  "form_fields_used": {
    "create_button":      "@<ref>",
    "create_pin_link":    "@<ref>",
    "file_input":         "#storyboard-upload-input",
    "title_textbox":      "@<ref>",
    "description_field":  "@<ref>",
    "link_textbox":       "@<ref>",
    "board_button":       "@<ref>",
    "publish_button":     "@<ref>"
  },
  "verification_screenshot": "..."
}
```

## Step 10a: Close spawned tabs

```bash
bash scripts/close_spawned_tabs.sh "$TAB_BASELINE"
rm -f "$TAB_BASELINE"
```

## Step 11: Report

Outcome, pin URL, screenshot path, run log path. **Do not close the Pinterest platform tab** — the closer protects it via `essential_tabs`; only incidentally-spawned tabs get cleaned up.
