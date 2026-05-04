---
name: tiktok-post
description: Post to TikTok. CURRENTLY DEFERRED — TikTok's web upload is video-only; Photo Mode (image carousels) is mobile-app exclusive. This skill documents the state and the three paths forward. Read it before attempting anything TikTok-related.
disable-model-invocation: true
argument-hint: [media] [caption]
allowed-tools: Bash(agent-browser *) Bash(test *) Bash(date *)
---

# TikTok post — DEFERRED

> **Don't try to run this yet.** The web upload doesn't accept images, and we don't have a video pipeline. This skill is documentation; the actual implementation comes after one of the unblocking paths below.

## Why deferred

The TikTok web upload at `https://www.tiktok.com/upload` redirects to `https://www.tiktok.com/tiktokstudio/upload`. The file input there is:

```json
{ "accept": "video/*", "multiple": false }
```

No `/upload?photo`, no toggle on the page, no `/create` alternative. The word "photo" doesn't appear anywhere on the upload page. **Photo Mode (image carousels, up to 35 images) exists only in the mobile app.**

Browser automation against the web upload would only let us post videos. Since the existing content is iPhone screenshots (still images), we can't post anything until one of the paths below is taken.

## Account state

- Handle: `@swiftbible` — note the **lack of underscore**, different from `@swift_bible` on IG / X.
- Login: done manually 2026-05-04 (TikTok web sign-in is genuinely painful — CAPTCHAs, slider puzzles, email verification — auto-login is not worth attempting).
- State file: `~/.config/agent-browser/tiktok-default.json` (~539 KB; much larger than other platforms because TikTok stores a lot of fingerprinting cookies).
- Bio: "📖 Daily devotionals from the Swift Bible app. New every day at noon." (link field: `am2.biz/swiftbible`).

## Paths forward (pick one before this skill becomes runnable)

### Path A — Build a real video pipeline (best long-term)

Create animated screenshots + voiceover videos (e.g. `scripts/screenshots_to_short_video.sh`):

- Stitch screenshots into a 15–30s vertical (9:16) clip with slow Ken Burns zoom + fade transitions
- TTS the devotional text via `say` (macOS) or ElevenLabs API for higher quality
- Burn in captions for accessibility / scroll-readability
- Add background music (royalty-free or TikTok-licensed)
- Export as `mp4`, `1080×1920`, `<60s`

Unlocks **TikTok + YouTube Shorts + IG Reels + Pinterest Idea Pins** all at once. Probably 4–8 hours of work to get something good.

### Path B — Simple image-to-video helper (stopgap)

`scripts/screenshots_to_video.sh <screenshot...>` produces a quick vertical slideshow (5–10s, no audio or with a `say`-generated VO):

```bash
ffmpeg -y \
  -loop 1 -t 4 -i 01.jpg \
  -loop 1 -t 4 -i 02.jpg \
  -filter_complex "[0:v]scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:-1:-1:color=white,zoompan=z='min(zoom+0.0008,1.1)':d=120[v0]; \
                   [1:v]scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:-1:-1:color=white,zoompan=z='min(zoom+0.0008,1.1)':d=120[v1]; \
                   [v0][v1]xfade=transition=fade:duration=0.5:offset=3.5,format=yuv420p" \
  -r 30 -c:v libx264 out.mp4
```

Then post via the standard web upload (video, single file). ~30–60 min.

### Path C — iOS app automation via XcodeBuildMCP

Install the TikTok app in the simulator, drive it with `tap` / `swipe` / `screenshot`. Photo Mode is supported in-app, so this would post real image carousels.

Caveats:
- TikTok detects iOS Simulator (no real cellular IP, no IDFA, no real device fingerprint) and may shadow-ban the account
- The mobile app updates frequently, breaking accessibility-label-based automation
- Account login on simulator faces the same CAPTCHA hell

Probably the riskiest of the three. Worth trying ONLY if Paths A and B don't fit.

## When this skill IS implemented

Whichever path is taken, the skill should follow the same pattern as `/instagram-post` / `/x-post`:

1. Sanity-check media exists.
2. `agent-browser tab list` → switch to TikTok tab (or open `https://www.tiktok.com/tiktokstudio/upload`).
3. If `agent-browser get url` doesn't show TikTok as logged in, abort and tell user to manually re-sign-in (don't try to auto-login).
4. Upload via `agent-browser upload "input[type=file]" <video-path>` (single file, video/*).
5. Wait for processing, fill caption (real keystrokes via `type`), set privacy/options.
6. Click Post, verify, write run log.

Until then: this file is the canonical record of why TikTok isn't shipping yet.
