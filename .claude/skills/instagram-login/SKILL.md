---
name: instagram-login
description: Log into an Instagram account. If .env has INSTAGRAM_<ACCOUNT>_USERNAME / _PASSWORD set, signs in automatically; otherwise pauses for manual sign-in. Always logs the form fields it found so we can detect IG UI changes. Use when the user says "log in to instagram" or runs /instagram-login.
disable-model-invocation: true
argument-hint: [account-label]
allowed-tools: Bash(agent-browser *) Bash(mkdir *) Bash(test *) Bash(date *) Bash(grep *) Bash(cat *) Bash(source *) Read(.env)
---

# Instagram login for account `$0`

State path: `~/.config/agent-browser/instagram-$0.json`
Log path:   `~/.social-agents/logs/login/instagram-$0-<timestamp>.json`

See `docs/platforms/instagram.md` for the full IG playbook.

## Decide auto vs manual

```!
grep -q "^INSTAGRAM_$(echo "$0" | tr '[:lower:]' '[:upper:]')_USERNAME=" .env 2>/dev/null && echo "MODE: auto" || echo "MODE: manual"
```

## Open the login page

```!
agent-browser open https://www.instagram.com/accounts/login/ && agent-browser wait --load networkidle
```

## Snapshot the login form

```!
agent-browser snapshot -i 2>&1 | grep -E '(textbox|button "Log)' | head -10
```

From the output above, identify the `@refs` for:

- Username textbox (label like "Mobile number, username or email")
- Password textbox (label "Password")
- "Log In" button

**You must record these refs in the run log** (Step "Write the run log" below). If Instagram changes the form layout, the log is how we'll see it.

## Sign in

### Auto mode (creds in .env)

Replace `<USER_REF>`, `<PW_REF>`, `<LOGIN_REF>` with the refs from the snapshot. Do not echo the password into your response.

```bash
source .env && \
ACC_UPPER="$(echo "$0" | tr '[:lower:]' '[:upper:]')" && \
USERNAME_VAR="INSTAGRAM_${ACC_UPPER}_USERNAME" && \
PASSWORD_VAR="INSTAGRAM_${ACC_UPPER}_PASSWORD" && \
agent-browser fill @<USER_REF> "${!USERNAME_VAR}" && \
agent-browser fill @<PW_REF> "${!PASSWORD_VAR}" && \
agent-browser click @<LOGIN_REF> && \
agent-browser wait --load networkidle
```

### Manual mode (no creds)

Tell the user:

> Sign in in the browser, including any 2FA. Dismiss any "Save your info" or notifications dialogs. Reply "done" when you're signed in and on the home feed.

Wait for the user's "done" before continuing.

## Handle post-login dialogs

Snapshot again. Common dialogs:

- **"Save your login info?"** at `/accounts/onetap/` → click the "Not now" button.
- **"Turn on notifications"** → click "Not now".
- **2FA challenge** → in auto mode, abort and tell the user to do `/instagram-login $0` again manually; in manual mode, the user has already handled it.

For each dialog dismissed, record `{ref, label, context}` for the run log.

## Verify

```!
agent-browser get url
```

The URL should be `https://www.instagram.com/` or another feed URL. If it's still on `/accounts/login/`, the login failed — capture a snapshot, write the log with `outcome: failed` and the snapshot inline, then abort.

## Save state

```!
mkdir -p ~/.config/agent-browser ~/.social-agents/logs/login && agent-browser state save ~/.config/agent-browser/instagram-$0.json
```

## Write the run log

Use the `Write` tool to create a JSON file at `~/.social-agents/logs/login/instagram-$0-<timestamp>.json` with this exact shape (substitute real values):

```json
{
  "ts_start": "2026-05-04T17:04:00Z",
  "ts_end":   "2026-05-04T17:04:34Z",
  "platform": "instagram",
  "account":  "$0",
  "action":   "login",
  "mode":     "auto",
  "outcome":  "success",
  "form_fields_discovered": {
    "username_field":  "@e71",
    "username_label":  "Mobile number, username or email",
    "password_field":  "@e72",
    "password_label":  "Password",
    "login_button":    "@e73",
    "login_button_label": "Log In"
  },
  "post_login_dialogs_dismissed": [
    { "ref": "@e3", "label": "Not now", "context": "Save your login info? at /accounts/onetap/" }
  ],
  "final_url":  "https://www.instagram.com/",
  "state_file": "/Users/vanities/.config/agent-browser/instagram-$0.json"
}
```

Substitute `<timestamp>` with the value of `date +%Y-%m-%dT%H-%M-%S` (no `:` in filenames).

## Close

```!
agent-browser close
```

Confirm to the user:

- Account label.
- State file path.
- Log file path.
- Whether they can now run `/instagram-post $0 …` or `/post-daily-devotional`.
