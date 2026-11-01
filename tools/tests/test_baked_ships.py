# FT: FT-AUD-020
"""Ships are baked at build time (D308): nothing the game ships names the ship builder."""

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BUILD_ONLY = ("tools/", "tests/", "addons/", "docs/", "spikes/")


def test_the_game_never_builds_a_ship():
    tracked = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "*.gd"],
        cwd=ROOT, capture_output=True, text=True, check=True,
    ).stdout.split()
    runtime = [f for f in tracked if not f.startswith(BUILD_ONLY)]
    assert runtime, "no scripts found"
    offenders = [f for f in runtime if "ShipBuilder" in (ROOT / f).read_text()]
    assert offenders == []


def test_the_export_leaves_the_builder_out():
    presets = (ROOT / "export_presets.cfg").read_text()
    assert presets.count('exclude_filter="tests/*, tools/*') >= 1
    assert (ROOT / "tools/ship_builder.gd").exists()
    assert not (ROOT / "presentation/ship_builder.gd").exists()
