# social-agents

Skill-driven social media automation. The agent (Claude Code, OAuth-authed) does the work; this repo provides the playbook.

```
┌──────────────────────────────────────────────────────────┐
│  Trigger: /post-daily-devotional, cron, manual           │
│                       │                                  │
│                       ▼                                  │
│  Skill (.claude/skills/<name>/SKILL.md)                  │
│       │  reads platform docs (docs/platforms/*.md)       │
│       ▼                                                  │
│  Agent (Claude Code, OAuth-authed — no API key)          │
│       │  drives                                          │
│       ▼                                                  │
│  agent-browser CLI  →  real Chrome with persistent state │
│       ▼                                                  │
│  Instagram / TikTok / LinkedIn / X                       │
└──────────────────────────────────────────────────────────┘
```

No Python framework. No platform APIs. No `ANTHROPIC_API_KEY`.

## Prerequisites

- macOS (for iOS-simulator screenshots in the daily-devotional flow)
- Claude Code (`claude` CLI), authenticated
- `agent-browser` CLI on `PATH`

## Setup

```bash
cp .env.example .env  # only if you want to override defaults
```

That's it. Skills do the rest.

## Skills

| Skill | What it does |
|---|---|
| `/instagram-login <account>` | One-time manual login. You sign in by hand; state is saved for future runs. |
| `/instagram-post <account> <media-path> <caption>` | Post media + caption using a saved session. |
| `/post-daily-devotional` | Screenshot iOS simulator → post to Instagram. Composes `/instagram-post`. |

## Daily devotional, scheduled at noon

Local cron (the `/schedule` slash command runs *remote* agents and can't see your simulator — local cron is the right tool here).

```cron
0 12 * * * /bin/bash /Users/vanities/git/work/me/social-agents/scripts/daily_devotional.sh
```

Install:

```bash
( crontab -l 2>/dev/null; echo "0 12 * * * /bin/bash /Users/vanities/git/work/me/social-agents/scripts/daily_devotional.sh" ) | crontab -
```

The script invokes `claude --print "/post-daily-devotional"` so the skill is what actually runs — adaptive to UI changes.

## Logs

| Log | Source |
|---|---|
| `~/.social-agents/logs/cron/<date>.log` | Shell-level errors before Claude starts; also captures the headless `claude --print` stdout |
| `~/.config/agent-browser/instagram-<account>.json` | Saved browser state per account |
| `/tmp/daily-devotional-<date>.png` | Today's simulator screenshot |
| `/tmp/instagram-post-<account>-<timestamp>.png` | Verification screenshot from `/instagram-post` |

Tail today's run:

```bash
tail -f ~/.social-agents/logs/cron/$(date +%Y-%m-%d).log
```

## Layout

```
social-agents/
├── README.md
├── .env.example
├── docs/platforms/
│   └── instagram.md           ← reusable IG playbook (URLs, steps, anti-bot notes)
├── scripts/
│   └── daily_devotional.sh    ← cron entrypoint
└── .claude/skills/
    ├── instagram-login/SKILL.md
    ├── instagram-post/SKILL.md
    └── post-daily-devotional/SKILL.md
```

## Adding a platform

1. Write `docs/platforms/<name>.md` — URLs, steps, anti-bot notes.
2. Add skills `.claude/skills/<name>-login/SKILL.md`, `.claude/skills/<name>-post/SKILL.md`, etc. Link to the playbook.
3. Wire into composite flows (`/post-daily-devotional`-style) as needed.

## Status

- [x] Instagram: login, post, daily devotional
- [x] Cron at noon
- [ ] TikTok / LinkedIn / X playbooks
- [ ] Search / like / follow / comment skills
- [ ] Auto-caption from screenshot via vision
