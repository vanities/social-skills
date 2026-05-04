# Architecture: shared headed Chrome + skills

## The browser

We run **one persistent headed Chrome** that the user and the agent share, backed by a **dedicated automation profile** so extensions (uBlock Origin) and login state survive close/restart. Each social platform lives in its own tab. The browser survives across Claude Code sessions; you (the user) can poke at it any time, and skills find their tab and pick up where you left off.

## Profile

Default path: `~/.social-agents/chrome-profile/` (override via `SOCIAL_AGENTS_CHROME_PROFILE`).

Launch the browser at the start of a work session:

```bash
bash scripts/launch_browser.sh
```

That runs `agent-browser --profile <path> --headed open https://www.instagram.com/`. Subsequent `agent-browser` commands attach to the running daemon and pick up the profile automatically — skills don't re-pass `--profile`.

What lives in the profile:

- Extensions (install uBlock once; persists)
- Cookies + localStorage for every site you've signed into
- History, autofill, etc.

What doesn't:

- The Chrome variant agent-browser uses is "Chrome for Testing" (different binary from your everyday Chrome), so this profile is fully isolated from your normal browsing.

```
┌──────────────────────────────────────────────────────────────┐
│  Headed Chrome window                                        │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐             │
│  │ [0] IG      │ │ [1] TikTok  │ │ [2] LinkedIn │  …         │
│  │ (logged in) │ │ (logged in) │ │ (logged in) │             │
│  └─────────────┘ └─────────────┘ └─────────────┘             │
└──────────────────────────────────────────────────────────────┘
        ▲                 ▲                ▲
        │                 │                │
        └───────── agent (Claude Code via agent-browser CLI) ──┘
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

## Cron flow (cold start)

When `scripts/daily_devotional.sh` fires from cron:

1. The persistent browser may or may not be running. If running, the skill will use it.
2. If not, the skill needs to launch a headless-or-headed agent-browser session, `state load`, then proceed.

(The cron flow currently assumes a fresh session — improvement: detect existing daemon and use it.)

## Logs

Two layers:

- **Shell-level** — anything before Claude starts: `~/.social-agents/logs/cron/<date>.log`
- **Skill-level** — every skill run writes a JSON log: `~/.social-agents/logs/<action>/<platform>-<account>-<timestamp>.json` with form refs, dialogs handled, screenshots, and outcome.
