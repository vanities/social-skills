---
name: x-login
description: Log into X (Twitter) in the shared headed Chrome. Auto-mode if .env has TWITTER_USERNAME / TWITTER_PASSWORD set; pauses for any verification challenge X throws on a new device fingerprint. Logs the form refs found. Use when the user says "log into x" / "log into twitter" or runs /x-login.
allowed-tools: Bash(agent-browser *) Bash(mkdir *) Bash(test *) Bash(date *) Bash(grep *) Bash(cat *) Bash(cut *) Read(.env)
---

# X (Twitter) login

State path (backup): `~/.config/agent-browser/x-default.json`
Log path:           `~/.social-skills/logs/login/x-default-<timestamp>.json`
Reference:          `docs/platforms/x.md` (write this if it doesn't exist).

`.env` uses unsplit `TWITTER_USERNAME` / `TWITTER_PASSWORD` (single account; same convention as LinkedIn). The username can be a handle, email, or phone — X accepts all three on the first screen.

## Snapshot tabs (for cleanup at end)

```bash
# Record the current tab set so the final step can close anything we spawn.
# No-op behaviorally when config/brand.json has keep_tabs_open: true.
# Note: a NEW X tab created here (when none existed) is protected by
# the essential_tabs whitelist in the closer — it won't be touched.
# See AGENTS.md → "Spawned-tab cleanup".
TAB_BASELINE="${HOME}/.social-skills/state/tab-baseline-x-login.json"
bash scripts/tab_baseline_save.sh "$TAB_BASELINE"
```

## Find or open the X tab

```bash
# Find the existing X tab and switch into it; opens the login URL ONLY if no
# x.com tab exists. NEVER `agent-browser tab list` (auto-spawn risk) — the
# helper is curl-based find + switch + verify and won't open a duplicate.
# (twitter.com 301s to x.com, so a logged-in tab is on x.com.)
bash scripts/switch_to_platform_tab.sh "x.com" "https://x.com/i/flow/login"
agent-browser wait --load networkidle
```

Then check `agent-browser get url` — if already on `/home`, skip to "Save state".

## Snapshot the username form

```!
agent-browser snapshot -i 2>&1 | head -25
```

Identify `@refs` for:

- "Phone, email, or username" textbox
- "Next" button

X login is a two-step flow: username → Next → password → Log in. Refs **shift between the two screens** — re-snapshot after each click.

**Record the discovered refs in the run log.**

## Step 1: Type the username and click Next

`.env` may contain shell-special chars. DO NOT `source .env`:

```bash
X_USER=$(grep -m1 '^TWITTER_USERNAME=' .env | cut -d= -f2-) && \
agent-browser click @<USER_REF> && \
agent-browser wait $(bash scripts/jitter.sh 300 700) && \
agent-browser type @<USER_REF> "$X_USER" && \
agent-browser wait $(bash scripts/jitter.sh 400 1000) && \
agent-browser click @<NEXT_REF> && \
agent-browser wait $(bash scripts/jitter.sh 1500 2800)
```

After this, the page transitions to "Enter your password". Re-snapshot.

### Possible interstitial: "Enter your phone number or email address"

If X doesn't recognize the device fingerprint, it may ask for the email/phone associated with the account before showing the password screen. The textbox is labeled `Phone or email`. Type the email (`grep -m1 '^TWITTER_EMAIL=' .env` if present, else fall back to `$X_USER` if it's already an email), click Next, re-snapshot.

## Step 2: Type the password and click Log in

```bash
X_PASS=$(grep -m1 '^TWITTER_PASSWORD=' .env | cut -d= -f2-) && \
agent-browser click @<PW_REF> && \
agent-browser wait $(bash scripts/jitter.sh 300 700) && \
agent-browser type @<PW_REF> "$X_PASS" && \
agent-browser wait $(bash scripts/jitter.sh 1200 2800) && \
agent-browser click @<LOGIN_REF> && \
agent-browser wait 4000
```

## Handle verification challenge

```!
agent-browser get url
```

URL should be `x.com/home` on success. If instead the page shows:

- **"Authenticate your account" / "Verify your identity"**: X sent a code to email or phone. Pause and ask the user:
  > X sent a verification code. Check your email/phone and paste it.
  
  When the user pastes the code, snapshot, find the code textbox + "Next" / "Verify" button, type the code, click. Re-check URL.

- **"Help us keep your account safe"** with a CAPTCHA: pause and ask the user to solve it manually in the browser, then continue.

- **"Suspicious login prevented"**: X blocked the login. Note this in the run log with `outcome: failed` and abort.

Record the challenge as `{type: "<email_pin | phone_pin | captcha | suspicious_block>", solved: true|false}` in the run log.

## Verify

```!
agent-browser get url
```

Expected: `x.com/home`. Anything else → write log with `outcome: failed`, abort.

## Save state

```!
mkdir -p ~/.config/agent-browser ~/.social-skills/logs/login
agent-browser state save ~/.config/agent-browser/x-default.json
```

## Write the run log

Use the `Write` tool to create `~/.social-skills/logs/login/x-default-<timestamp>.json`:

```json
{
  "ts_start": "<ISO 8601 UTC>",
  "ts_end":   "<ISO 8601 UTC>",
  "platform": "x",
  "account":  "default",
  "action":   "login",
  "mode":     "auto",
  "outcome":  "success | challenge_solved | failed",
  "tab_strategy": "switched | opened-new | already-signed-in",
  "form_fields_discovered": {
    "username_field":  "@<ref>",
    "username_label":  "Phone, email, or username",
    "next_button_step1": "@<ref>",
    "password_field":  "@<ref>",
    "login_button":    "@<ref>"
  },
  "verification_challenge": null,
  "final_url":   "<url>",
  "state_file":  "~/.config/agent-browser/x-default.json"
}
```

Substitute `<timestamp>` with `date +%Y-%m-%dT%H-%M-%S`.

## Close spawned tabs

```bash
bash scripts/close_spawned_tabs.sh "$TAB_BASELINE"
rm -f "$TAB_BASELINE"
```

## Report

Account, state file, log file, final URL. **Do not close the X platform tab** — the closer protects it via `essential_tabs`.
