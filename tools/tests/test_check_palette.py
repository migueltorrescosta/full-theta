# FT: FT-STN-006
"""Tests for tools/check_palette.py: the real palette passes, near-identical colours fail."""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import check_palette  # noqa: E402

FIXTURE = """
const ROLES: Dictionary = {
	"a": Color("#ff5a36"),
	"b": Color("#ff5c38"),
	"text": Color("#e6edf3"),
	"background": Color("#0b0f14"),
}
const GROUPS: Dictionary = {
	"g": ["a", "b"],
}
const CONTRAST: Array[Array] = [
	["text", "background"],
]
"""


def test_real_palette_passes():
    assert check_palette.check(check_palette.PALETTE.read_text(encoding="utf-8")) == []


def test_near_identical_colours_fail():
    errors = check_palette.check(FIXTURE)
    assert errors and all(e.startswith("g: a vs b under ") for e in errors)
    assert len(errors) == len(check_palette.VISIONS)


def test_low_contrast_fails():
    errors = check_palette.check(FIXTURE.replace("#e6edf3", "#1a1f26"))
    assert any(e.startswith("contrast: text on background under normal") for e in errors)


def test_unknown_role_fails():
    assert check_palette.check(FIXTURE.replace('["a", "b"]', '["a", "zz"]')) == ["unknown role 'zz'"]


def test_matrices_keep_white_and_grey():
    # Machado et al. 2009: every row sums to 1, so achromatic colours are unchanged.
    for name, m in check_palette.MATRICES.items():
        for row in m:
            assert sum(row) == pytest.approx(1.0, abs=1e-5), name
        for grey in (0.0, 0.5, 1.0):
            sim = check_palette.simulate((grey, grey, grey), name)
            assert sim == pytest.approx((grey,) * 3, abs=1e-4)


def test_protanopia_merges_red_and_green():
    red, green = (0.84, 0.15, 0.24), (0.25, 0.75, 0.25)
    normal = check_palette.de2000(check_palette.lab(red), check_palette.lab(green))
    seen = [check_palette.lab(check_palette.simulate(c, "protanopia")) for c in (red, green)]
    assert check_palette.de2000(*seen) < normal / 2


def test_ciede2000_reference_pairs():
    # Sharma, Wu and Dalal (2005), table 1, pairs 1 and 17.
    assert check_palette.de2000((50, 2.6772, -79.7751), (50, 0, -82.7485)) == pytest.approx(
        2.0425, abs=1e-4
    )
    assert check_palette.de2000((50, 2.5, 0), (73, 25, -18)) == pytest.approx(27.1492, abs=1e-4)


def test_contrast_extremes():
    assert check_palette.contrast((1, 1, 1), (0, 0, 0)) == pytest.approx(21.0)
    assert check_palette.contrast((0.5, 0.5, 0.5), (0.5, 0.5, 0.5)) == pytest.approx(1.0)
