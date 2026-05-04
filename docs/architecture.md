# Architecture: shared headed Chrome + skills

## The browser

We run **one persistent headed Chrome** that the user and the agent share. Each social platform lives in its own tab. The browser survives across Claude Code sessions; you (the user) can poke at it any time, and skills find their tab and pick up where you left off.

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
- The user wants to seed a new browser instance with a known good session.

In normal interactive use, the persistent browser keeps cookies + storage and state files don't get touched.

## Cron flow (cold start)

When `scripts/daily_devotional.sh` fires from cron:

1. The persistent browser may or may not be running. If running, the skill will use it.
2. If not, the skill needs to launch a headless-or-headed agent-browser session, `state load`, then proceed.

(The cron flow currently assumes a fresh session — improvement: detect existing daemon and use it.)

## Logs

Two layers:

- **Shell-level** — anything before Claude starts: `~/.social-agents/logs/cron/<date>.log`
- **Skill-level** — every skill run writes a JSON log: `~/.social-agents/logs/<action>/<platform>-<account>-<timestamp>.json` with form refs, dialogs handled, screenshots, and outcome.
