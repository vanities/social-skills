---
name: x-post
description: Post a tweet or a multi-tweet thread on X (Twitter) from a specific account. First arg is the X handle (no `@`); second is a path to a JSON file describing the tweets. Each entry has `text` (≤280 chars) and optional `media` (1–4 image paths). Use when the user says "post to X", "tweet this", or runs /x-post.
argument-hint: [account] [thread-json]
allowed-tools: Bash(agent-browser *) Bash(bash *) Bash(test *) Bash(date *) Bash(grep *) Bash(jq *) Bash(cat *) Bash(mkdir *) Read(*)
---

# Post to X (Twitter)

Account handle: `$0` (no `@`). **Required** — there is no default. Caller is responsible for passing the right one (see AGENTS.md account-routing rules; Claude Code also sees this through the CLAUDE.md symlink).
Thread file: `$1` — JSON array of tweet objects.

The browser may currently be signed in as a different account. This skill switches to `$0` automatically before composing — see Step 2.

## Thread file format

```json
[
  {"text": "Tweet 1 text. ≤280 chars.", "media": ["/abs/path/to/img.jpg"]},
  {"text": "Tweet 2 text.",              "media": ["/abs/path/to/img2.jpg"]},
  {"text": "Tweet 3 text. No media."},
  {"text": "Tweet 4 with a video.",      "media": ["/abs/path/clip.mp4"]}
]
```

