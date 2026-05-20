---
name: pinterest-login
description: Log into Pinterest in the shared headed Chrome. Auto-mode if .env has PINTEREST_USERNAME / PINTEREST_PASSWORD set; pauses for any verification challenge Pinterest throws on a new device. Logs the form refs found. Use when the user says "log into pinterest" or runs /pinterest-login.
allowed-tools: Bash(agent-browser *) Bash(mkdir *) Bash(test *) Bash(date *) Bash(grep *) Bash(cat *) Bash(cut *) Read(.env)
---

# Pinterest login

State path (backup): `~/.config/agent-browser/pinterest-default.json`
Log path:           `~/.social-skills/logs/login/pinterest-default-<timestamp>.json`

`.env` uses unsplit `PINTEREST_USERNAME` / `PINTEREST_PASSWORD` (single account, same convention as LinkedIn / X). The username is typically the account email.

## Snapshot tabs (for cleanup at end)

```bash
# Record the current tab set so the final step can close anything we spawn.
# No-op behaviorally when config/brand.json has keep_tabs_open: true.
# Note: a NEW Pinterest tab created here (when none existed) is protected by
# the essential_tabs whitelist in the closer — it won't be touched.
# See AGENTS.md → "Spawned-tab cleanup".
TAB_BASELINE="${HOME}/.social-skills/state/tab-baseline-pinterest-login.json"
bash scripts/tab_baseline_save.sh "$TAB_BASELINE"
```

## Find or open the Pinterest tab

```bash
# Find the existing Pinterest tab and switch into it; opens the login URL ONLY
# if no pinterest.com tab exists. NEVER `agent-browser tab list` (auto-spawn
# risk) — the helper is curl-based find + switch + verify, no duplicate.
bash scripts/switch_to_platform_tab.sh "pinterest.com" "https://www.pinterest.com/login/"
agent-browser wait --load networkidle
```

Then check `agent-browser get url` — if already on the home feed (`pinterest.com/` with content visible), skip to "Save state".

## Snapshot the login form

```!
agent-browser snapshot -i 2>&1 | grep -iE '(textbox.*[Ee]mail|textbox.*[Pp]assword|button.*[Ll]og in)' | head -5
```

Identify `@refs` for:
- Email textbox
- Password textbox
- "Log in" button

Pinterest also offers Google / Facebook sign-in; if `.env` only has email creds, ignore those buttons.

**Record the refs in the run log.**

## Sign in

`.env` may contain shell-special chars. DO NOT `source .env`:

```bash
P_USER=$(grep -m1 '^PINTEREST_USERNAME=' .env | cut -d= -f2-) && \
P_PASS=$(grep -m1 '^PINTEREST_PASSWORD=' .env | cut -d= -f2-) && \
agent-browser click @<EMAIL_REF> && \
agent-browser wait $(bash scripts/jitter.sh 300 700) && \
agent-browser type @<EMAIL_REF> "$P_USER" && \
agent-browser wait $(bash scripts/jitter.sh 400 1000) && \
agent-browser click @<PASSWORD_REF> && \
agent-browser wait $(bash scripts/jitter.sh 300 700) && \
agent-browser type @<PASSWORD_REF> "$P_PASS" && \
agent-browser wait $(bash scripts/jitter.sh 1200 2800) && \
agent-browser click @<LOGIN_REF> && \
agent-browser wait --load networkidle
```

## Handle verification challenge

```!
agent-browser get url
```

If the URL contains `/captcha/` or the page shows "Are you a human" / a slider CAPTCHA, **stop and ask the user** to solve it manually, then continue. Pinterest occasionally throws a CAPTCHA on first login from a fresh fingerprint; less aggressive than X/TikTok but still possible.

If the URL contains `/business/onboarding/` or a "Welcome" wizard, click through with the defaults (or just navigate to `https://www.pinterest.com/`).

## Verify

```!
agent-browser get url
```

Expected: `pinterest.com/` (home feed). Anything else → write log with `outcome: failed`, abort.

## Save state

```!
mkdir -p ~/.config/agent-browser ~/.social-skills/logs/login
agent-browser state save ~/.config/agent-browser/pinterest-default.json
```

## Write the run log

Use the `Write` tool to create `~/.social-skills/logs/login/pinterest-default-<timestamp>.json`:

```json
{
  "ts_start": "<ISO 8601 UTC>",
  "ts_end":   "<ISO 8601 UTC>",
  "platform": "pinterest",
  "account":  "default",
  "action":   "login",
  "mode":     "auto | manual",
  "outcome":  "success | challenge_solved | failed",
  "tab_strategy": "switched | opened-new | already-signed-in",
  "form_fields_discovered": {
    "email_field":    "@<ref>",
    "password_field": "@<ref>",
    "login_button":   "@<ref>"
  },
  "verification_challenge": null,
  "final_url":  "<url>",
  "state_file": "~/.config/agent-browser/pinterest-default.json"
}
```

## Close spawned tabs

```bash
bash scripts/close_spawned_tabs.sh "$TAB_BASELINE"
rm -f "$TAB_BASELINE"
```

## Report

Account, state file, log file, final URL. **Do not close the Pinterest platform tab** — the closer protects it via `essential_tabs`.
