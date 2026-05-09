# LinkedIn playbook

Reference for any skill operating on linkedin.com.

## URLs

- Login:    <https://www.linkedin.com/login>
- Feed:     <https://www.linkedin.com/feed/>
- Profile:  <https://www.linkedin.com/in/{slug}/>
- Company admin (by id): <https://www.linkedin.com/company/{company_id}/admin/>

## State

- Backup state file: `~/.config/agent-browser/linkedin-default.json` (single account; no per-label split for LinkedIn since `.env` uses unsplit `LINKEDIN_USERNAME` / `LINKEDIN_PASSWORD`).
- Default mode is the persistent shared headed Chrome — see `docs/architecture.md`.

## Login

LinkedIn is gentler about automation than IG, but a new device fingerprint will trigger an email/SMS verification PIN on first sign-in.

1. Open `https://www.linkedin.com/login` in the LinkedIn tab.
2. Find form refs via `agent-browser snapshot -i`:
   - Email/phone textbox (label `Email or phone`)
   - Password textbox (label `Password`)
   - Sign in button (label `Sign in`)
3. `type` (real keystrokes) for both fields, jitter between, longer jitter before clicking Sign in. See `instagram.md` § Human-like timing for the same ranges.
4. After clicking Sign in, watch for `linkedin.com/checkpoint/challenge/...` — that's the verification PIN page. If it appears, **stop and pause for the user** to provide the PIN; type it into the spinbutton; click Submit pin.
5. Verify final URL is `linkedin.com/feed/`. Save state.

## Posting (personal)

From `/feed/`, find the **Start a post** button → opens a modal with a text editor, Add media, audience switcher, and Post button.

## Posting (company page)

Set `org.linkedin_company_id` in `config/brand.json` to the numeric id of your company page. To find it: visit `linkedin.com/company/<your-page-slug>/admin/` while signed in — LinkedIn redirects to the numeric form `linkedin.com/company/<id>/admin/`, that's your id.

1. Navigate to `https://www.linkedin.com/company/<id>/admin/`. The dashboard shows the company name as a level-1 heading.
2. Click the sidebar **+ Create** button → menu opens with: Start a post, Create an event, Share that you're hiring, Publish an article, Add a product, Create an Ad, Add services, Create a showcase page.
3. Click **Start a post** → compose modal opens with the audience switcher reading **"<Company Name> … Post to Anyone"** (this is how you confirm you're posting AS the page, not as your personal profile).
4. Type caption with real keystrokes + jitter. Click **Add media** to attach a screenshot. Click **Post** when ready (button is disabled until there's content).

⚠️ The company link in the left sidebar of `/feed/` is wrapped — the bare `agent-browser click @<ref>` may not navigate. Reliable path: `agent-browser eval "..."` to read the `href` of an `a[href*="/company/"]` element, then `agent-browser open <that-url>`. Or just go straight to the admin URL via the id from `brand.json`.

## Human-like timing

Same as IG (`docs/platforms/instagram.md` § Human-like timing). LinkedIn detection is lighter, so jitter ranges can be slightly shorter if needed, but the same defaults work fine.

## Anti-bot guidance

- Real keystrokes (`type`, not `fill`) for email + password + caption text.
- Jitter between every action.
- Persistent headed Chrome with `--disable-blink-features=AutomationControlled` (set by `scripts/launch_browser.sh`).
- Don't post more than 3–5 times per day from a fresh account.
- Connection requests / follow loops should rate-limit ≤ ~30 per day.

## Common failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| `/checkpoint/challenge/` after Sign in | New device fingerprint | Pause, enter PIN from email/SMS, submit |
| `/uas/login-submit` 429 | Brute force throttle | Wait 1–2 hours |
| Composer modal doesn't open from sidebar | Element wrapper indirection | Click `+ Create` first, then `Start a post` from the menu |
| Post AS personal instead of company | Forgot to click into `/company/<id>/admin/` first | Navigate to admin URL before opening composer |
