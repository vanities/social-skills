---
name: instagram-post
description: Post a media file to Instagram with a caption. Operates against the shared headed Chrome — finds the existing Instagram tab if one is open, otherwise opens one. Use when the user says "post X to Instagram" or runs /instagram-post.
disable-model-invocation: true
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

## Step 2: Find or open the Instagram tab

```!
agent-browser tab list 2>&1
```

From the output:

- If a tab matches `https://www.instagram.com/`, switch to it: `agent-browser tab <index>`.
- If no IG tab is open: `agent-browser tab new https://www.instagram.com/` and wait for load.
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

When the upload dialog is reachable, click **"Select from computer"**. Then upload `$1`.

`agent-browser upload <file-input-ref> "$1"` for the file input (this one is *not* a human-typed field, so plain upload is correct). Wait jitter after:

```bash
agent-browser wait $(bash scripts/jitter.sh 800 1800)
```

## Step 6: Skip crop / edit screens

Click **"Next"** through any crop, filter, or edit screens until the caption screen appears. Re-snapshot between clicks. Wait jitter between each:

```bash
agent-browser wait $(bash scripts/jitter.sh 600 1400)
```

## Step 7: Enter the caption

Use `type` (real keystrokes), not `fill` — captions are user-typed content and should look that way. Find the caption textarea `@ref` and:

```text
agent-browser type @<caption-ref> "$2"
```

Then:

```bash
agent-browser wait $(bash scripts/jitter.sh 800 1600)
```

## Step 8: Share

Wait jitter (humans pause to re-read before posting), then click **Share**:

```bash
agent-browser wait $(bash scripts/jitter.sh 1500 3500) && \
agent-browser click @<share-ref> && \
agent-browser wait 3000
```

## Step 9: Verify and write the run log

```!
agent-browser screenshot /tmp/instagram-post-$0-$(date +%Y-%m-%dT%H%M%S).png
```

Use the `Write` tool to create `~/.social-agents/logs/post/instagram-$0-<timestamp>.json`:

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
