# social-skills — agent context

> If you're a fresh Claude session in this repo, read this top-to-bottom before doing anything. The architecture has gone through several pivots; the current shape is locked in by explicit user decisions, and reverting to earlier patterns will cause friction.

## What this is

Skill-driven social media automation across Instagram, LinkedIn, X, Pinterest (live), TikTok (deferred), and Facebook / Bluesky / YouTube Shorts (TBD). The agent (Claude Code, OAuth-authed) reads SKILL.md playbooks and drives a real Chrome browser via the `agent-browser` CLI. **No platform APIs, no Python framework, no `ANTHROPIC_API_KEY`.**

See:
- `README.md` — high-level overview
- `docs/architecture.md` — shared-browser model, profile, state
- `docs/platforms/<name>.md` — per-platform playbooks (only `instagram.md` and `linkedin.md` exist; the rest live inside their skill files)
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

## Engagement / warming system

Built 2026-05-04. **Per-platform warm skills + meta-orchestrator**:
- `config/engagement-schedule.json` — daily action budgets, time windows, weights, jitter ranges
- `~/.social-skills/state/engagement-state.json` — per-platform `last_run_iso` + today's action counts
- `~/.social-skills/logs/warm/<platform>-<account>-<ts>.json` — per-run logs

**One platform per `/warm-all` invocation.** Cron fires `/warm-all` ~3× daily at staggered minutes; each call picks the most-stale eligible platform (respecting `min_gap_minutes_between_platforms` and `daily_action_budget`) and runs its warm skill. Never run all three back-to-back.

**Per-pass action shape (set 2026-05-05): always 1 scroll up front, then 2–3 weighted engagement actions.** The earlier shape was 1–3 weighted-anything-including-scroll, which usually landed on a single scroll because scroll's weight was highest in every platform's bag — meaning warm passes often did 0 likes/saves/reposts. The new shape guarantees engagement: each fire produces 2–3 likes/saves/reacts/reposts (whichever the engagement bag draws). Action vocabularies per platform: X=`like,repost`; IG=`like` only (degenerates to 2-3 likes); Pinterest=`save,react,follow`. The `react` action is Pinterest's heart/love reaction (closest analog to an IG/X like) — added 2026-05-05 to diversify off save-only warming.

