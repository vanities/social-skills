"""Manual-login task: open Chrome with the per-account profile, wait for the user.

No agent, no LLM. The user logs in by hand (and handles any 2FA), then closes
the loop by pressing Enter. The persistent profile retains cookies + storage,
so subsequent agent runs against this account skip login.
"""

from __future__ import annotations

import sys

from social_agents.config import settings
from social_agents.platforms import get_platform


async def run_login(platform: str, account: str) -> None:
    plat = get_platform(platform)
    profile_dir = settings.profiles_dir / account
    profile_dir.mkdir(parents=True, exist_ok=True)

    # Lazy import so `--help` is fast and login doesn't pull browser-use.
    from playwright.async_api import async_playwright

    async with async_playwright() as p:
        context = await p.chromium.launch_persistent_context(
            str(profile_dir),
            channel="chrome",
            headless=False,
        )
        page = context.pages[0] if context.pages else await context.new_page()
        await page.goto(plat.login_url)

        print(
            f"\n[Chrome opened] Log in to {platform} as account label '{account}'.\n"
            f"Profile dir: {profile_dir}\n"
            f"When you're done (incl. any 2FA), press Enter here to close and persist the session."
        )
        # input() blocks the event loop intentionally; that's fine for a one-shot CLI.
        sys.stdin.readline()

        await context.close()
        print(f"[OK] Session saved at {profile_dir}")
