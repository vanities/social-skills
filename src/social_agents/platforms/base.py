"""Platform adapter base class.

Each Platform encodes the *shape* of a social network: where to log in,
and how to phrase a goal so the agent can accomplish a verb on that network.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import ClassVar


class Platform(ABC):
    name: ClassVar[str]
    login_url: ClassVar[str]

    @abstractmethod
    def post_goal(self, *, media: str, caption: str) -> str:
        """Return a natural-language goal for posting `media` with `caption`."""

    def search_goal(self, query: str) -> str:
        raise NotImplementedError(f"{self.name}: search not implemented")

    def like_goal(self, target: str) -> str:
        raise NotImplementedError(f"{self.name}: like not implemented")

    def follow_goal(self, target: str) -> str:
        raise NotImplementedError(f"{self.name}: follow not implemented")

    def comment_goal(self, target: str, text: str) -> str:
        raise NotImplementedError(f"{self.name}: comment not implemented")
