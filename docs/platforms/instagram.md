# Instagram playbook

Reference for any skill operating on instagram.com. Skills should link here rather than duplicating these steps.

## URLs

- Login: <https://www.instagram.com/accounts/login/>
- Home / feed: <https://www.instagram.com/>
- Profile: <https://www.instagram.com/{username}/>

## State

State files at `~/.config/agent-browser/instagram-<account>.json` are a backup. The default mode is the persistent shared headed Chrome — see `docs/architecture.md`. State files come into play for cron / cold-start runs.

## Posting a feed image

Precondition: an Instagram tab is open in the shared browser, signed in, snapshot taken.

1. Click the **Create** button (`+` / compose icon, usually in the left sidebar; sometimes top nav).
2. In the upload dialog, click **Select from computer**.
3. Upload the local image path. Use `agent-browser upload <ref> "<path>"` if available; otherwise find the `<input type=file>` `@ref` via snapshot and fill it.
4. Click **Next**. If a crop step appears, **Next** again. If a filter / edit step appears, **Next** again.
5. **Type** the caption (don't `fill` it — see "Human-like timing" below).
6. Click **Share**.
7. Wait for the share dialog to close. Verify the post appears at the top of the user's profile grid.

If a "Save your login info?" or notifications dialog appears at any point, dismiss it (**Not now**) and continue.

## Human-like timing (jitter)

Bots are detectable by their inhuman precision and speed. Apply these defaults on every IG interaction:

| When | Wait | How |
|---|---|---|
| After a navigation / tab switch | 600–1600 ms | `agent-browser wait $(bash scripts/jitter.sh 600 1600)` |
| Between fills inside a form | 300–1000 ms | `agent-browser wait $(bash scripts/jitter.sh 300 1000)` |
| Before clicking the **Log In** or **Share** submit button | 1200–3000 ms | `agent-browser wait $(bash scripts/jitter.sh 1200 3000)` |
| After clicking through crop / filter / edit screens | 600–1400 ms | per-click |

Prefer `agent-browser type @<ref> "<text>"` (real keystrokes, char by char) over `agent-browser fill @<ref> "<text>"` (instant batch) for any field a human would type into — username, password, caption. `fill` is fine for hidden file inputs and the `<input type=file>` for uploads (where there's no human typing model).

## Anti-bot guidance

- Run **headed Chrome** (`--headed`). HeadlessChrome is detected and flagged.
- Use the persistent shared browser — fresh sessions get flagged faster.
- Don't post more than 3–5 times per day from the same account.
- Don't follow / unfollow more than ~30 accounts/day.
- Captions over ~2,200 characters get truncated.
- Hashtags work — aim for 5–15 relevant ones.
- If you log in from a new device fingerprint, expect a security email and possibly a forced re-auth.

## Common failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| "Please wait a few minutes" screen | Rate limit | Wait 30+ min, retry |
| Login wall on automated run | State expired or new fingerprint | Re-run `/instagram-login <account>` |
| 2FA prompt mid-run | New device fingerprint | Re-do manual login |
| "Suspicious login" email | Detected as HeadlessChrome / new device | Re-login headed; ignore the email if it's you |
| Create button missing from sidebar | UI redesign | Update this playbook + the skills |
