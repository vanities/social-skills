---
name: instagram-post
description: Post a media file to Instagram with a caption using a saved session. Use when the user says "post X to Instagram" or runs /instagram-post.
disable-model-invocation: true
argument-hint: [account] [media-path] [caption]
allowed-tools: Bash(agent-browser *) Bash(test *) Bash(ls *) Bash(date *)
---

# Post to Instagram

Account: `$0`
Media: `$1`
Caption: `$2`

Reference: `docs/platforms/instagram.md`.

## Step 1: Sanity checks

```!
test -f ~/.config/agent-browser/instagram-$0.json && echo "state ok" || echo "STATE MISSING — run /instagram-login $0 first"
test -f "$1" && echo "media ok" || echo "MEDIA MISSING at $1"
```

If either fails, abort and tell the user.

## Step 2: Open Instagram with the saved session

```!
agent-browser state load ~/.config/agent-browser/instagram-$0.json
agent-browser open https://www.instagram.com/
agent-browser wait --load networkidle
agent-browser snapshot -i
```

## Step 3: Click "Create"

Read the snapshot above. Find the "Create" button (a `+` / compose icon, usually in the left sidebar). Click its `@ref`. After each navigation step, re-run `snapshot -i` to get fresh refs.

## Step 4: Upload the media

When the upload dialog is reachable, click "Select from computer", then upload `$1`. If `agent-browser upload` is available, use it; otherwise find the `<input type=file>` `@ref` via snapshot and fill it with the path.

## Step 5: Skip crop / edit screens

Click "Next" through any crop, filter, or edit screens until the caption screen appears.

## Step 6: Enter the caption

Find the caption textarea `@ref` and run:

```text
agent-browser fill @<caption-ref> "$2"
```

(Substitute the actual ref from the latest snapshot.)

## Step 7: Share

Find the "Share" button `@ref` and click it. Wait for the dialog to close.

## Step 8: Verify and clean up

```!
agent-browser screenshot /tmp/instagram-post-$0-$(date +%Y-%m-%dT%H%M%S).png
agent-browser close
```

Report:
- The verification screenshot path.
- Whether the post is visible on the profile grid.
- Any error encountered, with the failing step number.
