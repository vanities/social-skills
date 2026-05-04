# Instagram playbook

Reference for any skill operating on instagram.com. Skills should link here rather than duplicating these steps.

## URLs

- Login: <https://www.instagram.com/accounts/login/>
- Home / feed: <https://www.instagram.com/>
- Profile: <https://www.instagram.com/{username}/>

## State

One agent-browser state file per account at:

```
~/.config/agent-browser/instagram-<account>.json
```

Save after first manual sign-in:

```bash
agent-browser state save ~/.config/agent-browser/instagram-<account>.json
```

Load at the top of every subsequent run:

```bash
agent-browser state load ~/.config/agent-browser/instagram-<account>.json
```

## Posting a feed image

Precondition: page is `https://www.instagram.com/`, signed in, `agent-browser snapshot -i` taken.

1. Find the **Create** button (a `+` / compose icon, usually in the left sidebar; sometimes top nav). Click it via its `@ref`.
2. In the upload dialog, click **Select from computer**.
3. Upload the local image path. Some agent-browser builds expose `agent-browser upload <path>`; otherwise find the file `<input type=file>` `@ref` via snapshot and fill it.
4. Click **Next**. If a crop step appears, **Next** again. If a filter / edit step appears, **Next** again.
5. In the caption textarea, paste the caption verbatim (preserving line breaks and emoji).
6. Click **Share**.
7. Wait for the share dialog to close. Verify the post appears at the top of the user's profile grid.

If a "Save your login info?" or notifications dialog appears at any point, dismiss it (**Not now**) and continue.

## Anti-bot guidance

- Use the persistent agent-browser state — fresh sessions are flagged faster.
- Don't post more than 3–5 times per day from the same account.
- Captions over ~2,200 characters get truncated.
- Hashtags work — aim for 5–15 relevant ones.
- Don't follow / unfollow more than ~30 accounts/day.

## Common failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| "Please wait a few minutes" screen | Rate limit | Wait 30+ min, retry |
| Login wall on automated run | State expired | Re-run `/instagram-login <account>` |
| 2FA prompt mid-run | New device fingerprint | Re-do manual login |
| "Suspicious login" / IP block | Carrier-grade NAT or shared IP | Residential VPN or wait 24h |
| Create button missing from sidebar | UI redesign | Update this playbook + the skills |
