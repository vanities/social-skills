---
name: post-daily-devotional
description: Take a screenshot of the iOS simulator's daily devotional and post it to Instagram. Use when the user says "post the devotional", "publish today's devotional", or runs /post-daily-devotional.
disable-model-invocation: true
allowed-tools: Bash(xcrun simctl*) Bash(agent-browser *) Bash(test *) Bash(date *) Bash(ls *) Bash(cat *) Bash(mkdir *) Skill(instagram-post *)
---

# Post today's iOS-simulator devotional to Instagram

Account: `swiftbible` (override via `$SOCIAL_AGENTS_IG_ACCOUNT`).
Reference: `docs/platforms/instagram.md`.

## Step 1: Verify the simulator is booted

```!
xcrun simctl list devices | grep -q '(Booted)' && echo "ok" || echo "NO BOOTED SIMULATOR"
```

If `NO BOOTED SIMULATOR`, abort and tell the user to boot one in Xcode first.

## Step 2: Capture the screen

```!
SHOT="/tmp/daily-devotional-$(date +%Y-%m-%d).png"
xcrun simctl io booted screenshot "$SHOT"
ls -lh "$SHOT"
```

## Step 2b: Pad to 4:5 for Instagram

Raw iPhone screenshots are ~9:19.5 — IG's auto-crop chops important top/bottom content. Pad to 4:5 first:

```!
SHOT="/tmp/daily-devotional-$(date +%Y-%m-%d).png"
PADDED=$(bash scripts/pad_ios_screenshot.sh "$SHOT" "/tmp/daily-devotional-$(date +%Y-%m-%d)-4x5.jpg" edge)
ls -lh "$PADDED"
```

Use `$PADDED` (the 4:5 version) for the post in step 4, not `$SHOT`.

## Step 3: Read the caption (optional)

```!
test -f ~/.social-agents/daily-devotional-caption.txt && cat ~/.social-agents/daily-devotional-caption.txt || echo ""
```

## Step 4: Post via the instagram-post skill

Invoke `/instagram-post` with:

- account = `${SOCIAL_AGENTS_IG_ACCOUNT:-swiftbible}`
- media = `/tmp/daily-devotional-$(date +%Y-%m-%d)-4x5.jpg` (the padded version from step 2b)
- caption = output of step 3 (empty string if the file didn't exist)

## Verification and reporting

After `/instagram-post` completes, summarize:

- Screenshot path uploaded.
- Outcome (success / specific failure step).
- Path of the verification screenshot from `/instagram-post`.

If `/instagram-post` reported "STATE MISSING", tell the user to run `/instagram-login ${SOCIAL_AGENTS_IG_ACCOUNT:-swiftbible}` first.
