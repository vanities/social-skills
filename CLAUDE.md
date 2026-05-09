# social-skills — agent context

> If you're a fresh Claude session in this repo, read this top-to-bottom before doing anything. The architecture has gone through several pivots; the current shape is locked in by explicit decisions, and reverting to earlier patterns will cause friction.

## What this is

Skill-driven social media automation across Instagram, LinkedIn, X, Pinterest (live), TikTok (deferred), and Facebook / Bluesky / YouTube Shorts (TBD). The agent (Claude Code, OAuth-authed) reads SKILL.md playbooks and drives a real Chrome browser via the `agent-browser` CLI. **No platform APIs, no Python framework, no `ANTHROPIC_API_KEY`.**

Read also:
- [`README.md`](README.md) — high-level overview + setup
- [`PERSONAL.md`](PERSONAL.md) — how to wire your handles, brand voice, and per-brand composite skills via the gitignored `personal/` + committed `personal.example/` pattern
- `CLAUDE.local.md` — your private addendum with live state, account routing, and brand notes (gitignored, auto-loaded by Claude Code alongside this file). Sample shape: `CLAUDE.local.md.example`.
- `docs/architecture.md` — shared-browser model, profile, state
- `docs/platforms/<name>.md` — per-platform playbooks
- `.claude/skills/<name>/SKILL.md` — verbs Claude can invoke

## Hard rules (locked in; do not relitigate)

1. **No platform APIs** — official (Meta Graph, X API, LinkedIn API, TikTok Business) AND reverse-engineered (instagrapi, etc.). Everything goes through a real browser.
2. **No Python framework** — no `src/`, no `pyproject.toml`, no browser-use, no Playwright glue. The repo is markdown + skills + small bash. An earlier version had a full Python adapter framework; it was deleted intentionally.
3. **No Anthropic API key** — Claude Code itself, OAuth-authed via the user's subscription, IS the agent. Do not add `ANTHROPIC_API_KEY` to `.env.example` or anywhere else.
4. **Real Chrome only**, not Chrome for Testing — CFT crashes on routine UI interactions like the profile picker. `scripts/launch_browser.sh` points at `/Applications/Google Chrome.app/...`.
5. **Persistent shared browser** — one headed Chrome window the user and the agent both use. Each platform = one tab. Skills find the platform's tab and switch into it; they never close it.
6. **All brand-specific values live in `config/brand.json`** — handles, company IDs, topic regexes, board names. Never hardcode them in committed skill files. The brand config is gitignored; the schema is committed at `config/brand.example.json`.

## Architecture in 30 seconds

```
cron / interactive trigger  →  SKILL.md playbook  →  Claude (OAuth)  →  agent-browser CLI  →  real Chrome (persistent profile, anti-detection flag)  →  IG / LinkedIn / …
```

