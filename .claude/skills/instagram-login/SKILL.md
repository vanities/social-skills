---
name: instagram-login
description: One-time manual login for an Instagram account. Opens a browser, the user signs in by hand, agent-browser state is saved for future runs. Use when the user says "log in to instagram" or runs /instagram-login.
disable-model-invocation: true
argument-hint: [account-label]
allowed-tools: Bash(agent-browser *) Bash(mkdir *) Bash(test *)
---

# Manual Instagram login for account `$0`

State path: `~/.config/agent-browser/instagram-$0.json`
See `docs/platforms/instagram.md` for the full IG playbook.

## Step 1: Open the login page

```!
agent-browser open https://www.instagram.com/accounts/login/
agent-browser wait --load networkidle
```

## Step 2: Pause for the user

The browser is open. Tell the user:

> Sign in in the browser, including any 2FA. Dismiss any "Save your info" or notifications dialogs. Reply "done" when you're signed in and on the home feed.

Wait for the user's "done" before continuing.

## Step 3: Save state

```!
mkdir -p ~/.config/agent-browser
agent-browser state save ~/.config/agent-browser/instagram-$0.json
agent-browser close
```

Confirm the saved-state path. Tell the user they can now run `/instagram-post $0 ...` or `/post-daily-devotional`.
