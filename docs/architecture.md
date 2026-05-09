# Architecture: shared headed Chrome + skills

## The browser

We run **one persistent headed Chrome** that the user and the agent share, backed by a **dedicated automation profile** so extensions (uBlock Origin) and login state survive close/restart. Each social platform lives in its own tab. The browser survives across Claude Code sessions; you (the user) can poke at it any time, and skills find their tab and pick up where you left off.

We use **real Chrome** (`/Applications/Google Chrome.app/...`), not Chrome for Testing — CFT crashes on routine UI like the profile picker. The launch script passes `--disable-blink-features=AutomationControlled` to strip `navigator.webdriver` so platforms don't auto-flag the session.

## Profile

Default path: `~/.social-skills/chrome-profile/` (override via `SOCIAL_SKILLS_CHROME_PROFILE`).
Default binary: `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome` (override via `SOCIAL_SKILLS_CHROME_BINARY`).

Launch the browser at the start of a work session:

```bash
bash scripts/launch_browser.sh
```

This boots Chrome with the persistent profile and the anti-automation flag. Subsequent `agent-browser` commands attach to the running daemon and pick up the profile automatically — skills don't re-pass `--profile`.

What lives in the profile:

- Extensions (install uBlock once; persists)
- Cookies + localStorage for every site you've signed into
- History, autofill, etc.

The profile is dedicated to social automation, isolated from your everyday browsing — different profile dir, different Chrome window.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  Headed Chrome window — persistent profile                                   │
│  ┌─────────┐ ┌──────────┐ ┌─────┐ ┌────────┐ ┌───────────┐                   │
│  │ [0] IG  │ │ [1] LinkedIn │ │ [2] X │ │ [3] TikTok │ │ [4] Pinterest │     │
│  │ logged  │ │ logged in │ │ in  │ │ logged │ │ logged in │                   │
│  └─────────┘ └──────────┘ └─────┘ └────────┘ └───────────┘                   │
└──────────────────────────────────────────────────────────────────────────────┘
        ▲              ▲             ▲            ▲              ▲
        │              │             │            │              │
        └──────── agent (Claude Code via agent-browser CLI) ─────┘
```

## Tab convention

Every skill that targets a platform follows the same pattern:

1. `agent-browser tab list` to see what's open.
2. If a tab's URL matches the platform domain, `agent-browser tab <index>` to switch.
3. If no tab exists, `agent-browser --headed tab new <url>` (or `open` if there are zero tabs).
4. Do the work in that tab.
5. **Do not close the tab.** Leave it for the user.

## State files

State files at `~/.config/agent-browser/<platform>-<account>.json` are a **backup**, used when:

- The persistent browser isn't running (cron at noon, fresh boot).
- The user wants to seed a new browser instance with a known good session (e.g. when migrating to a new profile).
- Recovery — if a profile gets corrupted, `state load <path>` restores cookies into a fresh profile.

In normal interactive use, the persistent profile keeps cookies + storage and state files don't get touched. Re-save state periodically (`agent-browser state save ...`) so the backup is current.

## Cron flow

When `scripts/daily_devotional.sh` or `scripts/warm_all_cron.sh` fires from cron:

1. The wrapper restores `PATH` (macOS cron strips it) and `cd`s into the repo.
2. It invokes `claude --print --dangerously-skip-permissions "/<skill>"`. The flag is required because cron can't approve interactive permission prompts.
3. The skill assumes the persistent browser is running with logged-in tabs. If it's not, the skill aborts cleanly with a "run /<platform>-login first" message — cron run logs the abort and exits 0.

The Mac must be awake at fire times — cron does not wake the machine. If you regularly sleep through the morning slot (`9:17`), either keep the laptop awake or use `pmset` / `caffeinate` on a schedule.

## Logs

Three layers:

- **Shell-level** — anything before Claude starts: `~/.social-skills/logs/cron/<date>.log` (devotional) and `cron/warm-<date>.log` (warming).
- **Per-skill JSON** — every login / post / warm run writes `~/.social-skills/logs/<action>/<platform>-<account>-<ts>.json` with form refs discovered, dialogs handled, screenshots, and outcome. Form-field refs are the breadcrumb that makes UI changes easy to chase.
- **Engagement state** — `~/.social-skills/state/engagement-state.json` tracks per-platform `last_run_iso` and today's action counts, used by `/warm-all` to enforce the daily action budget and the global min-gap.
