# social-agents — agent context

> If you're a fresh Claude session in this repo, read this top-to-bottom before doing anything. The architecture has gone through several pivots; the current shape is locked in by explicit user decisions, and reverting to earlier patterns will cause friction.

## What this is

Skill-driven social media automation across Instagram, LinkedIn (and later TikTok / X / Facebook). The agent (Claude Code, OAuth-authed) reads SKILL.md playbooks and drives a real Chrome browser via the `agent-browser` CLI. **No platform APIs, no Python framework, no `ANTHROPIC_API_KEY`.**

See:
- `README.md` — high-level overview
- `docs/architecture.md` — shared-browser model, profile, state
- `docs/platforms/<name>.md` — per-platform playbooks
- `.claude/skills/<name>/SKILL.md` — verbs Claude can invoke

## Hard rules (set by the user; do not relitigate)

1. **No platform APIs** — official (Meta Graph, X API, LinkedIn API, TikTok Business) AND reverse-engineered (instagrapi, etc.). Everything goes through a real browser.
2. **No Python framework** — no `src/`, no `pyproject.toml`, no browser-use, no Playwright glue. The repo is markdown + skills + small bash. An earlier version had a full Python adapter framework; it was deleted intentionally.
3. **No Anthropic API key** — Claude Code itself, OAuth-authed via the user's subscription, IS the agent. Do not add `ANTHROPIC_API_KEY` to `.env.example` or anywhere else.
4. **Real Chrome only**, not Chrome for Testing — CFT crashes on routine UI interactions like the profile picker (we hit this 3× in one session). `scripts/launch_browser.sh` points at `/Applications/Google Chrome.app/...`.
5. **Persistent shared browser** — one headed Chrome window the user and the agent both use. Each platform = one tab. Skills find the platform's tab and switch into it; they never close it.

## Architecture in 30 seconds

```
cron / interactive trigger  →  SKILL.md playbook  →  Claude (OAuth)  →  agent-browser CLI  →  real Chrome (persistent profile, anti-detection flag)  →  IG / LinkedIn / …
```

- **Profile dir**: `~/.social-agents/chrome-profile/` (override: `SOCIAL_AGENTS_CHROME_PROFILE`)
- **Chrome binary**: `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome` (override: `SOCIAL_AGENTS_CHROME_BINARY`)
- **Anti-automation flag**: `--disable-blink-features=AutomationControlled` (strips `navigator.webdriver`)
- **Backup state files**: `~/.config/agent-browser/<platform>-<account>.json`
- **Logs**: `~/.social-agents/logs/{cron,login,post}/...`

Start a work session:
```bash
bash scripts/launch_browser.sh
```

## Conventions every skill follows

1. **Tab-aware**: `agent-browser tab list`, switch into existing platform tab if present, else `tab new <url>`. Never close the tab.
2. **Jitter**: `agent-browser wait $(bash scripts/jitter.sh MIN MAX)` between actions. Defaults:
   - After nav / tab switch: 600–1600 ms
   - Between fills in a form: 300–1000 ms
   - Before clicking Sign in / Post / Share: 1200–3000 ms
3. **Real keystrokes for human-typed fields**: `agent-browser type @<ref>` (not `fill`) for username, password, caption.
4. **`fill` / `upload` for file inputs**: file paths get pasted, not typed.
5. **Form-field logging mandatory**: every login/post run writes `~/.social-agents/logs/<action>/<platform>-<account>-<ts>.json` with the `@refs` it discovered. If a platform changes its UI, this is the breadcrumb that makes it easy to update the skill.
6. **`.env` parsing**: don't `source .env` — passwords contain `$`, backticks, etc. that re-evaluate. Use `grep -m1 '^KEY=' .env | cut -d= -f2-` to extract literal values.
7. **Per-platform credential format**:
   - Instagram: `INSTAGRAM_<ACCOUNT_LABEL>_USERNAME` / `_PASSWORD` (e.g. `INSTAGRAM_SWIFTBIBLE_*`).
   - LinkedIn: unsplit `LINKEDIN_USERNAME` / `LINKEDIN_PASSWORD` (single account).

## Skills available

| Skill | Purpose | Status |
|---|---|---|
| `/instagram-login <account>` | Log in (auto via .env or manual). Save state. | ✅ Tested live with `swiftbible` |
| `/instagram-post <account> <media> <caption>` | Click Create → upload → 4:5 crop → type caption → Share. | ✅ Tested live (post is up at instagram.com/swift_bible) |
| `/post-daily-devotional` | Composite: `xcrun simctl io booted screenshot` → `/instagram-post`. Default account `swiftbible`. | ✅ Posted live 2026-05-04 |
| `/linkedin-login` | Auto via .env. Pauses for verification PIN if checkpoint appears. | ✅ Live-tested through PIN challenge |
| `/linkedin-post <personal\|<company-id>> <media> <caption>` | Personal feed OR company-page post (e.g. `104970470` for AM2 LLC). | ⚠️ Skill written but not yet end-to-end tested |

