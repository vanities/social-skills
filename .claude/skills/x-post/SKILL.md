---
name: x-post
description: Post a tweet or a multi-tweet thread on X (Twitter). The single argument is a path to a JSON file describing the tweets. Each entry has `text` (≤280 chars) and optional `media` (1–4 image paths). Use when the user says "post to X", "tweet this", or runs /x-post.
disable-model-invocation: true
argument-hint: [thread-json]
allowed-tools: Bash(agent-browser *) Bash(test *) Bash(date *) Bash(grep *) Bash(jq *) Bash(cat *) Bash(mkdir *) Read(*)
---

# Post to X (Twitter)

Account: `default` (single X account; add per-account split if a second one is added).
Thread file: `$1` — JSON array of tweet objects.

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
test -f "$1" && jq . "$1" > /dev/null && echo "thread file ok ($(jq 'length' "$1") tweets)" || echo "MISSING OR BAD JSON"
jq -r '.[].text | length' "$1" | awk '$1 > 280 { print "TOO LONG: tweet "NR" is "$1" chars"; exit 1 }' || true
jq -r '.[].media // [] | .[]' "$1" | xargs -I {} bash -c 'test -f "{}" || echo "MEDIA MISSING: {}"'
```

Abort if any check fails.

## Step 2: Find or open the X tab

```bash
# Find the X tab via curl-only — NEVER `agent-browser tab list`.
# See feedback_no_agent_browser_in_cron_guard.md for the why.
TAB_INDEX=$(bash scripts/find_platform_tab.sh "x.com" 2>/dev/null || \
            bash scripts/find_platform_tab.sh "twitter.com" 2>/dev/null || true)
if [ -n "$TAB_INDEX" ]; then
  agent-browser tab "$TAB_INDEX"
else
  agent-browser tab new "https://x.com/home"
fi
agent-browser wait --load networkidle
```

```!
agent-browser get url
```

If `/i/flow/login`, abort and tell the user to run `/x-login`. Otherwise wait `--load networkidle`.

## Step 3: Compose tweet 0 (the root)

```bash
agent-browser snapshot -i 2>&1 | grep -E 'Post.*ref' | head -3   # find sidebar Post link, ~@e16
agent-browser click @<POST_LINK_REF>
agent-browser wait $(bash scripts/jitter.sh 700 1500)
```

The compose modal opens with one **"Post text"** textbox. **Refs shift on every action** — always re-snapshot before each click/type.

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
agent-browser upload "input[type=file]" $MEDIA0
agent-browser wait $(bash scripts/jitter.sh 1500 3000)
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

**Re-snapshot immediately before clicking Post** — refs shift after upload AND clicking a stale Post button silently no-ops. The freshest ref is the one to click.

```bash
agent-browser wait $(bash scripts/jitter.sh 1500 3500)
agent-browser click "@<POST_BUTTON_REF>"
agent-browser wait 5000
```

After the post, a "Your post was sent. View" toast appears. X may also surface a graduated-access modal ("Unlock more on X") on new accounts — dismiss it with the **"Got it"** button.

## Step 4: For each subsequent tweet — reply chain

For `i` from 1 to `n-1`:

a. **Find the previous tweet's status URL.** Navigate to the profile to read it:

```bash
agent-browser open https://x.com/swift_bible
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

Use `Write` to create `~/.social-agents/logs/post/x-default-<timestamp>.json`:

```json
{
  "ts_start": "...",
  "ts_end":   "...",
  "platform": "x",
  "account":  "default",
  "action":   "post",
  "outcome":  "success | failed",
  "thread_file": "$1",
  "tweet_count": <n>,
  "tweet_lengths": [<chars>, ...],
  "media_per_tweet": [<count>, ...],
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
