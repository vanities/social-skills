from social_agents.platforms.base import Platform
from social_agents.platforms.instagram import Instagram

_REGISTRY: dict[str, type[Platform]] = {
    Instagram.name: Instagram,
    # TikTok, LinkedIn, Twitter to be added.
}


def get_platform(name: str) -> Platform:
    if name not in _REGISTRY:
        known = ", ".join(sorted(_REGISTRY))
        raise ValueError(f"Unknown platform '{name}'. Known: {known}")
    return _REGISTRY[name]()


def known_platforms() -> list[str]:
    return sorted(_REGISTRY)


__all__ = ["Platform", "get_platform", "known_platforms"]