- **Profile dir**: `~/.social-skills/chrome-profile/` (override: `SOCIAL_SKILLS_CHROME_PROFILE`)
- **Chrome binary**: `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome` (override: `SOCIAL_SKILLS_CHROME_BINARY`)
- **Anti-automation flag**: `--disable-blink-features=AutomationControlled` (strips `navigator.webdriver`)
- **Backup state files**: `~/.config/agent-browser/<platform>-<account>.json`
- **Engagement state**: `~/.social-skills/state/engagement-state.json` (last-run + today's action counts per platform)
- **Logs**: `~/.social-skills/logs/{cron,login,post,warm}/...`

Start a work session:
```bash
bash scripts/launch_browser.sh
```

## Multi-brand model

`config/brand.json` supports a parent **org** (LinkedIn company id, etc.) with N child **brands**, each with its own per-platform handles, topic filter, and voice. Skills resolve which brand to target via the first arg if given, else `default_brand`.

```json
{
  "default_brand": "main",
  "org": { "name": "...", "linkedin_company_id": "..." },
  "brands": {
    "main": { "instagram": {...}, "x": {...}, "pinterest": {...}, "brand": {...} }
  }
}
```

If you have one brand, leave a single key under `brands`. If you have multiple (e.g. parent company + N products), add sibling keys. See `config/brand.example.json` for the full schema and a worked two-brand example.

## Engagement / warming system

- `config/engagement-schedule.json` — daily action budgets, time windows, weights, jitter ranges (PII-free; tune as needed)
- `config/brand.json` — per-brand `own_handle`, `topic_filter_regex`, `exclude_handles_substring` (parody-handle filter)
- `~/.social-skills/state/engagement-state.json` — per-platform `last_run_iso` + today's action counts
- `~/.social-skills/logs/warm/<platform>-<account>-<ts>.json` — per-run logs

**One platform per `/warm-all` invocation.** Cron fires `/warm-all` ~3× daily at staggered minutes; each call picks the most-stale eligible platform (respecting `min_gap_minutes_between_platforms` and `daily_action_budget`) and runs its warm skill. Never run all three back-to-back.

**Per-pass action shape: always 1 scroll up front, then 2–3 weighted engagement actions.** Earlier shape was 1–3 weighted-anything-including-scroll, which usually landed on a single scroll because scroll's weight was highest in every platform's bag — meaning warm passes often did 0 likes/saves/reposts. The current shape guarantees engagement: each fire produces 2–3 likes/saves/reacts/reposts (whichever the engagement bag draws). Action vocabularies per platform: X=`like,repost`; IG=`like` only (degenerates to 2-3 likes); Pinterest=`save,react,follow`. The `react` action is Pinterest's heart/love reaction.

**Hard rules baked into the skills**:
- **Auto-comments under tight constraints** — comments are the highest-risk bot-detection signal, so they ride a much stricter pipeline than likes/saves:
  - Phrase MUST come from `config/comment-corpus.json` (curated lowercase ≤5-word entries). NEVER generate or paraphrase a comment outside the corpus.
  - Typing MUST go through `bash scripts/type_human.sh "$PHRASE"` — that script types char-by-char via `agent-browser keyboard type` with randomized 30–130ms per-char delays, 120–350ms after spaces, and occasional 400–900ms "thinking" pauses (5% of chars). **No `keyboard type` of the full phrase, no `fill`, no clipboard paste — uniform-speed typing is itself a bot signature, separate from what's typed.**
  - At most **1 comment per warm pass**, OUTSIDE the 2–3 engagement count (so it's a low-frequency add-on, not an extra action slot).
  - De-dup state at `~/.social-skills/state/comment-history.json`: same phrase can't repeat within 7 days on the same platform; same author can't get a 2nd comment within 30 days; comment + like + save on the same post is forbidden (one engagement per target).
  - Skip authors whose handle matches `brands.<slug>.<platform>.exclude_handles_substring` (parody/impersonation risk).
  - Rollout order recommendation: Pinterest first (most lenient) → X (after ~2 weeks if no negative signals) → IG (last; IG punishes comment patterns hardest, may stay deferred indefinitely).
- **No auto-follow on IG / X for fresh accounts** — too aggressive for new accounts; Pinterest follow is allowed but rare.
- **macOS shell gotchas**: `mv` is aliased to `mv -i` (use `command mv -f`); the project shell is **zsh**, not bash, so `arr=($var)` does NOT word-split — use `shuf` over heredoc'd line lists for randomization.

## Conventions every skill follows

1. **Tab-aware**: skills do tab discovery via `bash scripts/switch_to_platform_tab.sh <substring> <fallback-url>` (which uses `scripts/find_platform_tab.sh` internally). **Never use `agent-browser tab list`** — it auto-spawns a fresh Chrome on CDP attach failure even when the existing Chrome is HTTP-healthy, which kills the user's session. Skills never close tabs.
2. **Jitter**: `agent-browser wait $(bash scripts/jitter.sh MIN MAX)` between actions. Defaults:
   - After nav / tab switch: 600–1600 ms
   - Between fills in a form: 300–1000 ms
   - Before clicking Sign in / Post / Share: 1200–3000 ms
3. **Real keystrokes for human-typed fields**: `agent-browser type @<ref>` (not `fill`) for username, password, single-line caption. **For multi-line content (post captions, tweet text) on IG and X, use `agent-browser keyboard type "$TEXT"` — NOT `type @<ref>`**. IG and X both use Lexical contenteditable editors; `type @<ref>` swallows embedded `\n` and produces a run-on paragraph, while `keyboard type` sends real Enter keystrokes that Lexical converts to proper `<br><br>` paragraph breaks AND auto-styles `#hashtags` with the link spans. LinkedIn's editor handles `type @<ref>` newlines fine — it's a different implementation. Reach for `keyboard type` whenever you've focused a contenteditable.
4. **`fill` / `upload` for file inputs**: file paths get pasted, not typed. `agent-browser upload <selector> <files...>` accepts multiple positional paths — use it for carousel posts on IG and LinkedIn (both expose `input[type=file]` with `multiple=true`). The same input accepts video on every platform we use; pre-encode iPhone screen recordings to h264 first via `pad_ios_video.sh` to avoid HEVC re-transcodes.
5. **Pre-pad iPhone media before posting**:
   - **Images** → `bash scripts/pad_ios_screenshot.sh <input> [output] [mode]` pads to 4:5 (Instagram feed). Plain modes: `edge` (seamless), `blur` (Apple-style), `random` (palette), `#RRGGBB`. Decorative / themed modes (random gradient bg + SVG decoration layer): `gradient`, `bloom`, `sparkle`, `cosmic`, `divine` (golden crosses + scripture words), `holy` (divine + Bibles + flying-dove silhouettes), `lovely` (hearts), `dream` (faded words over blur). `surprise` rolls one of the fancy modes. The decoration layer is rasterized via `rsvg-convert`, not `magick` — magick's SVG path can't resolve fontconfig text fonts on macOS so any `<text>` element makes it error with "unable to read font ''". `brew install librsvg` if it's missing.
   - **Videos** → `bash scripts/pad_ios_video.sh <input> [output] [mode]` pads to 9:16 (Instagram Reels) and re-encodes to 1080×1920 h264 + AAC + faststart. Modes: `blur` (default), `black`, `#RRGGBB`. Cross-platform safe — IG / LinkedIn / X all accept the output cleanly (avoids HEVC ingest issues).
   Skill steps that take iPhone media should always pass through these helpers first.
6. **Form-field logging mandatory**: every login/post run writes `~/.social-skills/logs/<action>/<platform>-<account>-<ts>.json` with the `@refs` it discovered. If a platform changes its UI, this is the breadcrumb that makes it easy to update the skill.
7. **`.env` parsing**: don't `source .env` — passwords contain `$`, backticks, etc. that re-evaluate. Use `grep -m1 '^KEY=' .env | cut -d= -f2-` to extract literal values.
8. **Per-platform credential format** (see `.env.example` for the full list):
   - Instagram: `INSTAGRAM_<ACCOUNT_LABEL>_USERNAME` / `_PASSWORD`. The label matches `brands.<slug>.instagram.default_account` from `brand.json`.
   - LinkedIn / X / Pinterest: unsplit `<PLATFORM>_USERNAME` / `_PASSWORD`. X uses `TWITTER_*`.
   - TikTok: manual-login only — auto-login isn't worth attempting against TikTok's CAPTCHA gauntlet. State at `~/.config/agent-browser/tiktok-default.json`.

## Multi-account routing on a single platform

Some platforms support multiple signed-in accounts in one browser session (X is the prime example: account switcher in the side nav). When you have N handles signed in, **every skill that posts MUST take an explicit account/handle arg and switch the session before composing**. There is no default account.

`/x-post <handle> <thread.json>` enforces this. The `scripts/x_switch_account.sh <handle>` helper reads the current session's profile link, opens the account switcher, and clicks the matching cell. It's a no-op when already on target.

## Skills available

| Skill | Purpose | Status |
|---|---|---|
| `/instagram-login <account>` | Log in (auto via .env or manual). Save state. | ✅ |
| `/instagram-post <account> <media...> <caption>` | Click Create → upload → crop (4:5 for image, Mobile/9:16 for Reel) → caption → Share. Image OR video; vertical video auto-becomes a Reel. Multi-image carousels via `<input multiple>`. | ✅ |
| `/linkedin-login` | Auto via .env. Pauses for verification PIN if checkpoint appears. | ✅ |
| `/linkedin-post <personal\|<company-id>> <media...> <caption>` | Personal feed OR company-page post. Pass multiple media paths to upload a carousel. Accepts image or video. | ✅ |
| `/x-login` | Two-step username → password flow. Auto via `TWITTER_*`. Pauses for any verification challenge. | ✅ |
| `/x-post <handle> <thread.json>` | Single tweet OR multi-tweet via reply chain on the given X account. Handle is REQUIRED — the skill switches the X session to that handle via `scripts/x_switch_account.sh` before composing. JSON `[{text, media?}, ...]`. First tweet supports up to 4 images via `multiple=true` input OR exactly 1 video; subsequent tweets are posted as **replies** to the previous (in-modal threads' file inputs don't accept programmatic uploads — see skill for why). | ✅ |
| `/x-article <account> <slug> <source>` | **Draft-helper, not publisher.** Reads a source (repo path, file, or `-` for in-conversation context), writes `articles/<slug>.md` with `[SUBHEADING]`, `[BLOCKQUOTE]`, `[INLINE IMAGE]` markers + absolute paths. The user pastes paragraph-by-paragraph into the X Article composer at `x.com/compose/articles`. Does NOT auto-publish — Lexical races on markdown shortcuts AND hides toolbar buttons contextually, so reliable auto-fill is impractical. | ✅ |
| `/feature-post <description> [brand-slug] [platforms]` | Cross-platform launch flow: drive iOS sim → capture screenshots / video → pad → draft platform-tailored captions → user approval → cross-post to LinkedIn / IG / X / Pinterest. LinkedIn / IG / X get an announcement-style caption; Pinterest gets a search-rewritten how-to with the brand's `feature_board`. | ✅ |
| `/tiktok-post` | DEFERRED. TikTok's web upload is **video-only** (Photo Mode is mobile-app exclusive). Skill documents the blocker + 3 unblock paths. | 🚫 |
| `/reddit-post <sub> <title> <body>` | STUB. Reddit fundamentally breaks the cross-post / cron / warm patterns: self-promo is heavily policed (10:1 rule), each sub has its own culture (no fan-out), and bot detection is aggressive. Use only as a single-shot helper for hand-crafted posts to subs where the account has built karma. | 🚫 |
| `/pinterest-login` | Auto via `PINTEREST_*`. Pauses for any CAPTCHA challenge. | ✅ |
| `/pinterest-post <pin.json>` | Reads JSON `{media, title, description, board, link?}`. Tall iPhone screenshots fit natively (no padding). Creates the board inline if it doesn't exist. | ✅ |
| `/x-warm [brand]` | One warming pass — scroll feed + 1-3 likes + maybe 1 repost. Topic-filtered against `brands.<slug>.x.topic_filter_regex`. | ✅ |
| `/pinterest-warm [brand]` | One warming pass — scroll feed + 1-4 saves + 1-2 reacts + maybe 1 follow. Same topic filter pattern. | ✅ |
| `/instagram-warm [brand]` | One warming pass — scroll feed + 1-3 likes. **No follow / comment** — IG punishes those signals hardest. | ✅ |
| `/warm-all` | Picks the most-stale eligible platform (uses `default_brand`) and runs its warm skill once. Cron'd 2-3× daily at staggered times. | ✅ |

For brand-specific composite skills (daily-content cron, brand-tooling helpers), see `personal.example/` — copy templates into `.claude/skills/<your-name>/` (gitignored) and customize. See `PERSONAL.md`.

## Cron pattern

Two cron entries cover most setups:

```cron
# Daily content (your composite skill, copied from personal.example/)
0 12 * * * /bin/bash <repo>/scripts/daily_content.sh

# Engagement warming: 3 staggered slots, picks one platform per fire
17  9 * * * /bin/bash <repo>/scripts/warm_all_cron.sh
43 13 * * * /bin/bash <repo>/scripts/warm_all_cron.sh
22 18 * * * /bin/bash <repo>/scripts/warm_all_cron.sh
```

Both wrappers `cd` into the repo, restore PATH for macOS cron, and invoke `claude --print --dangerously-skip-permissions "/<skill>"`. The flag is necessary because cron can't approve interactive permission prompts. Logs land in `~/.social-skills/logs/cron/<date>.log` and `~/.social-skills/logs/cron/warm-<date>.log`.

## Known issues / gotchas

- **`agent-browser snapshot -i` does NOT see inside `[role=dialog]` modals on Instagram** (Crop, Edit, Sharing, Post shared). It picks up sidebar / feed elements behind the modal but misses the modal's own buttons/textboxes. Pattern: enumerate dialogs via `eval`, then click buttons inside via `eval` too.
   ```bash
   agent-browser eval "(()=>{const dialogs=document.querySelectorAll('[role=dialog]');return Array.from(dialogs).map(d=>({label:d.getAttribute('aria-label'),visible:d.offsetParent!==null}))})()"
   agent-browser eval "(()=>{const d=document.querySelector('[role=dialog][aria-label=Crop]');const next=Array.from(d.querySelectorAll('button,[role=button]')).find(b=>b.textContent.trim()==='Next');next.click()})()"
   ```
   Caption/textbox inputs ARE surfaced by snapshot (so `keyboard type` after focus works), but Share / Next / OK / Done buttons inside dialogs need eval-based clicks.
- **NEVER use `agent-browser` for any liveness / diagnostic check on Chrome**. agent-browser auto-spawns a fresh Chrome when its CDP WebSocket can't connect — even if Chrome's HTTP `/json/version` endpoint is responding. Those endpoints have *different* reliability profiles: a Chrome can be HTTP-alive but WebSocket-broken (overnight idle, partial crash), and `agent-browser tab list` will quietly kill that Chrome and replace it with a fresh `about:blank` instance. The user has to click "Restore" to recover tabs.
- **Correct cron guard: probe via plain HTTP `/json/list`, grep the JSON for platform URLs, never invoke agent-browser before `claude --print`**. `/json/list` returns the full tab array (read-only HTTP, can't spawn anything) and the URLs in that array tell you both "Chrome is alive" AND "it's our Chrome with logged-in tabs". If the array is empty or only contains `about:blank` / `chrome://newtab`, skip. `daily_content.sh` and `warm_all_cron.sh` both use this pattern.
- **Skills do tab discovery via `scripts/switch_to_platform_tab.sh <url-substring> <fallback-url>` — NOT `agent-browser tab list`**. Same root cause: the spawn risk is in agent-browser's CDP attach, not just in the wrapper guard. All cron-path skills (warm + post) use the helper.
- **Be careful with backticks in shell** — they trigger command substitution. `echo "Remaining \`agent-browser tab list\` references"` actually RUNS `agent-browser tab list` before the echo. Use single quotes, escape with `\`, or rephrase.
- **DevToolsActivePort is a stale file that persists after Chrome quits** — never trust its presence as proof Chrome is alive. Always validate with the HTTP probe.
- **The cron's PATH must include `~/.vite-plus/bin`** — that's where `agent-browser` lives. macOS cron has a stripped PATH, and the wrapper's `export PATH=` line must restore it explicitly.
- **`agent-browser tab <index>` sometimes prints the target tab info but doesn't transfer focus**. Symptom: subsequent `get url` returns the *previous* tab's URL, and `snapshot` shows the previous tab's content. Workaround: re-issue `agent-browser tab <index>` followed by `sleep 2`, then verify with `get url` before continuing.
- **IG Reels Crop dialog defaults to 1:1**, not Mobile (9:16). Even for a vertical video, IG will square-crop the middle unless you explicitly select the 9:16 aspect via the "Select crop" popover. Skill auto-picks for vertical media; if the eval reports no Mobile/9:16 option, the skill aborts with a message — don't click Next on a wrong aspect.
- **IG's "Select crop" button is the ONE element in the entire stack that requires a real mouse event** — `agent-browser click @<ref>` and JS `.click()` both fail to open its popover (other buttons inside the same dialog respond fine). Use `agent-browser mouse move/down/up` at the button's bbox center. Once the popover is open, the aspect options DO surface in `snapshot -i` and respond to normal `click @<ref>`.
- **Pinterest's Publish button scrolls off-screen** by the time you fill the form (the form grows past one viewport). Clicking a button at negative-y silently no-ops AND saves the form as a draft. Always `agent-browser scrollintoview @<PUBLISH_REF>` before the click.
- **LinkedIn auto-attaches a link card** when the caption contains a URL — it occupies the single media slot. Click "Remove media" before "Add media" to free the slot.
- **XcodeBuildMCP needs `ui-automation` workflow enabled** to expose `tap` / `swipe` / `type_text` / `snapshot_ui` / `screenshot`. The default install enables only `simulator` (build/run/install/launch). Re-add with the env var:
  ```bash
  claude mcp remove XcodeBuildMCP -s local
  claude mcp add XcodeBuildMCP -e XCODEBUILDMCP_ENABLED_WORKFLOWS=simulator,device,debugging,ui-automation -- npx -y xcodebuildmcp@latest mcp
  ```
  Then `/reload-plugins`. After the tools surface, call `session_set_defaults({simulatorId: "<UDID>"})` once per session before screenshot/snapshot/tap. SwiftUI tab bars often expose `Tab Bar` group with empty `children` — fall back to coordinate taps (4 evenly-spaced tabs across the 402-pt screen → centers ≈ 50/150/250/350 at y≈832 for iPhone 17).
- **Chrome for Testing**: do not switch back to it. Crashes on profile UI clicks.
- **`source .env` fails** because passwords contain shell-special chars (`$`, single quote, backtick). Use `grep | cut`.
- **First Chrome launch with a fresh profile** sometimes opens the Chrome Web Store as a "first run" page. `agent-browser open <url>` after `launch_browser.sh` handles it.
- **IG "Save your login info?" + "Turn on Notifications"** dialogs appear post-login. Always click "Not now" / "Not Now". Login skills handle this; logs record what was dismissed.

## Decisions log

- Rejected Postiz / Mixpost (use APIs). Rejected instagrapi (reverse-engineered API). Rejected browser-use Python (needs API key). Picked agent-browser CLI + skills + Claude Code as the agent.
- Rejected Stagehand / Playwright MCP (would replicate agent-browser, which is already broadly used by the user across other projects).
- Rejected Chrome for Testing (crashed multiple times on profile picker). Switched to real Chrome. Profile dir works in both.
- Rejected the in-process scheduler (APScheduler). Daily-content composite uses local cron because remote scheduling can't see the user's iOS simulator.
- Codified the **`agent-browser keyboard type` for multi-line captions** rule (IG and X both use Lexical contenteditable; `type @ref` swallows newlines).
- Codified the **`[role=dialog]` snapshot blind-spot** — IG modal interactions need `eval`-based clicks.
- Refactored brand-specific values out of skills into `config/brand.json` (gitignored), with `config/brand.example.json` committed as the schema. Skills accept an optional brand-slug arg, fall back to `default_brand`.

## Pointers

- Memory: `~/.claude/projects/-Users-<your-username>-…-social-skills/memory/`
- Repo: PRIVATE. The committed code in this repo is intended to be PII-free; user-specific values live in gitignored files (see `PERSONAL.md`).
- Local state dir: `~/.social-skills/` (chrome-profile, logs, state).
