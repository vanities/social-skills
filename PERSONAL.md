# Personal config — gitignored files + committed examples

This repo is structured so all PII / brand-specific content lives in **gitignored files**, with parallel **`*.example`** versions committed as templates. Fork, copy from the examples, fill in your handles + voice, and you're running.

Three layers of personal config live alongside the public code:

| What | Committed (template) | Gitignored (yours) | Purpose |
|---|---|---|---|
| **Brand** | [`config/brand.example.json`](config/brand.example.json) | `config/brand.json` | Handles, company IDs, topic regex, brand voice. Schema supports a parent org with N child brands. |
| **CLAUDE addendum** | [`CLAUDE.local.md.example`](CLAUDE.local.md.example) | `CLAUDE.local.md` | Live state, account routing, in-flight work, brand-specific decisions. Auto-loaded by Claude Code alongside `CLAUDE.md`. |
| **Composite skills + cron** | [`personal.example/`](personal.example/) | `.claude/skills/post-daily-<your-brand>/`, `scripts/daily_content.sh`, `scripts/devotional_video*.sh`, `personal/` | Brand-specific composite skills, cron entrypoints, and any helpers tied to your domain. |
| **Comment corpus** (optional) | [`personal.example/comment-corpus.brand.json`](personal.example/comment-corpus.brand.json) | `config/comment-corpus.json` (you edit it directly) | Domain-specific phrases for warm-comments. |

## Quickstart

```bash
# 1. Brand config — handles, company id, topic filters, voice
cp config/brand.example.json config/brand.json
$EDITOR config/brand.json

# 2. Personal CLAUDE addendum (auto-loaded by Claude Code)
cp CLAUDE.local.md.example CLAUDE.local.md
$EDITOR CLAUDE.local.md

# 3. Daily-content composite skill (cron-driven fan-out)
cp -R personal.example/skills/post-daily-content .claude/skills/post-daily-<your-brand>
$EDITOR .claude/skills/post-daily-<your-brand>/SKILL.md   # tailor to your iOS app + content

# 4. Cron entrypoint (calls the skill above via headless Claude Code)
cp personal.example/scripts/daily_content.sh scripts/daily_content.sh
chmod +x scripts/daily_content.sh
# Edit the last line to match your skill name: claude --print ... "/post-daily-<your-brand>"

# 5. (Optional) Comment corpus — start from the universal default in config/, OR
# import the brand-flavored example as a starting set
cat personal.example/comment-corpus.brand.json    # peek
# Either edit config/comment-corpus.json directly OR pull categories from the brand example.

# 6. (Optional) Brand-specific helpers — e.g. talking-head video pipeline
cp personal.example/scripts/devotional_video.sh scripts/devotional_video.sh
chmod +x scripts/devotional_video.sh
```

All target paths above are listed in `.gitignore`, so changes to them stay local.

## Multi-brand setup

`config/brand.json` supports an org with N child brands. Useful when you have a parent company and several products posting under it.

```json
{
  "default_brand": "myapp",
  "org": {
    "name": "My Company LLC",
    "linkedin_company_id": "12345678"
  },
  "brands": {
    "myapp": {
      "instagram": { "default_account": "myapp",     "own_handle": "myapp" },
      "x":         { "default_handle":  "myapp",     "own_handle": "myapp",
                     "topic_filter_regex": "\\b(myapp_topic_keywords)\\b",
                     "exclude_handles_substring": "" },
      "pinterest": { "default_account": "myapp",     "own_handle": "myapp",
                     "default_board":   "Main Board",
                     "feature_board":   "How To",
                     "topic_filter_regex": "\\b(myapp_topic_keywords)\\b",
                     "exclude_handles_substring": "" },
      "brand":     { "name": "My App", "url": "https://myapp.example.com",
                     "voice": "..." }
    },
    "side_project": {
      "instagram": { "default_account": "side_project", "own_handle": "side_project" },
      ...
    }
  }
}
```

Skills accept an optional brand-slug as their first arg:

```bash
/x-warm myapp           # warms the @myapp handle, with myapp's topic filter
/x-warm side_project    # warms side_project, different filter
/feature-post "shipped X" myapp linkedin,x   # cross-posts under myapp brand
```

If you don't pass a slug, skills use `default_brand`.

The LinkedIn company id sits at the **org** level, not per brand — a single company page typically represents the parent org, and feature posts for any product brand go from that page.

## Per-brand composite skills

Brand-flavored composite skills (like a daily-content fan-out) belong in `.claude/skills/post-daily-<brand>/` (gitignored). The template at `personal.example/skills/post-daily-content/` shows the shape: drive the iOS sim → screenshot → pad → extract content → caption per platform → fan out via the platform skills.

If you have multiple brands, copy the template once per brand:

```bash
cp -R personal.example/skills/post-daily-content .claude/skills/post-daily-myapp
cp -R personal.example/skills/post-daily-content .claude/skills/post-daily-side-project
```

Then customize each (different bundle id, different content extraction logic, different voice).

Each gets its own cron line:

```cron
0 12 * * * /bin/bash <repo>/scripts/daily_myapp.sh
0 14 * * * /bin/bash <repo>/scripts/daily_side_project.sh
```

(Each `daily_<brand>.sh` is a copy of `personal.example/scripts/daily_content.sh` with the last line pointing at the matching skill.)

## What lives in `personal/`

The bare `personal/` directory is gitignored entirely. Use it for anything you don't want committed but isn't covered by the structured slots above — bookmarks, scratch notes, draft captions, brand assets you keep close, etc. It has no required shape.

## Why "example" files instead of just gitignoring?

Pure gitignore would mean a fresh clone has nothing to copy from. Committing `*.example` versions means anyone forking the repo gets a working starting point — they copy, edit, and have a runnable cron in 5 minutes instead of reading skill files and rebuilding the shape from scratch.
