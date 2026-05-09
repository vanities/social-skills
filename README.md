# social-skills

*because I'm terrible at being social.*

Skill-driven social media automation. The agent (Claude Code, OAuth-authed) does the work; this repo provides the playbook.

```
┌────────────────────────────────────────────────────────────┐
│  Trigger: cron / interactive slash command                 │
│                       │                                    │
│                       ▼                                    │
│  Skill (.claude/skills/<name>/SKILL.md)                    │
│       │  reads platform docs (docs/platforms/*.md)         │
│       ▼                                                    │
│  Agent (Claude Code, OAuth-authed — no API key)            │
│       │  drives                                            │
│       ▼                                                    │
│  agent-browser CLI  →  real Chrome (persistent profile)    │
│       ▼                                                    │
│  Instagram / LinkedIn / X / Pinterest                      │
└────────────────────────────────────────────────────────────┘
```

**Hard rules** (set during the build, do not relitigate):
- No platform APIs (no Meta Graph, no X API, no instagrapi). Everything goes through a real browser.
- No Python framework. Just markdown skills + small bash scripts.
- No `ANTHROPIC_API_KEY`. Claude Code (OAuth via your subscription) IS the agent.
- Real Chrome only — Chrome for Testing crashes on routine UI like the profile picker.
- One persistent shared browser. Each platform = one tab. Skills find existing tabs and switch into them; they never close them.

## Prerequisites

