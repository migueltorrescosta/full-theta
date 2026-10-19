# FT: FT-ARC-002
"""Seeded fixtures prove each L0 GDScript check fails on bad code (T005, FT-TST-001).

Each bad fixture breaks exactly one check, so the good one passing and each bad
one failing only its own check shows the three checks are independent and live.
"""

import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = "tools/tests/fixtures/gdtoolkit"
BIN = Path(sys.executable).parent


def godot() -> str:
    out = subprocess.run(
        [str(ROOT / "tools/get-godot.sh")], cwd=ROOT, check=True, capture_output=True, text=True
    )
    return out.stdout.strip()


CHECKS = {
    "gdlint": lambda f: [str(BIN / "gdlint"), f],
    "gdformat": lambda f: [str(BIN / "gdformat"), "--check", f],
    "check-only": lambda f: [godot(), "--headless", "--path", ".", "--check-only", "--script", f"res://{f}"],
}
FAILS = {"good": None, "bad_lint": "gdlint", "bad_format": "gdformat", "bad_check": "check-only"}


@pytest.mark.parametrize("check", CHECKS)
@pytest.mark.parametrize("fixture", FAILS)
def test_check_fails_only_its_seeded_fixture(check: str, fixture: str) -> None:
    cmd = CHECKS[check](f"{FIXTURES}/{fixture}.gd")
    result = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    expect_fail = FAILS[fixture] == check
    assert (result.returncode != 0) == expect_fail, result.stdout + result.stderr
