# FT: FT-STN-006
"""Tests for tools/check_colourblind.py: letter and shape encodings, source scan, baselines."""

import sys
from pathlib import Path

import numpy as np
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import check_colourblind as ccb  # noqa: E402
import check_palette as cp  # noqa: E402
import l5  # noqa: E402

PALETTE_TEXT = cp.PALETTE.read_text(encoding="utf-8")


def test_real_encodings_and_sources_pass():
    assert ccb.check_encodings(PALETTE_TEXT) == []
    assert ccb.check_sources() == []


def test_duplicate_shape_or_letter_fails():
    same_shape = PALETTE_TEXT.replace('"F": "square"', '"F": "triangle"')
    assert any("allegiance shape" in e for e in ccb.check_encodings(same_shape))
    same_letter = PALETTE_TEXT.replace('"letter": "Y"', '"letter": "N"')
    assert any("alert letter" in e for e in ccb.check_encodings(same_letter))


def test_colour_only_script_fails(tmp_path):
    (tmp_path / "stations").mkdir()
    (tmp_path / "stations/bad.gd").write_text('var c = Palette.item_color(it)\n', encoding="utf-8")
    (tmp_path / "stations/good.gd").write_text(
        'var c = Palette.item_color(it)\nvar p = Palette.shape_points("circle", c, 1.0)\n',
        encoding="utf-8",
    )
    errors = ccb.check_sources(tmp_path)
    assert len(errors) == 1 and errors[0].startswith("stations/bad.gd")


@pytest.mark.parametrize("vision", list(cp.MATRICES))
def test_array_simulation_matches_scalar(vision):
    rgb = np.array([[[255, 90, 54], [86, 180, 233]]], dtype=np.uint8)
    got = ccb.simulate_array(rgb, vision)[0]
    for px, out in zip(rgb[0], got):
        want = cp.simulate(tuple(v / 255.0 for v in px), vision)
        assert max(abs(int(o) - round(w * 255)) for o, w in zip(out, want)) <= 1


def test_image_roles_are_found_and_distinct_ones_pass(tmp_path):
    roles, _, _, _ = cp.parse(PALETTE_TEXT)
    img = np.zeros((20, 40, 3), np.uint8)
    img[:, :20] = [round(v * 255) for v in roles["hostile"]]
    img[:, 20:] = [round(v * 255) for v in roles["friendly"]]
    assert set(ccb.roles_on_screen(img, roles)) >= {"hostile", "friendly"}
    path = tmp_path / "ok.png"
    l5.write_png(path, 40, 20, img.tobytes())
    assert ccb.failures(ccb.analyse(path)) == []


def test_confusable_group_pair_is_reported():
    result = {"name": "x", "groups": {"g": {"deuteranopia": (3.0, ("a", "b"))}}}
    assert ccb.failures(result) == ["x: g: a vs b under deuteranopia: dE00 3.0 < 10.0"]


def test_station_baselines_pass():
    for name in ("station_helm", "station_radar", "station_tactical"):
        result = ccb.analyse(ccb.BASELINES / f"{name}.png")
        assert "hostile" in result["roles"]
        assert ccb.failures(result) == []


def test_every_station_and_joint_view_has_a_baseline():
    names = [p.stem for p in ccb.BASELINES.glob("*.png")]
    ids = ccb.station_ids()
    assert {"helm", "drive", "fire_control", "captain", "viewer", "comms"} <= set(ids)
    assert ccb.check_coverage(names, ids) == []
    assert ccb.check_coverage(["l5_hd_drive"], ["drive", "helm"]) == ["no baseline shows helm"]
