---
name: instagram-login
description: One-time manual login for an Instagram account. Opens Chrome with a persistent profile so future agent runs skip login. Use when the user says "log in to instagram" or runs /instagram-login.
disable-model-invocation: true
argument-hint: [account-label]
allowed-tools: Bash(uv run social-agents login*)
---

Run the manual-login flow for the given account label:

```!
uv run social-agents login --platform instagram --account "$0"
```

A real Chrome window opens. The user signs in (including any 2FA) in the browser. When they press Enter in the terminal, the session is saved to `~/.social-agents/profiles/<account>/` for future agent runs.
