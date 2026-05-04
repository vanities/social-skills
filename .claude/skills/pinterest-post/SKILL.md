---
name: pinterest-post
description: Post a pin to Pinterest. Reads a JSON spec with media, title, description, board, and optional destination link. Use when the user says "post to pinterest", "pin this", or runs /pinterest-post.
disable-model-invocation: true
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
  "link":        "https://am2.biz/swiftbible"
}
```

- `media` is required. JPEG / PNG / GIF / WebP / MP4. Tall (2:3 ≈ 1000×1500) gets the most reach. **iPhone screenshots fit natively** — no 4:5 padding needed for Pinterest.
- `title` is required. Up to 100 chars.
- `description` is required. Up to 500 chars.
- `board` is required. Pinterest blocks publish until a board is selected.
- `link` is optional but highly recommended — Pinterest's primary value is driving traffic.

## Step 1: Sanity checks

```!
test -f "$1" && jq -e '.media and .title and .description and .board' "$1" > /dev/null && echo "pin spec ok" || echo "MISSING REQUIRED FIELDS"
MEDIA=$(jq -r '.media' "$1") && test -f "$MEDIA" && echo "media ok" || echo "MEDIA MISSING at $MEDIA"
echo "title=$(jq -r '.title' "$1" | wc -c) chars; description=$(jq -r '.description' "$1" | wc -c) chars"
```

Abort if any check fails. (`wc -c` includes trailing newline → effective max is 101 / 501.)

## Step 2: Find or open the Pinterest tab

```!
agent-browser tab list 2>&1
```

- If a tab matches `pinterest.com`, switch into it.
- Else: `agent-browser tab new https://www.pinterest.com/`.

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

```bash
BOARD=$(jq -r '.board' "$1")
agent-browser click @<BOARD_BUTTON>
agent-browser wait $(bash scripts/jitter.sh 600 1200)
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

```bash
agent-browser snapshot -i 2>&1 | grep -E 'Publish.*ref' | head -1
agent-browser wait $(bash scripts/jitter.sh 1500 3500)
agent-browser click "@<PUBLISH_REF>"
agent-browser wait 8000   # publish takes 5–8s; the button text flips to "Publishing" mid-flight
```

After publish: the form clears, `Pin drafts (N)` decrements by one, and the new pin appears at `https://www.pinterest.com/<handle>/<board>/`. Verify by navigating to the board and confirming the pin count went up.

## Step 10: Verification screenshot + run log

```!
agent-browser screenshot /tmp/pinterest-post-default-$(date +%Y-%m-%dT%H%M%S).png
```

Use `Write` to create `~/.social-agents/logs/post/pinterest-default-<timestamp>.json`:

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

## Step 11: Report

Outcome, pin URL, screenshot path, run log path. **Do not close the tab.**
