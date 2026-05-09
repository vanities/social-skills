---
name: reddit-post
description: Post to a single subreddit. STUB — Reddit fundamentally breaks the cross-post / cron / warm patterns the other skills assume; this file documents why and what shape the skill should take when actually used. Read it before attempting anything Reddit-related. Use when the user says "post to reddit", "submit to r/<sub>", or runs /reddit-post.
disable-model-invocation: true
argument-hint: [subreddit] [title] [body-or-url]
allowed-tools: Bash(agent-browser *) Bash(test *) Bash(date *) Bash(grep *) Bash(mkdir *) Read(*) Write(*)
---

# Reddit post — STUB (architecturally different from every other platform)

> **Don't auto-fan or cron this.** Reddit's spam systems will shadow-ban accounts that behave like the rest of our platforms. This skill is for hand-crafted, one-at-a-time posts to specific subreddits where you've already built karma.

## Why this is different from `/x-post`, `/instagram-post`, etc.

Three structural problems that the existing skills' patterns can't survive:

1. **Self-promotion is heavily policed.** Most relevant subs (r/Christianity, r/iOSProgramming, r/SideProject, r/SaaS, r/IndieDev) enforce a 10:1 rule — 10 contributing comments for every self-promo post. A daily-devotional fan-out post would be flagged as spam within days. Cross-posting the same content to multiple subs is one of the most heavily flagged behaviors.
2. **Each sub has its own culture.** A "I built this, here's the technical post-mortem" post that thrives in r/SwiftUI tanks in r/Christianity, and vice versa. The "draft once, fan to all" pattern that works for IG / LinkedIn / X **breaks here.** Every Reddit post must be hand-crafted to its sub.
3. **Bot detection is aggressive.** Reddit flags new accounts that have no comment history but suddenly start posting links. Karma must be earned manually first; automation can't shortcut this.

## What this skill is NOT

- ❌ Not called by `/post-daily-devotional` (would get the account banned).
- ❌ Not called by `/feature-post` (cross-platform fan-out doesn't apply).
- ❌ Not paired with `/reddit-warm` (auto-engagement triggers spam filters faster than auto-posting).
- ❌ Not cron-fired.

## What this skill IS

A **single-shot post helper**. The user picks a subreddit they've already participated in, drafts a post in the sub's specific voice, and the skill submits it.

Typical usage:

```
/reddit-post SideProject "DocVault: a self-hosted finance + document workspace I built solo" \
  "Hey r/SideProject. I've been building DocVault for the last few months — it's a Mac/Linux/web tool that ingests …"
```

The body can be Markdown (Reddit's markdown subset) or a URL (link post).

## Pre-flight: account is ready

Before invoking this skill the FIRST time:

1. Reddit account exists and is logged in via `/reddit-login` (state at `~/.config/agent-browser/reddit-default.json`).
2. **The account has at least 2-3 weeks of organic comment activity in the target sub.** Not optional. Reddit's spam classifier weighs account age + comment history heavily.
3. The subreddit's posting rules have been read (every sub has a wiki / sidebar with format requirements: flair, title format, no self-promo days, etc.). Many subs require flair on every post and reject unflaired ones immediately.

If any of those isn't true, **abort and tell the user**. Do not paper over with retries.

## Right shape when implemented

### Step 1: Sanity checks

```bash
SUB="$1"
TITLE="$2"
BODY="$3"

[ -n "$SUB" ] && [ -n "$TITLE" ] && [ -n "$BODY" ] || { echo "missing args"; exit 1; }
[ ${#TITLE} -le 300 ] || { echo "title too long (Reddit cap: 300 chars)"; exit 1; }
```

### Step 2: Switch to Reddit tab

```bash
agent-browser tab list 2>&1 | head -10
# Switch into the reddit.com tab; if none: tab new https://www.reddit.com/
```

If `agent-browser get url` returns a login page, abort with "run /reddit-login first".

### Step 3: Navigate to the submit page

```bash
agent-browser open "https://www.reddit.com/r/${SUB}/submit"
agent-browser wait --load networkidle
agent-browser wait $(bash scripts/jitter.sh 1500 3000)
```

If Reddit redirects to a "you can't post here" page (sub is private / restricted / you're banned), abort cleanly with the error.

### Step 4: Pick post type — link vs text

Detect from `$BODY`: if it's a URL (`^https?://`), use the **Link** tab; otherwise **Post** (text). Reddit's submit page has tabs `Post` / `Images & Video` / `Link` / `Poll`.

### Step 5: Fill title + body, attach flair if required

```bash
# Title
agent-browser type @<TITLE_REF> "$TITLE"
agent-browser wait $(bash scripts/jitter.sh 400 1000)

# Body or URL
agent-browser type @<BODY_OR_URL_REF> "$BODY"
agent-browser wait $(bash scripts/jitter.sh 600 1500)
```

**If the sub requires flair** (most do), there's an "Add flair" button that opens a picker. The skill should prompt the user for the flair value if it's not passable as a 4th arg, OR fail with a clear message and a list of available flairs (read from the picker).

### Step 6: Post

```bash
agent-browser wait $(bash scripts/jitter.sh 1500 3500)
agent-browser click "@<POST_BUTTON_REF>"
agent-browser wait 5000
```

### Step 7: Verify + run log

After submission, capture the new post URL (Reddit redirects to `/r/<sub>/comments/<id>/<slug>/`). Save to `~/.social-skills/logs/post/reddit-default-<ts>.json`. **Manually check the post in the next few hours** — Reddit can shadow-remove it (visible only to you) without notification.

## Failure modes specific to Reddit

- **AutoModerator removal**: subs run AutoMod scripts that remove posts not matching format. If your post disappears within a minute, check the sub's modlog or the sticky "post requirements" thread.
- **Shadowban**: account-level Reddit ban that's invisible to the affected user. Test: log out, view your profile in incognito. If posts don't appear, you're shadowbanned — this is hard to recover from.
- **Karma threshold**: many subs require minimum comment karma (e.g. 10 in their sub or 100 globally). Posts from accounts under threshold are auto-removed.
- **Cooldowns**: Reddit rate-limits posts (especially link posts) per-sub. Don't post to the same sub more than 1-2× per week.
- **Rule against posting your own content**: r/Christianity for instance disallows linking to your own app/blog. Read every sub's rules.

## Status

🚫 **Stub only — not yet implemented.** When you're ready to use Reddit (account warmed, target subs identified, sub rules read), come back and fill in the @ref discovery in steps 3-6. Probably ~1 hour to wire up; the content production per post is the real cost.
