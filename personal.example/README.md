# personal.example/

Templates for the brand-specific files this repo expects you to provide. Everything here is committed as a starting point; the parallel files **you** edit live at gitignored paths so your handles, voice, and live state never make it into the public history.

See [`PERSONAL.md`](../PERSONAL.md) at the repo root for the full pattern. Quick recipe:

```bash
# 1. Brand config — handles, IDs, topic filters
cp config/brand.example.json config/brand.json
$EDITOR config/brand.json

# 2. Personal Claude Code addendum — Claude Code auto-loads CLAUDE.local.md
cp CLAUDE.local.md.example CLAUDE.local.md   # at the repo root, next to CLAUDE.md (symlink to AGENTS.md)
$EDITOR CLAUDE.local.md

# 3. Domain-specific composite skill (cron-driven daily content)
cp -R personal.example/skills/post-daily-content skills/post-daily-content
$EDITOR skills/post-daily-content/SKILL.md

# 4. Cron entrypoint (calls the skill above via headless Claude Code)
cp personal.example/scripts/daily_content.sh scripts/daily_content.sh
chmod +x scripts/daily_content.sh

# 5. (Optional) Domain-specific comment corpus for /warm skills
#    — strict pipeline, see config/comment-corpus.json header for rules.
cp personal.example/comment-corpus.brand.json config/comment-corpus.brand.json

# 6. (Optional) Brand-specific helpers — e.g. talking-head video pipeline
cp personal.example/scripts/devotional_video.sh scripts/devotional_video.sh
chmod +x scripts/devotional_video.sh
```

All target paths above are listed in `.gitignore`, so changes to them stay local.

## What's in here

| File | Purpose |
|---|---|
| `comment-corpus.brand.json` | Sample domain-specific comment phrases (Christian / devotional flavor). The committed `config/comment-corpus.json` ships with universal phrases only; this file shows what a curated brand-flavored set looks like. |
| `scripts/daily_content.sh` | Sample cron wrapper — generic shape, runnable as-is once you point it at your skill. |
| `scripts/devotional_video.sh` | Sample brand-specific helper — turns iPhone screenshot + narration text into a 9:16 mp4 via local TTS + ffmpeg. Replace narration source / branding for your domain. |
| `scripts/devotional_video_remote.sh` | Variant of the above using a remote talking-head inference server (Hallo2). Keep, replace, or delete. |
| `skills/post-daily-content/SKILL.md` | Sample composite skill — drives an iOS sim to capture today's content, drafts captions, fans out to IG / X / Pinterest. Originally built for a Bible-app daily devotional; the structure is reusable for any iOS-app daily-content workflow. |

## Why "example", why not just gitignore?

If we gitignored brand-specific files outright, a fresh clone would have nothing to copy from. Having `personal.example/` committed means anyone forking the repo gets a working starting point — they can copy, edit, and have a runnable cron in 5 minutes instead of reading skill files and rebuilding the shape from scratch.
