# FT: FT-TST-001
"""L0's one-process script check (tools/check_scripts.gd) fails a script that does not compile.

It replaces `godot --check-only` per script, so it must fail the same seeded fixture.
"""

import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = "res://tools/tests/fixtures/gdtoolkit"


@pytest.mark.parametrize("fixture", ["good", "bad_lint", "bad_format", "bad_check"])
def test_check_scripts_fails_only_the_check_fixture(fixture: str, tmp_path: Path) -> None:
    godot = subprocess.run(
        [str(ROOT / "tools/get-godot.sh")], cwd=ROOT, check=True, capture_output=True, text=True
    ).stdout.strip()
    listing = tmp_path / "scripts.txt"
    listing.write_text(f"{FIXTURES}/good.gd\n{FIXTURES}/{fixture}.gd\n")
    cmd = [godot, "--headless", "--path", ".", "-s", "res://tools/check_scripts.gd", "--", str(listing)]
    result = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    assert (result.returncode != 0) == (fixture == "bad_check"), result.stdout + result.stderr
    if fixture == "bad_check":
        assert f"failed: {FIXTURES}/bad_check.gd" in result.stderr
