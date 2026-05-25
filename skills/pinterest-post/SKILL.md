---
name: pinterest-post
description: Post a pin to Pinterest. Reads a JSON spec with media, title, description, board, and optional destination link. Use when the user says "post to pinterest", "pin this", or runs /pinterest-post.
argument-hint: [pin-json]
allowed-tools: Bash(agent-browser *) Bash(test *) Bash(date *) Bash(grep *) Bash(jq *) Bash(cat *) Bash(mkdir *) Bash(head *) Bash(curl *) Read(*) Write(*)
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

## THE most important thing to know (Business Hub UI, 2026-05)

Pinterest serves the **Business Hub** UI. The single biggest failure mode is the
**broken-render state**: a Pinterest tab that has been alive a while (or was
navigated route-to-route) rots into a blank page — `document.body` still has a
nonzero height but `innerText.length === 0`, `agent-browser snapshot -i` returns
**0 refs**, and the form selectors don't exist. **This state survives hard
reloads.** Both 2026-05-25 Pinterest runs wasted most of their effort here: they
saw "snapshot returns nothing" and concluded the whole UI was eval-only, when in
fact they were just operating inside a dead tab.

**The fix is not eval-gymnastics — it is to open the builder in a FRESH tab and
verify it rendered.** On a freshly-opened `pin-creation-tool` tab the builder
renders normally: `#storyboard-upload-input` is present, `bodyLen > 0`, and
`snapshot -i` returns ~70 refs (verified live 2026-05-25). So:

- **Always open the builder in a NEW tab** (`agent-browser tab new …`), never by
  re-navigating a long-lived Pinterest tab. A fresh tab inherits the logged-in
  session cookie and renders clean.
- **After every load, verify render** with the health check below. If blank,
  open another fresh tab. Do not try to "wake up" a blank tab with clicks/reloads.
- The new builder tab is a *spawned* tab; Step 10a's `close_spawned_tabs.sh`
  cleans it up automatically at the end (it is not in `essential_tabs`).

Genuinely-changed Business Hub selectors (verified from the 2026-05-25 run logs +
live recon), used below instead of snapshot @refs because ids/test-ids survive
re-renders better than refs do:

| Field | Selector |
|---|---|
| File input | `#storyboard-upload-input` |
| Title | `#storyboard-selector-title` |
| Description | Draft.js editor `[aria-label="Describe your Pin"]` (needs `execCommand`, see Step 6) |
| Link | `#WebsiteField` |
| Board open-button | `[data-test-id=board-dropdown-select-button]` |
| Publish | the enabled `button` whose text is `Publish` (eval-click, see Step 9) |

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

## Step 2: Confirm Pinterest is logged in

Make sure the persistent browser has a live Pinterest session before opening a
builder. Use the curl-based helper (NEVER `agent-browser tab list` — auto-spawn
risk; see feedback_no_agent_browser_in_cron_guard.md):

```bash
bash scripts/switch_to_platform_tab.sh "pinterest.com" "https://www.pinterest.com/"
agent-browser wait --load networkidle
```

If `agent-browser get url` returns a login URL, abort and tell the user to run
`/pinterest-login`. (We don't post from this tab — Step 3 opens a fresh builder
tab — but it confirms the session and lets `switch_to_platform_tab` repair a
totally-missing Pinterest tab.)

## Step 3: Open the pin builder in a FRESH tab + verify render

```bash
open_builder() {
  agent-browser tab new "https://www.pinterest.com/pin-creation-tool/" >/dev/null 2>&1
  agent-browser wait --load networkidle
  agent-browser wait $(bash scripts/jitter.sh 2500 4000)
}

builder_health() {
  # Returns the JSON {ready, bodyLen, login}. ready=true means the file input
  # exists AND the body actually rendered text.
  agent-browser eval "(()=>{const up=!!document.querySelector('#storyboard-upload-input');const len=(document.body.innerText||'').length;const login=/\/login|\/signup/.test(location.pathname);return JSON.stringify({ready:up&&len>0,bodyLen:len,login})})()" 2>&1 | tail -1
}

READY=false
for attempt in 1 2 3; do
  open_builder
  H=$(builder_health)
  echo "[pinterest-post] builder attempt $attempt: $H"
  echo "$H" | grep -q '"login":true' && { echo "[pinterest-post] hit a login wall — run /pinterest-login" >&2; exit 1; }
  if echo "$H" | grep -q '"ready":true'; then READY=true; break; fi
  # Blank/broken-render tab. Do NOT reload it (the rot survives reloads). Just
  # loop — open_builder spawns a brand-new tab next iteration, which renders clean.
  echo "[pinterest-post] builder tab blank (broken-render) — opening another fresh tab"
done
[ "$READY" = true ] || { echo "[pinterest-post] pin builder never rendered after 3 fresh tabs — abort" >&2; exit 1; }
```

