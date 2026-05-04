from __future__ import annotations

from social_agents.agent import AgentRunner
from social_agents.platforms import get_platform


async def run_post(
    platform: str,
    account: str,
    media: str,
    caption: str,
) -> None:
    plat = get_platform(platform)
    goal = plat.post_goal(media=media, caption=caption)
    runner = AgentRunner(account=account)
    result = await runner.run(goal)
    print(result)
