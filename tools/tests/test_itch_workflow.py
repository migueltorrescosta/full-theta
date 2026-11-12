"""The itch.io upload workflow (.github/workflows/itch.yml): it runs only when the owner
publishes a release, keeps a read-only token, pins and checks butler, takes the key and
the game from repository settings (never from the repository), and pushes the three
desktop packages."""
# FT: FT-ARC-023

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
ITCH = (ROOT / ".github/workflows/itch.yml").read_text()


def test_runs_only_on_a_published_release_with_a_read_only_token() -> None:
    assert re.search(r"on:\n  release:\n    types: \[published\]\n", ITCH)
    assert "permissions:\n  contents: read\n" in ITCH
    assert "write" not in ITCH
    assert "actions/checkout" not in ITCH  # no repository code runs


def test_butler_is_pinned_and_checked() -> None:
    assert re.search(r"BUTLER_VERSION: \d+\.\d+\.\d+\n", ITCH)
    assert re.search(r"BUTLER_SHA256: [0-9a-f]{64}\n", ITCH)
    assert 'sha256sum -c -' in ITCH
    assert "LATEST" not in ITCH


def test_the_key_and_game_come_from_settings_and_are_optional() -> None:
    assert "${{ secrets.BUTLER_API_KEY }}" in ITCH
    assert "${{ vars.ITCH_GAME }}" in ITCH
    assert "if: ${{ vars.ITCH_GAME != '' }}" in ITCH
    # Nothing that looks like a key is committed.
    assert not re.search(r"BUTLER_API_KEY: [^$\s]", ITCH)


def test_pushes_the_three_desktop_channels() -> None:
    for channel in ("linux", "windows", "mac"):
        assert re.search(rf"push \S+ {channel}\n", ITCH)
    assert "--userversion \"$TAG\"" in ITCH
