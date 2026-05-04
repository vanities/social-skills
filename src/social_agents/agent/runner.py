"""Wraps browser-use to drive a real, attached Chrome browser.

Each account gets its own persistent profile dir, so cookies and login state
survive between runs. We use `channel='chrome'` so Playwright drives the
user's installed Chrome (not bundled Chromium) — that fingerprint matters
on platforms with bot detection.
"""

from __future__ import annotations

from pathlib import Path

from social_agents.config import settings


class AgentRunner:
    def __init__(self, account: str, model: str | None = None):
        self.account = account
        self.model = model or settings.anthropic_model
        self.profile_dir: Path = settings.profiles_dir / account
        self.profile_dir.mkdir(parents=True, exist_ok=True)

    async def run(self, goal: str) -> str:
        """Drive Chrome to accomplish `goal` and return the agent's final result."""
        # Imported lazily so `social-agents login` works without a fully-resolved
        # browser-use install (login is plain Playwright).
        from browser_use import Agent
        from browser_use.browser import BrowserProfile, BrowserSession
        from browser_use.llm import ChatAnthropic

        llm = ChatAnthropic(model=self.model)
        profile = BrowserProfile(
            user_data_dir=str(self.profile_dir),
            channel="chrome",
            headless=False,
        )
        session = BrowserSession(browser_profile=profile)
        agent = Agent(task=goal, llm=llm, browser_session=session)
        try:
            result = await agent.run()
            return str(result)
        finally:
            await session.close()
