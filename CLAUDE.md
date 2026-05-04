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

1. **Tab-aware**: `agent-browser tab list`, switch into existing platform tab if present (`agent-browser tab <index>`, NOT `tab switch <index>` — that subcommand doesn't exist), else `tab new <url>`. Never close the tab.
2. **Jitter**: `agent-browser wait $(bash scripts/jitter.sh MIN MAX)` between actions. Defaults:
   - After nav / tab switch: 600–1600 ms
   - Between fills in a form: 300–1000 ms
   - Before clicking Sign in / Post / Share: 1200–3000 ms
3. **Real keystrokes for human-typed fields**: `agent-browser type @<ref>` (not `fill`) for username, password, caption.
4. **`fill` / `upload` for file inputs**: file paths get pasted, not typed. `agent-browser upload <selector> <files...>` accepts multiple positional paths — use it for carousel posts on IG and LinkedIn (both expose `input[type=file]` with `multiple=true`).
5. **Pre-pad iPhone screenshots before posting**: raw iOS simulator screenshots are ~9:19.5, well outside Instagram's allowed range. `bash scripts/pad_ios_screenshot.sh <input> [output] [mode]` pads to 4:5 with seamless edge color (default), an Apple-style blurred background (`blur`), a random palette color (`random`), or a hex color. Skill steps that take iPhone screenshots should always pass through this script first.
6. **Form-field logging mandatory**: every login/post run writes `~/.social-agents/logs/<action>/<platform>-<account>-<ts>.json` with the `@refs` it discovered. If a platform changes its UI, this is the breadcrumb that makes it easy to update the skill.
7. **`.env` parsing**: don't `source .env` — passwords contain `$`, backticks, etc. that re-evaluate. Use `grep -m1 '^KEY=' .env | cut -d= -f2-` to extract literal values.
8. **Per-platform credential format**:
   - Instagram: `INSTAGRAM_<ACCOUNT_LABEL>_USERNAME` / `_PASSWORD` (e.g. `INSTAGRAM_SWIFTBIBLE_*`).
   - LinkedIn: unsplit `LINKEDIN_USERNAME` / `LINKEDIN_PASSWORD` (single account).

## Skills available

| Skill | Purpose | Status |
|---|---|---|
| `/instagram-login <account>` | Log in (auto via .env or manual). Save state. | ✅ Tested live with `swiftbible` |
| `/instagram-post <account> <media> <caption>` | Click Create → upload → 4:5 crop → type caption → Share. | ✅ Tested live (post is up at instagram.com/swift_bible) |
| `/post-daily-devotional` | Composite: `xcrun simctl io booted screenshot` → `/instagram-post`. Default account `swiftbible`. | ✅ Posted live 2026-05-04 |
| `/linkedin-login` | Auto via .env. Pauses for verification PIN if checkpoint appears. | ✅ Live-tested through PIN challenge |
| `/linkedin-post <personal\|<company-id>> <media> <caption>` | Personal feed OR company-page post (e.g. `104970470` for AM2 LLC). Pass multiple media paths to upload a carousel. | ✅ Live-tested 2026-05-04 (AM2 LLC, 2-image carousel) |
| `/x-login` | Two-step username → password flow. Auto via `TWITTER_USERNAME` / `TWITTER_PASSWORD` (username can be handle, email, or phone). Pauses for any verification challenge. | ✅ Live-tested 2026-05-04 (`swiftbible@am2.biz`, no challenge surfaced) |
| `/x-post <thread-json>` | Single tweet OR multi-tweet via reply chain. Reads JSON `[{text, media?}, ...]`. First tweet supports up to 4 images via `multiple=true` input; subsequent tweets are posted as **replies** to the previous (not in-modal threads — see skill for why). | ✅ Live-tested 2026-05-04 (1 single tweet + 1 three-tweet reply chain on `@swift_bible`) |
| `/feature-post <description> [platforms]` | Orchestrates the full multi-platform feature-launch flow: drive iOS sim → capture screenshots → pad → draft platform-tailored captions → user approval → cross-post to LinkedIn (AM2 LLC) / IG (swiftbible) / X (swift_bible). Composes the per-platform `/<platform>-post` skills. | ⚠️ Skill written, not yet end-to-end tested as a single invocation (every component step has been exercised) |
| `/tiktok-post` | DEFERRED. TikTok's web upload is **video-only** (Photo Mode is mobile-app exclusive). Skill documents the blocker + 3 unblock paths (real video pipeline, image-to-video helper, iOS-app automation via XcodeBuildMCP). | 🚫 Blocked on video content / video pipeline |
| `/pinterest-login` | Auto via `PINTEREST_USERNAME` / `PINTEREST_PASSWORD`. Pauses for any CAPTCHA challenge. | ✅ State saved 2026-05-04 (user signed in manually via .env email/password; auto-login via skill not yet exercised) |
| `/pinterest-post <pin-json>` | Reads JSON `{media, title, description, board, link?}`. Tall iPhone screenshots fit natively (no padding). Creates the board inline if it doesn't exist. | ✅ Live-tested 2026-05-04 (first pin: "James 2:12" daily devotional in board "Daily Devotionals" on `pinterest.com/swiftbible`) |

## Live state (as of 2026-05-04)

- **`swiftbible`** Instagram (https://www.instagram.com/swift_bible/) — logged in, 2 live posts:
  1. Daily devotional (May 4 — James 2:12)
  2. Feature carousel: redesigned More tab + new History view (cross-posted from the AM2 LLC LinkedIn post). Run log at `~/.social-agents/logs/post/instagram-swiftbible-2026-05-04T112554.json`.
  Bio set to "📖 Daily devotionals from the Swift Bible app. New post every day at noon. am2.biz/swiftbible".
- **LinkedIn personal** (`mischkeaa@gmail.com` → `Adam Mischke`) — logged in, state saved.
- **AM2 LLC company page** (id `104970470`) — admin access confirmed. First live post landed 2026-05-04: 2-image carousel featuring the Swift Bible iOS app's redesigned More tab + new History view (Church history, 9 eras / 29 articles). Run log at `~/.social-agents/logs/post/linkedin-104970470-2026-05-04T111757.json`.
- **X (Twitter)** `@swift_bible` (account `swiftbible@am2.biz`) — logged in 2026-05-04, state at `~/.config/agent-browser/x-default.json`. First-day posts: (1) daily devotional tweet (May 4 — James 2:12) + screenshot, (2) 3-tweet reply chain on the More-tab/History feature with screenshots on T1 and T2. Profile shows "5 posts" because each reply counts. **X surfaced a "graduated access" soft-restriction modal after the first post** — reduced reach + DM filtering until the account engages with the timeline / follows people. Doesn't block posting; dismiss via "Got it". Worth following accounts and engaging organically to graduate.
- **TikTok** `@swiftbible` (note: NO underscore, unlike IG/X handles) — logged in 2026-05-04 manually via the painful web sign-in (CAPTCHAs etc.; do not attempt auto-login). State at `~/.config/agent-browser/tiktok-default.json` (~539KB). **No posts yet** — `/tiktok-post` is deferred because web upload is video-only and we don't have a video pipeline. See `.claude/skills/tiktok-post/SKILL.md` for the three unblock paths. Bio: "📖 Daily devotionals from the Swift Bible app. New every day at noon." with `am2.biz/swiftbible` in the link field.
- **Pinterest** `swiftbible` (`pinterest.com/swiftbible`, same handle as TikTok — no underscore). Logged in 2026-05-04 (creds in `.env` as `PINTEREST_USERNAME` / `PINTEREST_PASSWORD`; state at `~/.config/agent-browser/pinterest-default.json`). First live pin 2026-05-04: "James 2:12 — The Law of Liberty" daily devotional in board "Daily Devotionals" with link `am2.biz/swiftbible`. Bio matches the Swift Bible voice. **Pinterest auto-saves form state as drafts** while you type — clicking "Create new Pin" (top-left) drops the current form to a draft instead of publishing; the actual publish action is the red **"Publish"** button (top-right). Tall iPhone screenshots fit natively here (Pinterest is built for 2:3 / tall content), so no `pad_ios_screenshot.sh` step needed.

## Cron

```cron
0 12 * * * /bin/bash /Users/vanities/git/work/me/social-agents/scripts/daily_devotional.sh
```

The script `cd`s into the repo and runs `claude --print "/post-daily-devotional"`. Cron PATH is patched at the top of the script for macOS.

## In-flight work (next session resumes here)

1. **`/feature-post` end-to-end live-test**: skill is written (`.claude/skills/feature-post/SKILL.md`) but hasn't yet been invoked as a single slash command — every component step (sim capture, padding, drafting, posting to LI/IG/X) was exercised manually 2026-05-04. Next feature ship → use `/feature-post` to validate the orchestration in one go.
2. **X account `@swift_bible` graduated-access**: posts have reduced reach until the account engages with the timeline. Worth adding a `/x-warm` skill (or manual session) to follow + like + reply organically. Run from the timeline; no creds needed beyond saved state.
3. **Facebook (AM2 LLC Page)**: not yet built. Easiest first step is the IG → FB cross-post toggle in IG's composer settings (no automation required). A `/facebook-post` skill would be the harder path.
4. **TikTok**: deferred. Requires a video pipeline (animated screenshots + voiceover/captions) before any login automation makes sense.

## Known issues / gotchas

- **XcodeBuildMCP needs `ui-automation` workflow enabled to expose `tap` / `swipe` / `type_text` / `snapshot_ui` / `screenshot`**. The default install enables only `simulator` (build/run/install/launch). Re-add with the env var:
  ```bash
  claude mcp remove XcodeBuildMCP -s local
  claude mcp add XcodeBuildMCP -e XCODEBUILDMCP_ENABLED_WORKFLOWS=simulator,device,debugging,ui-automation -- npx -y xcodebuildmcp@latest mcp
  ```
  Then `/reload-plugins` (no full Claude restart needed). After the tools surface, call `session_set_defaults({simulatorId: "<UDID>"})` once per session before screenshot/snapshot/tap. SwiftUI tab bars often expose `Tab Bar` group with empty `children` — fall back to coordinate taps (4 evenly-spaced tabs across the 402-pt screen → centers ≈ 50/150/250/350 at y≈832 for iPhone 17).
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