**Hard rules baked into the skills**:
- **Auto-comments under tight constraints (set 2026-05-05; was previously banned)** — comments are the highest-risk bot-detection signal, so they ride a much stricter pipeline than likes/saves:
  - Phrase MUST come from `config/comment-corpus.json` (curated lowercase ≤5-word entries, ~74 phrases across 4 categories). NEVER generate or paraphrase a comment outside the corpus.
  - Typing MUST go through `bash scripts/type_human.sh "$PHRASE"` — that script types char-by-char via `agent-browser keyboard type` with randomized 30–130ms per-char delays, 120–350ms after spaces, and occasional 400–900ms "thinking" pauses (5% of chars). **No `keyboard type` of the full phrase, no `fill`, no clipboard paste — uniform-speed typing is itself a bot signature, separate from what's typed.**
  - At most **1 comment per warm pass**, OUTSIDE the 2–3 engagement count (so it's a low-frequency add-on, not an extra action slot).
  - De-dup state at `~/.social-skills/state/comment-history.json`: same phrase can't repeat within 7 days on the same platform; same author can't get a 2nd comment within 30 days; comment + like + save on the same post is forbidden (one engagement per target).
  - Skip authors whose handle includes `bible` or `swiftbible` (might be us / parody).
  - Rollout order: Pinterest first (most lenient) → X (after ~2 weeks if no negative signals) → IG (last; IG punishes comment patterns hardest, may stay deferred indefinitely).
- **No auto-follow on IG / X for now** — too aggressive for fresh accounts; Pinterest follow is allowed but rare.
- **macOS shell gotchas**: `mv` is aliased to `mv -i` (use `command mv -f`); the project shell is **zsh**, not bash, so `arr=($var)` does NOT word-split — use `shuf` over heredoc'd line lists for randomization.

## Conventions every skill follows

1. **Tab-aware**: `agent-browser tab list`, switch into existing platform tab if present (`agent-browser tab <index>`, NOT `tab switch <index>` — that subcommand doesn't exist), else `tab new <url>`. Never close the tab.
2. **Jitter**: `agent-browser wait $(bash scripts/jitter.sh MIN MAX)` between actions. Defaults:
   - After nav / tab switch: 600–1600 ms
   - Between fills in a form: 300–1000 ms
   - Before clicking Sign in / Post / Share: 1200–3000 ms
3. **Real keystrokes for human-typed fields**: `agent-browser type @<ref>` (not `fill`) for username, password, single-line caption. **For multi-line content (post captions, tweet text) on IG and X, use `agent-browser keyboard type "$TEXT"` — NOT `type @<ref>`**. IG and X both use Lexical contenteditable editors; `type @<ref>` swallows embedded `\n` and produces a run-on paragraph, while `keyboard type` sends real Enter keystrokes that Lexical converts to proper `<br><br>` paragraph breaks AND auto-styles `#hashtags` with the link spans. LinkedIn's editor handles `type @<ref>` newlines fine — it's a different implementation. Reach for `keyboard type` whenever you've focused a contenteditable.
4. **`fill` / `upload` for file inputs**: file paths get pasted, not typed. `agent-browser upload <selector> <files...>` accepts multiple positional paths — use it for carousel posts on IG and LinkedIn (both expose `input[type=file]` with `multiple=true`). The same input accepts video on every platform we use; pre-encode iPhone screen recordings to h264 first via `pad_ios_video.sh` to avoid HEVC re-transcodes.
5. **Pre-pad iPhone media before posting**:
   - **Images** → `bash scripts/pad_ios_screenshot.sh <input> [output] [mode]` pads to 4:5 (Instagram feed). Plain modes: `edge` (seamless), `blur` (Apple-style), `random` (palette), `#RRGGBB`. Fancy modes (random gradient bg + SVG decoration layer): `gradient`, `bloom`, `sparkle`, `cosmic`, `divine` (golden crosses + scripture words), `holy` (divine + Bibles + flying-dove silhouettes), `lovely` (hearts), `dream` (faded words over blur). `surprise` rolls one of the fancy modes — `/post-daily-devotional` defaults to this. The decoration layer is rasterized via `rsvg-convert`, not `magick` — magick's SVG path can't resolve fontconfig text fonts on macOS so any `<text>` element makes it error with "unable to read font ''". `brew install librsvg` if it's missing.
   - **Videos** → `bash scripts/pad_ios_video.sh <input> [output] [mode]` pads to 9:16 (Instagram Reels) and re-encodes to 1080×1920 h264 + AAC + faststart. Modes: `blur` (default), `black`, `#RRGGBB`. Cross-platform safe — IG/LinkedIn/X all accept the output cleanly (avoids HEVC ingest issues).
   Skill steps that take iPhone media should always pass through these helpers first.
6. **Form-field logging mandatory**: every login/post run writes `~/.social-skills/logs/<action>/<platform>-<account>-<ts>.json` with the `@refs` it discovered. If a platform changes its UI, this is the breadcrumb that makes it easy to update the skill.
7. **`.env` parsing**: don't `source .env` — passwords contain `$`, backticks, etc. that re-evaluate. Use `grep -m1 '^KEY=' .env | cut -d= -f2-` to extract literal values.
8. **Per-platform credential format** (see `.env.example` for the full list):
   - Instagram: `INSTAGRAM_<ACCOUNT_LABEL>_USERNAME` / `_PASSWORD` (e.g. `INSTAGRAM_SWIFTBIBLE_*`).
   - LinkedIn / X / Pinterest: unsplit `<PLATFORM>_USERNAME` / `_PASSWORD` (single account each). X uses `TWITTER_*`.
   - TikTok: manual-login only — auto-login isn't worth attempting against TikTok's CAPTCHA gauntlet. State at `~/.config/agent-browser/tiktok-default.json`.

## X account routing (set 2026-05-07)

Two X accounts are signed into the shared browser: `@swift_bible` (Swift Bible product brand) and `@vanities` (the user's personal builder/dev account). The Chrome session can have either active at any moment, so **every X-touching skill MUST take an explicit `account` arg and switch the session before composing**. There is no default account.

- `@swift_bible` — brand voice. Daily devotionals, Swift Bible product feature posts, Swift Bible warming. Caption tone: app-as-product.
- `@vanities` — builder voice. Doc Vault and any other GitHub-hosted personal projects, dev-flavored cross-posts of Swift Bible features (the "I built this" angle), long-form Articles. Caption tone: builder-as-author.

The switcher (`scripts/x_switch_account.sh <handle>`) reads `[data-testid=AppTabBar_Profile_Link]` for the current handle, opens `[data-testid=SideNav_AccountSwitcher_Button]`, and clicks the matching `[data-testid=UserCell]` (filtering out "Follow" suggestion cells). It's a no-op when already on target. Selectors verified live 2026-05-07; not yet exercised in a cron firing.

`/post-daily-devotional` passes `swift_bible` to `/x-post`. `/feature-post` passes `swift_bible` to `/x-post`. `/x-article` is invoked with whichever account fits the content (DocVault → `vanities`; future Swift Bible long-form → both, two separate runs).

## Skills available

| Skill | Purpose | Status |
|---|---|---|
| `/instagram-login <account>` | Log in (auto via .env or manual). Save state. | ✅ Tested live with `swiftbible` |
| `/instagram-post <account> <media> <caption>` | Click Create → upload → crop (4:5 for image, Mobile/9:16 for Reel) → caption → Share. Image OR video; vertical video auto-becomes a Reel. | ✅ Tested live as image carousel + as Reel (2026-05-05 Explain feature, 37s video) |
| `/post-daily-devotional` | Composite: `xcrun simctl io booted screenshot` → `/instagram-post`. Default account `swiftbible`. | ✅ Posted live 2026-05-04 |
| `/linkedin-login` | Auto via .env. Pauses for verification PIN if checkpoint appears. | ✅ Live-tested through PIN challenge |
| `/linkedin-post <personal\|<company-id>> <media> <caption>` | Personal feed OR company-page post (e.g. `104970470` for AM2 LLC). Pass multiple media paths to upload a carousel. Accepts image or video. | ✅ Live-tested 2026-05-04 (AM2 LLC, 2-image carousel) + 2026-05-05 (AM2 LLC, single video) |
| `/x-login` | Two-step username → password flow. Auto via `TWITTER_USERNAME` / `TWITTER_PASSWORD` (username can be handle, email, or phone). Pauses for any verification challenge. | ✅ Live-tested 2026-05-04 (`swiftbible@am2.biz`, no challenge surfaced) |
| `/x-post <account> <thread-json>` | Single tweet OR multi-tweet via reply chain on the given X account. First arg is the handle (no `@`, e.g. `swift_bible` or `vanities`) — REQUIRED, no default; the skill switches the X session to that handle via `scripts/x_switch_account.sh` before composing. Reads JSON `[{text, media?}, ...]`. First tweet supports up to 4 images via `multiple=true` input OR exactly 1 video; subsequent tweets are posted as **replies** to the previous (not in-modal threads — see skill for why). | ✅ Live-tested 2026-05-04 (1 single tweet + 1 three-tweet reply chain) + 2026-05-05 (single tweet with 37s video on `@swift_bible`). Account-switcher arg added 2026-05-07 — not yet exercised in cron but selectors verified live. |
| `/x-article <account> <slug> <source>` | **Draft-helper, not publisher.** Reads a source (repo path, file, or `-` for in-conversation context), writes `articles/<slug>.md` with `[SUBHEADING]`, `[BLOCKQUOTE]`, `[INLINE IMAGE]` markers + absolute paths so the user can paste paragraph-by-paragraph into the X Article composer at `x.com/compose/articles`. Does NOT auto-publish — the composer's Lexical editor races on markdown shortcuts AND hides toolbar buttons contextually, so reliable auto-fill is impractical. See skill for the full reasoning. | ⚠️ Skill written 2026-05-07 (rewritten as draft-helper after live testing showed auto-fill was too fragile). First end-to-end use: DocVault article for `@vanities`, `articles/docvault.md`. |
| `/feature-post <description> [platforms]` | Orchestrates the full multi-platform feature-launch flow: drive iOS sim → capture screenshots / video → pad → draft platform-tailored captions → user approval → cross-post to LinkedIn (AM2 LLC) / IG (swiftbible) / X (swift_bible) / Pinterest (swiftbible). LinkedIn/IG/X get an announcement-style caption; Pinterest gets a search-rewritten how-to with a different board (`Bible Study Tools`, not `Daily Devotionals`). Composes the per-platform `/<platform>-post` skills. | ⚠️ Skill written, not yet end-to-end tested as a single invocation (every component step has been exercised, Pinterest leg added 2026-05-05 but not yet exercised inside `/feature-post`) |
| `/tiktok-post` | DEFERRED. TikTok's web upload is **video-only** (Photo Mode is mobile-app exclusive). Skill documents the blocker + 3 unblock paths (real video pipeline, image-to-video helper, iOS-app automation via XcodeBuildMCP). | 🚫 Blocked on video content / video pipeline |
| `/reddit-post <sub> <title> <body>` | STUB. Reddit fundamentally breaks the cross-post / cron / warm patterns: self-promo is heavily policed (10:1 rule), each sub has its own culture (no fan-out), and bot detection is aggressive. Use only as a single-shot helper for hand-crafted posts to subs where the account has built karma. **Not** called by `/post-daily-devotional` or `/feature-post`. | 🚫 Stub only — needs ~2-3 weeks of manual karma-building before any post is safe |
| `/pinterest-login` | Auto via `PINTEREST_USERNAME` / `PINTEREST_PASSWORD`. Pauses for any CAPTCHA challenge. | ✅ State saved 2026-05-04 (user signed in manually via .env email/password; auto-login via skill not yet exercised) |
| `/pinterest-post <pin-json>` | Reads JSON `{media, title, description, board, link?}`. Tall iPhone screenshots fit natively (no padding). Creates the board inline if it doesn't exist. | ✅ Live-tested 2026-05-04 (first pin: "James 2:12" daily devotional in board "Daily Devotionals" on `pinterest.com/swiftbible`) |
| `/x-warm` | One warming pass on `@swift_bible` — scroll feed + 1-3 likes + maybe 1 repost. Reads `config/engagement-schedule.json`, updates `~/.social-skills/state/engagement-state.json`. Skips comments + own tweets. | ✅ Live-tested 2026-05-04 (1 scroll pass + 1 like on @Bible365_'s tweet; verified via Like→Liked aria-label flip) |
| `/pinterest-warm` | One warming pass on `swiftbible` — scroll feed + 1-4 saves (default board "Profile") + maybe 1 follow. | ✅ Save-action live-tested (saved 1 pin via click→detail→Save flow); skill itself not yet invoked end-to-end |
| `/instagram-warm` | One warming pass on `swift_bible` — scroll feed + 1-3 likes. **No follow / comment** (IG is the strictest about bot-detection). | ⚠️ Skill written, not yet live-tested; mirrors `/x-warm` UI patterns |
| `/warm-all` | Picks the most-stale eligible platform and runs its warm skill once. Designed to be cron'd 2-3× daily at staggered times. | ⚠️ Written, not yet live-tested |

## Live state (as of 2026-05-05)

- **`swiftbible`** Instagram (https://www.instagram.com/swift_bible/) — logged in, 3 live posts:
  1. Daily devotional (May 4 — James 2:12)
  2. Feature carousel (May 4): redesigned More tab + new History view. Run log at `~/.social-skills/logs/post/instagram-swiftbible-2026-05-04T112554.json`.
  3. **Feature Reel (May 5)**: 37s screen recording of the on-device Apple Intelligence "Explain" chat feature (tap a verse → AI explanation → chat for follow-ups). Pre-padded 9:16 with blurred bg via the new `pad_ios_video.sh`. Run log: `~/.social-skills/logs/post/instagram-swiftbible-2026-05-05T084703-explain-reel.json`.
  Bio: "📖 Daily devotionals from the Swift Bible app. New post every day at noon. am2.biz/swiftbible".
- **LinkedIn personal** (`mischkeaa@gmail.com` → `Adam Mischke`) — logged in, state saved.
- **AM2 LLC company page** (id `104970470`) — admin access confirmed. Two live posts:
  1. 2-image feature carousel (May 4): More tab + History view. Run log: `~/.social-skills/logs/post/linkedin-104970470-2026-05-04T111757.json`.
  2. **Single-video feature post (May 5)**: same Explain feature 37s video. Caption note: kept `am2.biz/swiftbible` (the user said leave LinkedIn as-is when we switched IG/X to the App Store URL mid-run). Run log: `~/.social-skills/logs/post/linkedin-104970470-2026-05-05T083747-explain.json`.
- **X (Twitter)** `@swift_bible` (account `swiftbible@am2.biz`) — logged in 2026-05-04, state at `~/.config/agent-browser/x-default.json`. Posts so far: (1) daily devotional tweet (May 4), (2) 3-tweet reply chain on the More-tab/History feature, (3) **single tweet with 37s Explain feature video (May 5)** at https://x.com/swift_bible/status/2051660998411423871 — no graduated-access modal this time (account is past that gate). Run log: `~/.social-skills/logs/post/x-default-2026-05-05T085110-explain.json`.
- **TikTok** `@swiftbible` (note: NO underscore, unlike IG/X handles) — logged in 2026-05-04 manually via the painful web sign-in (CAPTCHAs etc.; do not attempt auto-login). State at `~/.config/agent-browser/tiktok-default.json` (~539KB). **No posts yet** — `/tiktok-post` is deferred because web upload is video-only and we don't have a video pipeline. See `.claude/skills/tiktok-post/SKILL.md` for the three unblock paths. Bio: "📖 Daily devotionals from the Swift Bible app. New every day at noon." with `am2.biz/swiftbible` in the link field.
- **Pinterest** `swiftbible` (`pinterest.com/swiftbible`, same handle as TikTok — no underscore). Logged in 2026-05-04 (creds in `.env` as `PINTEREST_USERNAME` / `PINTEREST_PASSWORD`; state at `~/.config/agent-browser/pinterest-default.json`). Bio matches the Swift Bible voice. Live pins:
  1. 2026-05-04 — "James 2:12 — The Law of Liberty" (daily devotional) → board `Daily Devotionals` → link `am2.biz/swiftbible`.
  2. 2026-05-05 — "Song of Solomon 4:12 — A Garden Enclosed" (daily devotional) → board `Daily Devotionals` → link `am2.biz/swiftbible`.
  3. **2026-05-05 — "AI Bible Study App for iPhone — Chat with Verses…" (feature post, Apple Intelligence Explain) → NEW board `Bible Study Tools` → App Store link.** First exercise of the Pinterest leg of `/feature-post` with the search-rewritten title/description pattern. Run log: `~/.social-skills/logs/post/pinterest-default-2026-05-05T174222-explain.json`.

  **Board strategy** (set 2026-05-05): `Daily Devotionals` for cron-fired per-day verses; `Bible Study Tools` for `/feature-post` cross-posts (search-rewritten how-to content). Don't mix.

  **Pinterest auto-saves form state as drafts** while you type — clicking "Create new Pin" (top-left) drops the current form to a draft instead of publishing; the actual publish action is the red **"Publish"** button (top-right). Tall iPhone screenshots fit natively here (Pinterest is built for 2:3 / tall content), so no `pad_ios_screenshot.sh` step needed.

## Cron

Installed 2026-05-04 (was previously documented but never installed). View / edit with `crontab -l` / `crontab -e`.

```cron
# Daily devotional fan-out: noon local, posts to IG + X + Pinterest (skips LinkedIn)
0 12 * * * /bin/bash /Users/vanities/git/work/me/social-skills/scripts/daily_devotional.sh

# Engagement warming: 3 staggered slots within active hours (8-22).
# Each fires /warm-all which picks the most-stale eligible platform (X / Pinterest / IG)
# and runs ONE warm pass. Off-the-hour minutes (:17, :43, :22) so it doesn't look bot-clocked.
17 9  * * * /bin/bash /Users/vanities/git/work/me/social-skills/scripts/warm_all_cron.sh
43 13 * * * /bin/bash /Users/vanities/git/work/me/social-skills/scripts/warm_all_cron.sh
22 18 * * * /bin/bash /Users/vanities/git/work/me/social-skills/scripts/warm_all_cron.sh
```

Both wrappers `cd` into the repo, restore PATH for macOS cron, and invoke `claude --print --dangerously-skip-permissions "/<skill>"`. The flag is necessary because cron can't approve interactive permission prompts. Logs land in `~/.social-skills/logs/cron/<date>.log` (devotional) and `~/.social-skills/logs/cron/warm-<date>.log` (warming).

## In-flight work (next session resumes here)

1. **Watch the cron run for a few days** — both `/post-daily-devotional` (noon) and `/warm-all` (9:17 / 13:43 / 18:22) are now installed and use `--dangerously-skip-permissions`. Check `~/.social-skills/logs/cron/*.log` and `~/.social-skills/logs/warm/*.json` to confirm each fire executes cleanly. First eligible warm-all fire from now: 18:22 today.
2. **Live-test `/post-daily-devotional` end-to-end** as a single skill call (today's invocation was manual step-by-step on May 4). The refactored skill drafts captions for all 3 platforms by reading the screenshot directly. Risk: caption auto-generation may produce something off-brand on day 1; review the first cron-fired run's outputs and tune the templates if needed.
3. **`/feature-post` end-to-end live-test**: skill written, every component exercised manually but never as a single invocation. Next feature ship → invoke `/feature-post` to validate.
4. **Facebook (AM2 LLC Page)**: not yet built. Easiest first step is creating an AM2 LLC Page → linking to IG via Meta Accounts Center → enable the IG composer's cross-post toggle (no automation required). `/facebook-post` is the harder route if that toggle isn't reliably visible on web.
5. **Bluesky**: similar architecture to X minus the graduated-access friction (~1hr to mirror `/x-login` + `/x-post`). Not started.
6. **Reddit**: stub written (`.claude/skills/reddit-post/SKILL.md`). Real cost is content production per post (every sub has its own voice). Don't attempt without ~2-3 weeks of manual karma-building first in target subs (r/SideProject is the most lenient for indie-dev posts; r/Christianity disallows self-app-linking; r/iOSProgramming allows it with prep).
7. **TikTok / YouTube Shorts**: deferred until a video pipeline exists. See `.claude/skills/tiktok-post/SKILL.md`.

## Known issues / gotchas

- **`agent-browser snapshot -i` does NOT see inside `[role=dialog]` modals on Instagram** (Crop, Edit, Sharing, Post shared). It picks up sidebar / feed elements behind the modal but misses the modal's own buttons/textboxes. Pattern: enumerate dialogs via `eval`, then click buttons inside via `eval` too.
   ```bash
   agent-browser eval "(()=>{const dialogs=document.querySelectorAll('[role=dialog]');return Array.from(dialogs).map(d=>({label:d.getAttribute('aria-label'),visible:d.offsetParent!==null}))})()"
   agent-browser eval "(()=>{const d=document.querySelector('[role=dialog][aria-label=Crop]');const next=Array.from(d.querySelectorAll('button,[role=button]')).find(b=>b.textContent.trim()==='Next');next.click()})()"
   ```
   Caption/textbox inputs ARE surfaced by snapshot (so `keyboard type` after focus works), but Share / Next / OK / Done buttons inside dialogs need eval-based clicks.
- **NEVER use `agent-browser` for any liveness / diagnostic check on Chrome**. agent-browser auto-spawns a fresh Chrome when its CDP WebSocket can't connect — even if Chrome's HTTP `/json/version` endpoint is responding. Those endpoints have *different* reliability profiles: a Chrome can be HTTP-alive but WebSocket-broken (overnight idle, partial crash), and `agent-browser tab list` will quietly kill that Chrome and replace it with a fresh `about:blank` instance. The user has to click "Restore" to recover tabs. Caught 2026-05-05 (my diagnostic `tab list` killed the user's session) AND 2026-05-06 noon (the cron's own `tab list` guard step did the same — even though HTTP `/json/version` had succeeded a moment earlier).
- **Correct cron guard: probe via plain HTTP `/json/list`, grep the JSON for platform URLs, never invoke agent-browser before `claude --print`**. `/json/list` returns the full tab array (read-only HTTP, can't spawn anything) and the URLs in that array tell you both "Chrome is alive" AND "it's our Chrome with logged-in tabs". If the array is empty or only contains `about:blank` / `chrome://newtab`, skip. `daily_devotional.sh` and `warm_all_cron.sh` both use this pattern as of 2026-05-06.
- **Skills do tab discovery via `scripts/find_platform_tab.sh <url-substring>` too — NOT `agent-browser tab list`**. Same root cause: the spawn risk is in agent-browser's CDP attach, not just in the wrapper guard. The 6:22 PM cron on 2026-05-06 fired cleanly through the wrapper guard, but the IG warm skill's Step 4 (`agent-browser tab list 2>&1 | head -10`) respawned Chrome anyway. All cron-path skills (instagram-warm, pinterest-warm, x-warm, instagram-post, x-post, pinterest-post, linkedin-post) were patched 2026-05-06 evening to use `find_platform_tab.sh`. Login skills (`*-login`) and `reddit-post` / `tiktok-post` still have the old pattern — lower priority since they're interactive (user is watching when they fire).
- **Be careful with backticks in shell** — they trigger command substitution. `echo "Remaining \`agent-browser tab list\` references"` actually RUNS `agent-browser tab list` before the echo. Use single quotes, escape with `\`, or rephrase. Caused a near-miss respawn 2026-05-06 evening while writing diagnostic output about the very pattern we were trying to avoid.
- **DevToolsActivePort is a stale file that persists after Chrome quits** — never trust its presence as proof Chrome is alive. Always validate with the HTTP probe.
- **The cron's PATH must include `~/.vite-plus/bin`** — that's where `agent-browser` lives. macOS cron has a stripped PATH, and the wrapper's `export PATH=` line must restore it explicitly. Caused 2026-05-06 9:17 AM warm to skip with `command not found`.
- **`agent-browser tab <index>` sometimes prints the target tab info but doesn't transfer focus**. Symptom: subsequent `get url` returns the *previous* tab's URL, and `snapshot` shows the previous tab's content. Workaround: re-issue `agent-browser tab <index>` followed by `sleep 2`, then verify with `get url` before continuing. First-attempt success is the common case; the flake shows up under load.
- **IG Reels Crop dialog defaults to 1:1**, not Mobile (9:16). Even for a vertical video, IG will square-crop the middle unless you explicitly select the 9:16 aspect via the "Select crop" popover. Skill auto-picks for vertical media; if the eval reports no Mobile/9:16 option, the skill aborts with a message — don't click Next on a wrong aspect.
- **IG's "Select crop" button is the ONE element in the entire stack that requires a real mouse event** — `agent-browser click @<ref>` and JS `.click()` both fail to open its popover (other buttons inside the same dialog respond fine). Use `agent-browser mouse move/down/up` at the button's bbox center. Once the popover is open, the aspect options (`Original`, `1:1`, `4:5`, `16:9`/`Mobile`) DO surface in `snapshot -i` and respond to normal `click @<ref>`. Hit this 2026-05-05 first daily devotional run; user caught the wrong aspect, we recovered with real mouse events.
- **Pinterest's Publish button scrolls off-screen** by the time you fill the form (the form grows past one viewport). Clicking a button at negative-y silently no-ops AND saves the form as a draft (you'll see `Pin drafts (N+1)` instead of a published toast). Always `agent-browser scrollintoview @<PUBLISH_REF>` before the click. Hit 2026-05-05; skill now scrolls before publishing.
- **LinkedIn auto-attaches a link card** when the caption contains a URL (e.g. `am2.biz/swiftbible`, App Store URL) — it occupies the single media slot. Click "Remove media" before "Add media" to free the slot. Skill handles this.
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
- 2026-05-05: Added video flow to `/instagram-post` (auto-becomes Reel on web), `/linkedin-post`, `/x-post`. New helper `scripts/pad_ios_video.sh` mirrors `pad_ios_screenshot.sh` (1080×1920 9:16, blurred-bg default, also re-encodes HEVC → h264 for cross-platform safety). Codified the **`agent-browser keyboard type` for multi-line captions** rule (IG and X both use Lexical contenteditable; `type @ref` swallows newlines). Documented the `[role=dialog]` snapshot blind-spot — IG modal interactions need `eval`-based clicks.

## Pointers

- Memory: `~/.claude/projects/-Users-vanities-git-work-me-social-skills/memory/`
- User's global rules referencing `agent-browser`: `/Users/vanities/git/work/teraflop/teraflop-dev-setup/rules/validate-ui.md` and `solutions-fabric-auth.md`.
- Repo: `git@github.com:vanities/social-skills.git` (PRIVATE, pushed 2026-05-04, renamed from `social-agents` 2026-05-08).
- Local state dir: `~/.social-skills/` (chrome-profile, logs, state). Renamed from `~/.social-agents/` 2026-05-08; `~/.social-agents` is a backward-compat symlink to the new path until next Chrome restart.