On a healthy builder, `snapshot -i` works again if you want refs — but the
selectors in the table above are more stable, so the steps below use them.

## Step 4: Upload the media

```bash
MEDIA=$(jq -r '.media' "$1")
agent-browser upload "#storyboard-upload-input" "$MEDIA"
agent-browser wait $(bash scripts/jitter.sh 2000 4000)
# Confirm the title field enabled (it unlocks once media is attached).
agent-browser eval "(()=>{const t=document.querySelector('#storyboard-selector-title');return t?('title enabled='+!t.disabled):'no title field yet'})()"
```

If the title field never appears, the upload didn't take — re-check the media path and retry the upload once.

## Step 5: Fill the title

`#storyboard-selector-title` is a plain input — `fill` works (verified 2026-05-25).

```bash
TITLE=$(jq -r '.title' "$1")
agent-browser fill "#storyboard-selector-title" "$TITLE"
agent-browser wait $(bash scripts/jitter.sh 400 1000)
agent-browser eval "(()=>{const t=document.querySelector('#storyboard-selector-title');return 'title len='+(t?t.value.length:'?')})()"
```

## Step 6: Fill the description (Draft.js — needs execCommand)

The Business Hub description box is a **Draft.js** editor at
`[aria-label="Describe your Pin"]`. It **ignores** `agent-browser type` / `fill`
/ `inserttext` / paste events — only `document.execCommand('insertText', …)`
commits text to it. Stage the text in a `window` global first so quoting/escaping
is bulletproof (`jq` emits a JS-safe string literal):

```bash
DESC_JS=$(jq '.description' "$1")   # JSON string literal == valid JS string literal
agent-browser eval "window.__pinDesc = $DESC_JS; 'staged'"

# Some renders gate the editor behind an "Add a detailed description" control —
# click it first if the editor isn't present yet.
agent-browser eval "(()=>{const e=document.querySelector('[aria-label=\"Describe your Pin\"]');if(e)return 'editor present';const add=Array.from(document.querySelectorAll('button,[role=button]')).find(b=>/detailed description/i.test(b.textContent||''));if(add){add.click();return 'opened editor'}return 'no editor/control'})()"
agent-browser wait $(bash scripts/jitter.sh 400 900)

agent-browser eval "(()=>{const e=document.querySelector('[aria-label=\"Describe your Pin\"]');if(!e)return 'NO EDITOR';e.focus();document.execCommand('insertText',false,window.__pinDesc);return 'desc len='+(e.textContent||'').length})()"
agent-browser wait $(bash scripts/jitter.sh 400 1000)
```

If `desc len` comes back 0, re-focus and re-run the `execCommand` line once.

## Step 7: Fill the link (if present)

`#WebsiteField` is a plain input — `fill` works.

```bash
LINK=$(jq -r '.link // empty' "$1")
if [ -n "$LINK" ]; then
  agent-browser fill "#WebsiteField" "$LINK"
  agent-browser wait $(bash scripts/jitter.sh 400 1000)
fi
```

## Step 8: Pick the board

Open the dropdown via its test-id, then click the matching board by name. Stage
the board name in a `window` global (same escaping trick as the description).

**Critical**: Pinterest auto-saves the form to *drafts* on every change. Clicking
a stale control — or clicking mid-auto-save — can open the **drafts sidebar**
instead of the board dropdown, which then hijacks the form with an unrelated saved
draft (confirmed 2026-05-15). Pause so auto-save settles, then sanity-check that
the dropdown (not the drafts sidebar) opened.

```bash
BOARD=$(jq -r '.board' "$1")
BOARD_JS=$(jq '.board' "$1")
agent-browser eval "window.__pinBoard = $BOARD_JS; 'staged'"
agent-browser wait $(bash scripts/jitter.sh 800 1500)   # let auto-save commit before changing focus

# Open the board dropdown
agent-browser eval "(()=>{const b=document.querySelector('[data-test-id=board-dropdown-select-button]');if(!b)return 'NO BOARD BUTTON';b.click();return 'opened'})()"
agent-browser wait $(bash scripts/jitter.sh 700 1300)

# Did the dropdown open, or did the drafts sidebar hijack?
DROPDOWN_STATE=$(agent-browser eval "(()=>{const draft=Array.from(document.querySelectorAll('h2')).find(h=>(h.textContent||'').startsWith('Pin drafts'));const create=Array.from(document.querySelectorAll('button')).find(b=>(b.textContent||'').trim()==='Create board');return JSON.stringify({draftsSidebar:!!draft,boardDropdown:!!create})})()" 2>&1 | tail -1)
if echo "$DROPDOWN_STATE" | grep -q '"draftsSidebar":true'; then
  echo "[pinterest-post] click opened drafts sidebar (hijack!) — abort, re-run to retry" >&2
  exit 1
fi

# Click the board whose visible text matches the name exactly.
SEL=$(agent-browser eval "(()=>{const name=window.__pinBoard;const els=Array.from(document.querySelectorAll('[data-test-id*=board] [role=button],[role=button],[role=option],div'));const hit=els.find(e=>(e.textContent||'').trim()===name);if(hit){hit.click();return 'selected'}return 'not found'})()" 2>&1 | tail -1)
echo "[pinterest-post] board select: $SEL"
agent-browser wait $(bash scripts/jitter.sh 800 1500)
```

