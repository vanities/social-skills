---
name: linkedin-login
description: Log into LinkedIn in the shared headed Chrome. Auto-mode if .env has LINKEDIN_USERNAME / LINKEDIN_PASSWORD set; pauses for any verification PIN that LinkedIn requires on a new device fingerprint. Logs the form refs found. Use when the user says "log into linkedin" or runs /linkedin-login.
disable-model-invocation: true
allowed-tools: Bash(agent-browser *) Bash(mkdir *) Bash(test *) Bash(date *) Bash(grep *) Bash(cat *) Bash(cut *) Read(.env)
---

# LinkedIn login

State path (backup): `~/.config/agent-browser/linkedin-default.json`
Log path:           `~/.social-agents/logs/login/linkedin-default-<timestamp>.json`
Reference:          `docs/platforms/linkedin.md`.

`.env` uses unsplit `LINKEDIN_USERNAME` / `LINKEDIN_PASSWORD` (single LinkedIn account; no per-label split unlike Instagram).

## Find or open the LinkedIn tab

```!
agent-browser tab list 2>&1
```

- If a tab matches `linkedin.com`, switch to it: `agent-browser tab <index>`. Check `agent-browser get url` — if already on `/feed/`, skip to "Save state".
- If no LinkedIn tab: `agent-browser tab new https://www.linkedin.com/login`.

Then `agent-browser wait --load networkidle`.

## Snapshot the login form

```!
agent-browser snapshot -i 2>&1 | grep -iE '(textbox.*Email|textbox.*Password|button.*Sign in)' | head -5
```

Identify `@refs` for:

- Email/phone textbox (label `Email or phone`)
- Password textbox (label `Password`)
- "Sign in" button

**Record these in the run log.**

## Sign in

`.env` may contain shell-special chars (`$`, backtick, etc.) so DON'T `source .env`. Use `grep | cut` to extract values without re-parsing:

```bash
LI_USER=$(grep -m1 '^LINKEDIN_USERNAME=' .env | cut -d= -f2-) && \
LI_PASS=$(grep -m1 '^LINKEDIN_PASSWORD=' .env | cut -d= -f2-) && \
agent-browser type @<USER_REF> "$LI_USER" && \
agent-browser wait $(bash scripts/jitter.sh 400 1000) && \
agent-browser type @<PW_REF> "$LI_PASS" && \
agent-browser wait $(bash scripts/jitter.sh 1200 2800) && \
agent-browser click @<SIGNIN_REF> && \
agent-browser wait --load networkidle
```

## Handle verification PIN

```!
agent-browser get url
```

If URL contains `/checkpoint/challenge/`, LinkedIn sent a verification PIN. **Stop and ask the user**:

> LinkedIn sent a verification PIN. Check your email/phone and paste it.

When the user pastes the code, snapshot the challenge page, find the `Verification code` spinbutton + `Submit pin` button, type the code, click Submit. Then `wait --load networkidle` and re-check URL.

Record the challenge as `{type: "checkpoint", solved: true}` in the run log.

## Verify

```!
agent-browser get url
```

Expected: `linkedin.com/feed/`. Anything else → write log with `outcome: failed`, abort.

## Save state

```!
mkdir -p ~/.config/agent-browser ~/.social-agents/logs/login
agent-browser state save ~/.config/agent-browser/linkedin-default.json
```

## Write the run log

Use the `Write` tool to create `~/.social-agents/logs/login/linkedin-default-<timestamp>.json`:

```json
{
  "ts_start": "<ISO 8601 UTC>",
  "ts_end":   "<ISO 8601 UTC>",
  "platform": "linkedin",
  "account":  "default",
  "action":   "login",
  "mode":     "auto",
  "outcome":  "success | checkpoint | failed",
  "tab_strategy": "switched | opened-new | already-signed-in",
  "form_fields_discovered": {
    "email_field":    "@<ref>",
    "email_label":    "Email or phone",
    "password_field": "@<ref>",
    "login_button":   "@<ref>"
  },
  "verification_pin_required": true,
  "final_url":  "<url>",
  "state_file": "/Users/vanities/.config/agent-browser/linkedin-default.json"
}
```

Substitute `<timestamp>` with `date +%Y-%m-%dT%H-%M-%S`.

## Report

Account, state file, log file, final URL. **Do not close the tab.**