## Live state (as of 2026-05-04)

- **`swiftbible`** Instagram (https://www.instagram.com/swift_bible/) — logged in, 1 live post (daily devotional for May 4), bio set to "📖 Daily devotionals from the Swift Bible app. New post every day at noon. am2.biz/swiftbible".
- **LinkedIn personal** (`mischkeaa@gmail.com` → `Adam Mischke`) — logged in, state saved.
- **AM2 LLC company page** (id `104970470`) — admin access confirmed, the *Start a post* compose modal was open at end of last session with audience switcher reading "AM2 LLC … Post to Anyone". **Posting an AM2 LLC update was the in-flight task; the user paused to gather screenshots from the Swift Bible iOS app's More tab + History view.**

## Cron

```cron
0 12 * * * /bin/bash /Users/vanities/git/work/me/social-agents/scripts/daily_devotional.sh
```

The script `cd`s into the repo and runs `claude --print "/post-daily-devotional"`. Cron PATH is patched at the top of the script for macOS.

## In-flight work (next session resumes here)

1. **AM2 LLC feature post — Swift Bible "More tab redesign + History view"**: user wants two screenshots from the iOS simulator (More tab, then tap History). User asked me to make this a skill *per platform* — see "feature-post pattern" below.
2. **`/feature-post` design** — not yet implemented. The pattern the user described:
   - User gives a 1–2 sentence feature description ("redesigned more tab, opened up history view").
   - Agent screenshots the relevant simulator state(s) — user navigates the simulator manually unless xcodebuildmcp tools are surfaced (see "Known issues").
   - Agent drafts a platform-tailored caption (LinkedIn: professional/builder; IG: same as the Swift Bible audience).
   - User approves.
   - Agent posts. Cross-posts optional.
   - Suggested skill files (not yet written): `.claude/skills/linkedin-post-feature/SKILL.md`, `.claude/skills/instagram-post-feature/SKILL.md`. Each thin — composes the existing `/<platform>-post` skill with a prepended draft-caption + screenshot step.
3. **LinkedIn end-to-end live test** — login worked, but the post flow is documented but unverified live.

## Known issues / gotchas

- **xcodebuildmcp installed but tools don't surface in deferred-tool registry**: `claude mcp add XcodeBuildMCP -- npx -y xcodebuildmcp@latest mcp` was run; `claude mcp list` shows it as ✓ Connected. But `ToolSearch` returns no matches for it. Even `/reload-plugins` doesn't expose them. The user *believes* a fresh session will pick them up. If you're that fresh session and they appear in your tools — use them to drive the simulator (tap More → screenshot → tap History → screenshot) instead of asking the user to navigate manually.
- **Chrome for Testing**: do not switch back to it. Crashes on profile UI clicks.
- **LinkedIn sidebar AM2 LLC link**: clicking the wrapper element doesn't navigate. Use the company id (`104970470`) and go directly to `https://www.linkedin.com/company/<id>/admin/`. Or `agent-browser eval` to read `a[href*="/company/"]` hrefs.
- **`source .env` fails** because the LinkedIn password has `$`, single quote, backtick. Use `grep | cut`.
- **First Chrome launch with a fresh profile** sometimes opens the Chrome Web Store as a "first run" page. `agent-browser open <url>` after launch_browser.sh handles it.
- **IG "Save your login info?" + "Turn on Notifications"** dialogs appear post-login. Always click "Not now" / "Not Now". Skills handle this; logs record what was dismissed.

## Decisions log (so we don't relitigate)

- 2026-05-04: Rejected Postiz / Mixpost (use APIs). Rejected instagrapi (reverse-engineered API). Rejected browser-use Python (needs API key). Picked agent-browser CLI + skills + Claude Code as the agent.
- 2026-05-04: Rejected Stagehand / Playwright MCP (would replicate agent-browser, which user already uses across Solutions Fabric).
- 2026-05-04: Rejected Chrome for Testing (crashed 3×). Switched to real Chrome. Profile dir works in both.
- 2026-05-04: Rejected the in-process scheduler (APScheduler). Daily devotional uses local cron because `/schedule` runs *remote* agents that can't see the user's iOS simulator.
- 2026-05-04: Default IG account flipped from `adam` placeholder → `swiftbible` (the real account in `.env`).

## Pointers

- Memory: `~/.claude/projects/-Users-vanities-git-work-me/memory/social_agents_design.md`
- User's global rules referencing `agent-browser`: `/Users/vanities/git/work/teraflop/teraflop-dev-setup/rules/validate-ui.md` and `solutions-fabric-auth.md`.
- Repo is local-only currently (`gh repo create` not yet run; user wants `--private` when we do).
