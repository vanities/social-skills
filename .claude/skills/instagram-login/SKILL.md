---
name: instagram-login
description: Log into an Instagram account in the shared headed Chrome. If .env has INSTAGRAM_<ACCOUNT>_USERNAME / _PASSWORD set, signs in automatically; otherwise pauses for manual sign-in. Always logs the form fields it found so we can detect IG UI changes. Use when the user says "log in to instagram" or runs /instagram-login.
argument-hint: [account-label]
allowed-tools: Bash(agent-browser *) Bash(mkdir *) Bash(test *) Bash(date *) Bash(grep *) Bash(cat *) Bash(source *) Read(.env)
---

# Instagram login for account `$0`

State path (backup, for cron / cold-start runs): `~/.config/agent-browser/instagram-$0.json`
Log path: `~/.social-skills/logs/login/instagram-$0-<timestamp>.json`
Reference: `docs/platforms/instagram.md`.

The default mode of operation is the **shared headed Chrome** — keep the browser alive across sessions so the user and the agent both work in it. State files exist as a fallback for fresh-process runs (cron).

## Decide auto vs manual

```!
grep -q "^INSTAGRAM_$(echo "$0" | tr '[:lower:]' '[:upper:]')_USERNAME=" .env 2>/dev/null && echo "MODE: auto" || echo "MODE: manual"
```

## Find or open the Instagram tab

```!
agent-browser tab list 2>&1
```

- If a tab matches `instagram.com`, switch to it: `agent-browser tab <index>`. Then check `agent-browser get url` — if it's already on a feed URL (not `/accounts/login/`), the user is already signed in and you can skip to "Save state".
- If no IG tab: `agent-browser --headed tab new https://www.instagram.com/accounts/login/` (or `agent-browser --headed open ...` if there are zero tabs at all).

Always `agent-browser wait --load networkidle` after.

## Snapshot the login form

```!
agent-browser snapshot -i 2>&1 | grep -E '(textbox|button "Log)' | head -10
```

From the output, identify the `@refs` for:

- Username textbox (label like "Mobile number, username or email")
- Password textbox (label "Password")
- "Log In" button

**You must record these refs in the run log** (Step "Write the run log" below). If Instagram changes the form, the log is how we'll see it.

## Sign in

### Auto mode (creds in .env)

Replace `<USER_REF>`, `<PW_REF>`, `<LOGIN_REF>` with the refs from the snapshot. Do not echo the password into your response. Use `type` (real keystrokes) over `fill` (instant batch) and add jitter — see `docs/platforms/instagram.md` § "Human-like timing".

```bash
source .env && \
ACC_UPPER="$(echo "$0" | tr '[:lower:]' '[:upper:]')" && \
USERNAME_VAR="INSTAGRAM_${ACC_UPPER}_USERNAME" && \
PASSWORD_VAR="INSTAGRAM_${ACC_UPPER}_PASSWORD" && \
agent-browser type @<USER_REF> "${!USERNAME_VAR}" && \
agent-browser wait $(bash scripts/jitter.sh 300 900) && \
agent-browser type @<PW_REF> "${!PASSWORD_VAR}" && \
agent-browser wait $(bash scripts/jitter.sh 1200 2800) && \
agent-browser click @<LOGIN_REF> && \
agent-browser wait --load networkidle
```

### Manual mode

Tell the user:

> Sign in in the Chrome tab, including any 2FA. Reply "done" when you're on the home feed.

## Handle post-login dialogs

Snapshot. Common dialogs:

- **"Save your login info?"** at `/accounts/onetap/` → click **"Not now"**.
- **"Turn on Notifications"** → click **"Not Now"**.
- **2FA challenge** → in auto mode, abort and tell the user to do `/instagram-login $0` again manually; in manual mode, the user has already handled it.

For each dialog dismissed, record `{ref, label, context}` for the run log.

## Verify

```!
agent-browser get url
```

Expected: `https://www.instagram.com/`. If still on `/accounts/login/`, capture a snapshot, write the log with `outcome: failed` + the snapshot inline, then abort.

## Save state (backup)

```!
mkdir -p ~/.config/agent-browser ~/.social-skills/logs/login && agent-browser state save ~/.config/agent-browser/instagram-$0.json
```

## Write the run log

Use the `Write` tool to create `~/.social-skills/logs/login/instagram-$0-<timestamp>.json`:

```json
{
  "ts_start": "<ISO 8601 UTC>",
  "ts_end":   "<ISO 8601 UTC>",
  "platform": "instagram",
  "account":  "$0",
  "action":   "login",
  "mode":     "auto | manual",
  "outcome":  "success | 2fa_required | failed",
  "tab_strategy": "switched | opened-new | already-signed-in",
  "form_fields_discovered": {
    "username_field":     "@<ref>",
    "username_label":     "<label>",
    "password_field":     "@<ref>",
    "password_label":     "<label>",
    "login_button":       "@<ref>",
    "login_button_label": "<label>"
  },
  "post_login_dialogs_dismissed": [
    { "ref": "@<ref>", "label": "<button label>", "context": "<page url or descriptor>" }
  ],
  "final_url":  "<url>",
  "state_file": "~/.config/agent-browser/instagram-$0.json"
}
```

Substitute `<timestamp>` with `date +%Y-%m-%dT%H-%M-%S`.

## Report

- Account label, state file path, log file path.
- Tab where IG is now (so the user can find it).
- Whether `/instagram-post $0 …` or `/post-daily-devotional` is ready to run.

**Do not close the tab.** The shared browser stays open.