- `text` is required. Must be ≤280 chars per tweet (URLs auto-shorten to 23 chars via t.co — count those as 23, not their literal length).
- `media` is optional. Per tweet, EITHER 1–4 image paths OR exactly 1 video. Use absolute paths.
  - Image formats: jpg, png, webp, gif (X's `input[type=file]` accepts `image/jpeg,image/png,image/webp,image/gif`).
  - Video formats: mp4, mov (`video/mp4,video/quicktime`). Hard cap: 2:20 / 512 MB. Pre-encode to h264 + AAC + faststart for clean ingest (HEVC sometimes triggers a re-transcode on X's side).
  - **Don't mix images and video in the same tweet** — X allows one or the other.
- A single-tweet post is just an array with one element.

## CRITICAL: thread strategy — reply chain, NOT multi-tweet modal

X's compose modal supports adding multiple tweets in one session (the "Add post" / "+" affordance), but **only the first tweet's file input accepts programmatic uploads**. Tweets 2+ in the same modal have `<input type=file>` elements that exist in the DOM with `multiple=false`, BUT Playwright/`setInputFiles` "succeeds" without actually populating them — X's React state never receives the file. Manual click works (file dialog → native event); programmatic injection does not.

**Workaround (verified live 2026-05-04)**: post each tweet as a reply to the previous one. Each reply opens a fresh single-tweet compose where the file input behaves normally. The result is visually identical to a thread.

```
T1 → post standalone via the sidebar "Post" link
   → grab T1's status URL from the home/profile feed
T2 → navigate to T1's detail page → click inline reply textbox → type + upload → click Reply
   → grab T2's status URL
T3 → navigate to T2's detail page → reply
```

If a future X UI change makes secondary file inputs respond to `setInputFiles`, the in-modal multi-tweet path can replace this; until then, reply-chain.

## Step 1: Sanity checks

```!
test -n "$0" || { echo "ACCOUNT MISSING — usage: /x-post <handle> <thread.json>"; exit 1; }
test -f "$1" && jq . "$1" > /dev/null && echo "thread file ok ($(jq 'length' "$1") tweets) for @$0" || echo "MISSING OR BAD JSON"
jq -r '.[].text | length' "$1" | awk '$1 > 280 { print "TOO LONG: tweet "NR" is "$1" chars"; exit 1 }' || true
jq -r '.[].media // [] | .[]' "$1" | xargs -I {} bash -c 'test -f "{}" || echo "MEDIA MISSING: {}"'
```

Abort if any check fails.

## Step 2: Find or open the X tab + switch to the right account

```bash
# Switch to the X tab via curl-based discovery (NEVER `agent-browser tab list`
# — auto-spawn risk). Helper does find + switch + URL-verify + tab-new
# fallback in one step. See feedback_no_agent_browser_in_cron_guard.md.
bash scripts/switch_to_platform_tab.sh "x.com" "https://x.com/home"
agent-browser wait --load networkidle

# CRITICAL: switch the X session to the requested account if it isn't already.
# The browser may have been left on a different account between runs. Without
# this, a noon cron could post under the wrong handle (any other signed-in
# account). The helper is a no-op when already on target.
bash scripts/x_switch_account.sh "$0"
```

```!
agent-browser get url
```

If `/i/flow/login`, abort and tell the user to run `/x-login`. If `x_switch_account.sh` exits non-zero, abort and tell the user the target account isn't in the popover (sign in manually first).

## Step 3: Compose tweet 0 (the root)

```bash
agent-browser snapshot -i 2>&1 | grep -E 'Post.*ref' | head -3   # find sidebar Post link, ~@e16
agent-browser click @<POST_LINK_REF>
agent-browser wait $(bash scripts/jitter.sh 700 1500)
```

The compose modal opens with one **"Post text"** textbox. **Refs shift on every action** — always re-snapshot before each click/type. **Re-snapshot specifically before clicking the Post button** — its ref shifts after media upload, and clicking a stale ref silently no-ops without an error (you'll be left on `x.com/compose/post` with the modal still open). Confirmed live 2026-05-07.

```bash
TEXT0=$(jq -r '.[0].text' "$1")
MEDIA0=$(jq -r '.[0].media // [] | .[]' "$1")    # newline-separated when multiple
agent-browser click "@<TEXTBOX>"
agent-browser wait $(bash scripts/jitter.sh 300 700)
agent-browser focus "@<TEXTBOX>"
agent-browser keyboard type "$TEXT0"             # NOT `type @ref` — X uses Lexical contenteditable; `type` swallows newlines into a run-on
agent-browser wait $(bash scripts/jitter.sh 600 1300)
```

If `MEDIA0` is non-empty, upload (the **first** input supports `multiple=true` for up to 4 images in a single tweet, OR exactly 1 video):

```bash
# Use the testid selector — `input[type=file]` matches TWO file inputs in
# this DOM (one in the modal, one stale on x.com/home), and the upload may
# silently set the file on the stale one. Confirmed live 2026-05-10: image
# never attached when targeting `input[type=file]`; switching to the testid
# selector fixed it. Both candidates have data-testid=fileInput, but
# Playwright/`setInputFiles` consistently picks the active modal one when
# this selector is used.
agent-browser upload "input[data-testid=fileInput]" $MEDIA0
agent-browser wait $(bash scripts/jitter.sh 1500 3000)

# VERIFY the attachment preview rendered before continuing — if upload silently
# failed, attachment preview won't be there and the post will go up text-only.
HAS_MEDIA=$(agent-browser eval "(()=>{const dialog=document.querySelector('[role=dialog]')||document;const blob=Array.from(dialog.querySelectorAll('img')).find(i=>i.src.startsWith('blob:'));return blob?'yes':'no'})()" 2>&1 | tail -1 | tr -d '"')
if [ "$HAS_MEDIA" != "yes" ]; then
  echo "[x-post] media upload didn't attach — retrying once" >&2
  agent-browser upload "input[data-testid=fileInput]" $MEDIA0
  agent-browser wait $(bash scripts/jitter.sh 1500 3000)
fi
```

**For video uploads, wait for processing to complete before clicking Post.** X's compose modal exposes upload status via `[data-testid=attachments]` ("Processing 50%" → "Uploaded (100%)"); the Post button stays disabled until processing finishes. Poll:

```bash
for i in 1 2 3 4 5 6 7 8 9 10; do
  agent-browser wait 3000
  STATE=$(agent-browser eval "(()=>{const a=document.querySelector('[data-testid=attachments]');return a?a.textContent.slice(0,200):'no attachment'})()" 2>&1 | tail -1)
  echo "[$i] $STATE"
  if echo "$STATE" | grep -qE 'Uploaded \(100%\)' && ! echo "$STATE" | grep -qE 'Processing'; then
    echo "✓ video ready"
    break
  fi
done
```

**Click Post via its `data-testid`, NOT via @ref.** Refs shift after upload, AND even a freshly-snapshotted `@<POST_BUTTON_REF>` can silently no-op (confirmed live 2026-05-10: clicked the just-snapshotted ref, URL stayed at `x.com/compose/post`; clicking via `[data-testid=tweetButton]` worked first try). The testid is stable across renders.

```bash
agent-browser wait $(bash scripts/jitter.sh 1500 3500)
agent-browser eval "document.querySelector('[data-testid=tweetButton]:not([disabled])').click()"
agent-browser wait 5000

# Verify the modal closed (URL flipped off /compose/post). If we're still
# there, click again — the click can race with React state finishing the
# media-attachment commit on slow runs.
URL=$(agent-browser get url 2>&1 | tail -1)
if echo "$URL" | grep -q '/compose/post'; then
  echo "[x-post] Post click no-op'd — retrying" >&2
  agent-browser eval "document.querySelector('[data-testid=tweetButton]:not([disabled])').click()"
  agent-browser wait 5000
fi
```

After the post, a "Your post was sent. View" toast appears. X may also surface a graduated-access modal ("Unlock more on X") on new accounts — dismiss it with the **"Got it"** button.

## Step 4: For each subsequent tweet — reply chain

For `i` from 1 to `n-1`:

a. **Find the previous tweet's status URL.** Navigate to the active account's profile to read it:

```bash
agent-browser open "https://x.com/$0"   # $0 is the handle the skill was invoked with
agent-browser wait --load networkidle
PREV_URL=$(agent-browser eval "Array.from(document.querySelectorAll('a[href*=\"/status/\"]')).map(a=>a.href.match(/\\/status\\/\\d+\$/)?.[0]).filter(Boolean)[0]" 2>&1 | tail -2 | head -1 | tr -d '"')
agent-browser open "https://x.com${PREV_URL}"
agent-browser wait --load networkidle
```

(Alternative: capture the tweet id from `Array.from(...)` after each post and remember it, instead of re-reading from the profile each time.)

b. **Compose the reply** — the inline reply composer has a `Post your reply` textbox and a single `Reply` button. Only ONE `<input type=file>` exists on this page (the reply's own), so plain `input[type=file]` works:

```bash
TEXT_I=$(jq -r ".[$i].text" "$1")
MEDIA_I=$(jq -r ".[$i].media // [] | .[]" "$1")
agent-browser snapshot -i 2>&1 | grep -E 'Post text|Reply.*ref' | head -5
agent-browser click "@<REPLY_TEXTBOX>"
agent-browser wait $(bash scripts/jitter.sh 300 700)
agent-browser focus "@<REPLY_TEXTBOX>"
agent-browser keyboard type "$TEXT_I"            # NOT `type @ref` — preserves newlines
agent-browser wait $(bash scripts/jitter.sh 600 1300)

if [ -n "$MEDIA_I" ]; then
  agent-browser upload "input[type=file]" $MEDIA_I
  agent-browser wait $(bash scripts/jitter.sh 1500 3000)
  # Video reply: poll [data-testid=attachments] for "Uploaded (100%)" before continuing (see Step 3).
fi
```

c. **Re-snapshot, find live Reply button, click.** (The Reply button ref shifts after typing/uploading; clicking a stale ref silently no-ops.)

```bash
agent-browser snapshot -i 2>&1 | grep -E 'Reply.*ref' | head -5
agent-browser wait $(bash scripts/jitter.sh 1500 3500)
agent-browser click "@<LIVE_REPLY_BUTTON>"
agent-browser wait 5000
```

Verify the "Your post was sent" toast. If absent, re-snapshot and re-click Reply (the click on a stale ref happens occasionally).

## Step 6: Verify

```!
agent-browser get url
```

Expected: still on `x.com/home` (or wherever you started). Snapshot — a "Your post was sent" toast or the disappearance of the modal indicates success.

```!
agent-browser screenshot /tmp/x-post-default-$(date +%Y-%m-%dT%H%M%S).png
```

## Step 7: Run log

Use `Write` to create `~/.social-skills/logs/post/x-$0-<timestamp>.json`:

```json
{
  "ts_start": "...",
  "ts_end":   "...",
  "platform": "x",
  "account":  "$0",
  "action":   "post",
  "outcome":  "success | failed",
  "thread_file": "$1",
  "tweet_count": <n>,
  "tweet_lengths": [<chars>, ...],
  "media_per_tweet": [<count>, ...],
  "account_switch": {
    "needed":  "true | false",
    "before":  "<handle that was active before this run>"
  },
  "form_fields_used": {
    "post_link":          "@<ref>",
    "tweet_textbox_refs": ["@<ref>", ...],
    "file_input_used":    "input[type=file]",
    "add_post_buttons":   ["@<ref>", ...],
    "post_button":        "@<ref>"
  },
  "verification_screenshot": "..."
}
```

## Step 8: Report

Outcome, tweet count, screenshot path, run log path. **Do not close the tab.**