**If the board doesn't exist** (`board select: not found`), create it inline. The
create-board name input historically has DOM id `#boardEditName`:

```bash
agent-browser eval "(()=>{const c=Array.from(document.querySelectorAll('button,[role=button]')).find(b=>(b.textContent||'').trim()==='Create board');if(c){c.click();return 'create form'}return 'no create btn'})()"
agent-browser wait $(bash scripts/jitter.sh 600 1200)
agent-browser eval "document.querySelector('#boardEditName')?.focus(); 'focused'"
agent-browser fill "#boardEditName" "$BOARD"
agent-browser wait $(bash scripts/jitter.sh 600 1300)
agent-browser eval "(()=>{const s=Array.from(document.querySelectorAll('button')).find(b=>(b.textContent||'').trim()==='Create'&&!b.disabled);if(s){s.click();return 'created'}return 'no submit'})()"
agent-browser wait $(bash scripts/jitter.sh 1500 3000)
```

## Step 9: Publish

The publish action is **the enabled `button` whose text is exactly `Publish`**
(top-right, red). **Do NOT click `Create new Pin`** — that starts a fresh draft
and saves the current form as a *draft* (the sidebar shows `Pin drafts (N)`).

**Click via `eval`, not `@<ref>`.** Confirmed across 2026-05-10 and 2026-05-25
runs: `@ref` clicks on the publish button save a draft instead of publishing;
`eval`-find-by-text + `.click()` publishes. Scroll it into view first via eval
too (by publish time the form has usually grown past one viewport):

```bash
# Scroll Publish into view
agent-browser eval "(()=>{const p=Array.from(document.querySelectorAll('button')).find(b=>b.textContent.trim()==='Publish'&&!b.disabled);if(!p)return 'no publish btn';p.scrollIntoView({block:'center'});return 'scrolled'})()"
agent-browser wait $(bash scripts/jitter.sh 500 1100)

# Publish
agent-browser eval "(()=>{const p=Array.from(document.querySelectorAll('button')).find(b=>b.textContent.trim()==='Publish'&&!b.disabled);if(p){p.click();return 'clicked'}return 'no btn'})()"
agent-browser wait 8000   # publish takes 5–8s; button text flips to "Publishing" mid-flight
```

**Verify it published, don't trust the click.** Look for the toast
**"Your Pin has been published!"**. The reliable confirmation is the target
board's pin count going up (and `Pin drafts (N)` decrementing). If you instead
see `Pin drafts (N+1)`, the click saved a draft — re-scroll, re-run the eval
click once.

```bash
agent-browser eval "(()=>{const ok=document.body.innerText.includes('Your Pin has been published');return ok?'PUBLISHED':'no toast yet'})()"
```

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
  "pin_url":    "https://www.pinterest.com/<handle>/<board-slug>/",
  "builder_attempts": <n>,
  "form_fields_used": {
    "file_input":        "#storyboard-upload-input",
    "title_input":       "#storyboard-selector-title",
    "description_field": "[aria-label='Describe your Pin'] via execCommand insertText",
    "link_input":        "#WebsiteField",
    "board_button":      "[data-test-id=board-dropdown-select-button]",
    "publish_button":    "eval: button[text=Publish] .click()"
  },
  "verification_screenshot": "..."
}
```

## Step 10a: Close spawned tabs

```bash
bash scripts/close_spawned_tabs.sh "$TAB_BASELINE"
rm -f "$TAB_BASELINE"
```

This also cleans up the fresh builder tab opened in Step 3 (it is not an
`essential_tab`, so the closer removes it).

## Step 11: Report

Outcome, pin URL (the board URL is the reliable one — Business Hub doesn't always
expose a per-pin permalink immediately), screenshot path, run log path, and how
many builder-tab attempts it took (a high count is the early warning that the
broken-render rot is getting worse). **Do not close the Pinterest platform tab** —
the closer protects it via `essential_tabs`.
