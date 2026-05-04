from __future__ import annotations

import asyncio
from pathlib import Path

import typer

from social_agents.platforms import known_platforms
from social_agents.tasks import run_login, run_post

app = typer.Typer(
    no_args_is_help=True,
    add_completion=False,
    help="Pure-agent social media automation (no platform APIs).",
)


@app.command()
def login(
    platform: str = typer.Option(..., "--platform", "-p", help=f"One of: {', '.join(known_platforms())}"),
    account: str = typer.Option(..., "--account", "-a", help="Account label (used as profile-dir name)"),
):
    """Open a real Chrome window for you to log in. Session persists per account."""
    asyncio.run(run_login(platform=platform, account=account))


@app.command()
def post(
    platform: str = typer.Option(..., "--platform", "-p"),
    account: str = typer.Option(..., "--account", "-a"),
    media: Path = typer.Option(..., "--media", "-m", exists=True, dir_okay=False, resolve_path=True),
    caption: str = typer.Option("", "--caption", "-c"),
):
    """Have the agent post a piece of media with a caption."""
    asyncio.run(
        run_post(
            platform=platform,
            account=account,
            media=str(media),
            caption=caption,
        )
    )


@app.command()
def platforms():
    """List supported platforms."""
    for name in known_platforms():
        typer.echo(name)


def main() -> None:
    app()


if __name__ == "__main__":
    main()
