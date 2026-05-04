"""Settings resolved from env with sensible defaults."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


def _path_from_env(name: str, default: Path) -> Path:
    raw = os.environ.get(name)
    return Path(raw).expanduser() if raw else default


@dataclass(frozen=True)
class Settings:
    profiles_dir: Path
    media_dir: Path
    anthropic_model: str

    @classmethod
    def from_env(cls) -> "Settings":
        home_root = Path.home() / ".social-agents"
        return cls(
            profiles_dir=_path_from_env(
                "SOCIAL_AGENTS_PROFILES_DIR", home_root / "profiles"
            ),
            media_dir=_path_from_env(
                "SOCIAL_AGENTS_MEDIA_DIR", home_root / "media"
            ),
            anthropic_model=os.environ.get(
                "SOCIAL_AGENTS_MODEL", "claude-sonnet-4-6"
            ),
        )


settings = Settings.from_env()