- macOS (iOS-simulator screenshots use `xcrun simctl`)
- [Claude Code](https://claude.ai/code) CLI, OAuth-authed
- [`agent-browser`](https://github.com/...) CLI on `PATH`
- `jq` and `ImageMagick` (`brew install jq imagemagick`)

## Setup

```bash
# 1. Clone + cd in
git clone git@github.com:vanities/social-skills.git
cd social-skills

# 2. Add credentials (only the platforms you'll use)
cp .env.example .env
# Edit .env: INSTAGRAM_*_USERNAME / _PASSWORD, LINKEDIN_*, TWITTER_*, PINTEREST_*

# 3. Launch the persistent shared browser
bash scripts/launch_browser.sh

# 4. Log in to each platform once (state persists)
claude  # then in chat: /instagram-login <account>, /linkedin-login, /x-login, /pinterest-login
```

That's it. Skills do the rest.

## Skills

### Login + post

| Skill | Status |
|---|---|
| `/instagram-login <account>` · `/instagram-post <account> <media...> <caption>` | ✅ |
| `/linkedin-login` · `/linkedin-post <personal\|<company-id>> <media...> <caption>` | ✅ Personal feed or company-page (e.g. AM2 LLC `104970470`). Multi-image carousels supported. |
| `/x-login` · `/x-post <thread-json>` | ✅ Single tweet or multi-tweet **reply chain** (X's in-modal threads don't accept programmatic uploads to the 2nd+ tweet). |
| `/pinterest-login` · `/pinterest-post <pin-json>` | ✅ Tall iPhone screenshots fit Pinterest natively (no padding). Creates boards inline. |
| `/tiktok-post` | 🚫 Deferred — TikTok web upload is video-only (Photo Mode is mobile-app exclusive). See `.claude/skills/tiktok-post/SKILL.md` for unblock paths. |

### Composite + orchestration

| Skill | What it does |
|---|---|
| `/post-daily-devotional` | Screenshot iOS sim → pad to 4:5 → read screenshot to extract verse/reflection → draft platform-tailored captions → post to **IG + X + Pinterest** (skips LinkedIn). Cron-fired at noon. |
| `/feature-post <description> [platforms]` | End-to-end feature launch. Drives the iOS sim via XcodeBuildMCP, captures screenshots, pads, drafts platform-specific captions, gets your approval, then cross-posts to LinkedIn (AM2 LLC) + IG + X. |

### Engagement / warming

Pure-broadcast accounts get throttled. These skills mimic organic behavior — scroll, like, save, repost — to graduate fresh accounts and keep reach healthy.

| Skill | What it does |
|---|---|
| `/x-warm` | Scroll feed + 1–3 likes + maybe 1 repost on `@swift_bible`. |
| `/pinterest-warm` | Scroll feed + 1–4 saves + maybe 1 follow on `swiftbible`. |
| `/instagram-warm` | Scroll feed + 1–3 likes on `@swift_bible`. |
| `/warm-all` | Picks the most-stale eligible platform per invocation and runs its warm skill. Cron-fired 3× daily at staggered minutes. |

**Hard rules** baked into every warm skill:
- **No auto-comments anywhere** — highest bot-detection signal.
- **No auto-follow on X / IG** for fresh accounts; Pinterest follow is allowed but rare.
- All actions wait `4–18s` jitter between each, refs are re-snapshotted before every click.

Daily action budgets, weights, and time windows live in [`config/engagement-schedule.json`](config/engagement-schedule.json). Per-platform state (last run, today's counters) in `~/.social-skills/state/engagement-state.json`.

## Cron — installed automation

```cron
# Daily devotional fan-out: noon local, posts to IG + X + Pinterest
0 12 * * * /bin/bash <repo>/scripts/daily_devotional.sh

# Engagement warming: 3 staggered slots, picks one platform per fire
17  9 * * * /bin/bash <repo>/scripts/warm_all_cron.sh
43 13 * * * /bin/bash <repo>/scripts/warm_all_cron.sh
22 18 * * * /bin/bash <repo>/scripts/warm_all_cron.sh
```

Both wrappers invoke `claude --print --dangerously-skip-permissions "/<skill>"` because cron can't approve interactive permission prompts.

**Operational caveats**:
- The Mac must be awake at fire times (cron doesn't wake the machine).
- The persistent Chrome window must be open with all platform tabs logged in. Run `bash scripts/launch_browser.sh` after a reboot.

## Helper scripts

| Script | What |
|---|---|
| `scripts/launch_browser.sh` | Boots the persistent shared Chrome against `~/.social-skills/chrome-profile/` with the anti-detection flag. |
| `scripts/jitter.sh MIN MAX` | Random delay generator — used between every browser action. |
| `scripts/pad_ios_screenshot.sh <input> [output] [mode]` | Pads tall iPhone screenshots to 4:5. Plain modes: `edge` (seamless sample), `blur` (Apple-style frame), `random` (palette), `#RRGGBB` (solid). Fancy modes (random gradient bg + SVG decoration layer — sparkles, stars, hearts, golden crosses, mini-Bibles, doves, scripture words, glow orbs): `gradient`, `bloom`, `sparkle`, `cosmic`, `divine`, `holy`, `lovely`, `dream`. Smart: `surprise` picks a fancy mode at random. |
| `scripts/daily_devotional.sh` · `scripts/warm_all_cron.sh` | Cron entrypoints — `cd` into the repo, restore `PATH`, run Claude headless. |

## Logs

| Log | Source |
|---|---|
| `~/.social-skills/logs/cron/<date>.log` | Daily devotional cron (shell + headless Claude stdout) |
| `~/.social-skills/logs/cron/warm-<date>.log` | Warm cron |
| `~/.social-skills/logs/login/<platform>-<account>-<ts>.json` | Per-login form-field discovery (the breadcrumb that makes UI changes easy to chase) |
| `~/.social-skills/logs/post/<platform>-<account>-<ts>.json` | Per-post outcome + verification screenshot path |
| `~/.social-skills/logs/warm/<platform>-<account>-<ts>.json` | Per-warm-pass actions executed |
| `~/.config/agent-browser/<platform>-<account>.json` | Saved browser session (cookies, localStorage, etc.) |

## Layout

```
social-skills/
├── README.md
├── CLAUDE.md                  ← agent context (read this if you're a fresh Claude session)
├── .env.example
├── config/
│   └── engagement-schedule.json
├── docs/platforms/
│   └── <platform>.md          ← reusable per-platform playbooks
├── scripts/
│   ├── launch_browser.sh
│   ├── jitter.sh
│   ├── pad_ios_screenshot.sh
│   ├── daily_devotional.sh
│   └── warm_all_cron.sh
└── .claude/skills/
    ├── instagram-{login,post}/SKILL.md
    ├── linkedin-{login,post}/SKILL.md
    ├── x-{login,post,warm}/SKILL.md
    ├── pinterest-{login,post,warm}/SKILL.md
    ├── instagram-warm/SKILL.md
    ├── tiktok-post/SKILL.md       ← stub, deferred
    ├── post-daily-devotional/SKILL.md
    ├── feature-post/SKILL.md
    └── warm-all/SKILL.md
```

## Adding a platform

1. Write `docs/platforms/<name>.md` — URLs, login flow, anti-bot notes.
2. Add skills `.claude/skills/<name>-login/SKILL.md`, `<name>-post/SKILL.md`, optionally `<name>-warm/SKILL.md`. Mirror the `x-*` skills as a template — they cover the trickiest cases (graduated-access, reply-chain threads, viewport-required clicks).
3. Update `config/engagement-schedule.json` with the platform's action budget.
4. Wire into `/warm-all` and `/post-daily-devotional` if you want it cron-scheduled.

## Status

- [x] **Instagram** — login, post (incl. multi-image carousel), warm
- [x] **LinkedIn** — login (incl. PIN checkpoint), post (personal + company pages)
- [x] **X / Twitter** — login, post (incl. reply-chain threads), warm
- [x] **Pinterest** — login, post (incl. inline board creation), warm
- [x] **Daily devotional** — fans to IG + X + Pinterest, cron-driven
- [x] **`/feature-post`** — XcodeBuildMCP-driven multi-platform feature launch
- [x] **Engagement warming** — `/warm-all` cron with 3 staggered slots, per-platform action budgets
- [x] **iOS screenshot padding** — `edge` / `blur` / `random` / hex modes
- [ ] TikTok — deferred until a video pipeline exists (animated screenshots + voiceover)
- [ ] YouTube Shorts — same blocker as TikTok
- [ ] Facebook (AM2 LLC Page) — easiest path is creating a Page + linking to IG via Meta Accounts Center to enable the cross-post toggle
- [ ] Bluesky — similar to X minus the friction; ~1 hr to mirror the X skills
- [ ] Auto-comment generation with user-approval pattern (currently fully skipped — too high-risk)
