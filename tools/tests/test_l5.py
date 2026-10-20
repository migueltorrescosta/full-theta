# FT: FT-TST-003
"""Fixture tests for tools/l5.py: PNG decoding, tolerant diffs and the environment check.

None of these needs Xvfb or Godot; they compare small generated images.
"""

import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import l5  # noqa: E402

ENV = {
    "renderer": "llvmpipe (LLVM 21.1.8, 256 bits)",
    "gl_version": "4.5 (Core Profile) Mesa 26.0.8-1ubuntu0.3",
    "godot": "4.7.2-stable (official)",
}
W, H = 200, 100  # 20000 pixels: MAX_FRACTION allows 2


def image(colour: tuple[int, int, int] = (10, 20, 30)) -> bytearray:
    return bytearray(bytes(colour) * (W * H))


def setup(tmp_path: Path, base: bytes, shot: bytes, env: dict | None = None) -> tuple[Path, Path]:
    baselines, out = tmp_path / "baselines", tmp_path / "out"
    baselines.mkdir()
    out.mkdir()
    l5.write_png(baselines / "a.png", W, H, bytes(base))
    l5.write_png(out / "a.png", W, H, bytes(shot))
    (baselines / "env.json").write_text(json.dumps(ENV))
    (out / "env.json").write_text(json.dumps(env or ENV))
    return baselines, out


def test_png_round_trip(tmp_path):
    rgb = bytes(i % 251 for i in range(W * H * 3))
    l5.write_png(tmp_path / "x.png", W, H, rgb)
    assert l5.read_png(tmp_path / "x.png") == (W, H, rgb)


def test_reads_a_godot_baseline():
    w, h, rgb = l5.read_png(l5.BASELINES / "s2_scene.png")
    assert (w, h, len(rgb)) == (640, 360, 640 * 360 * 3)
    assert not l5.blank(rgb)


def test_identical_shot_passes(tmp_path):
    errors, stats = l5.compare(*setup(tmp_path, image(), image()), ["a"])
    assert errors == []
    assert stats["a"] == {"differing": 0, "fraction": 0.0, "max_delta": 0}


def test_difference_within_threshold_passes(tmp_path):
    shot = image()
    for i in range(0, len(shot), 3):
        shot[i] += l5.THRESHOLD
    errors, stats = l5.compare(*setup(tmp_path, image(), shot), ["a"])
    assert errors == []
    assert stats["a"]["max_delta"] == l5.THRESHOLD


def test_few_differing_pixels_pass(tmp_path):
    shot = image()
    allowed = int(W * H * l5.MAX_FRACTION)
    assert allowed > 0
    for p in range(allowed):
        shot[3 * p] = 255
    errors, _ = l5.compare(*setup(tmp_path, image(), shot), ["a"])
    assert errors == []


def test_too_many_differing_pixels_fail(tmp_path):
    shot = image()
    over = int(W * H * l5.MAX_FRACTION) + 1
    for p in range(over):
        shot[3 * p] = 255
    baselines, out = setup(tmp_path, image(), shot)
    errors, stats = l5.compare(baselines, out, ["a"])
    assert len(errors) == 1 and errors[0].startswith(f"a: {over} pixels differ")
    assert stats["a"]["differing"] == over
    assert (out / "a.diff.png").exists()


# FT: FT-TST-020
def test_environment_change_fails_before_diff(tmp_path):
    env = dict(ENV, gl_version="4.5 (Core Profile) Mesa 26.1.0")
    shot = image((200, 0, 0))
    errors, stats = l5.compare(*setup(tmp_path, image(), shot, env), ["a"])
    assert errors == [
        "baseline environment changed: gl_version: "
        "'4.5 (Core Profile) Mesa 26.0.8-1ubuntu0.3' -> '4.5 (Core Profile) Mesa 26.1.0'"
        + l5.ENV_HINT
    ]
    assert stats == {}


# FT: FT-TST-020
def test_llvmpipe_change_fails(tmp_path):
    env = dict(ENV, renderer="llvmpipe (LLVM 22.1.0, 256 bits)")
    errors, _ = l5.compare(*setup(tmp_path, image(), image(), env), ["a"])
    assert len(errors) == 1 and errors[0].startswith("baseline environment changed: renderer:")


def test_missing_baseline_fails(tmp_path):
    errors, _ = l5.compare(*setup(tmp_path, image(), image()), ["a", "b"])
    assert errors == ["b: no baseline; run with --update-baselines"]


def test_size_change_fails(tmp_path):
    baselines, out = setup(tmp_path, image(), image())
    l5.write_png(out / "a.png", H, W, bytes(image()))
    errors, _ = l5.compare(baselines, out, ["a"])
    assert errors == [f"a: size {H}x{W}, baseline {W}x{H}"]


def test_blank_detection():
    assert l5.blank(bytes(image()))
    shot = image()
    shot[-1] = 0
    assert not l5.blank(bytes(shot))


def test_shot_size_defaults_to_the_manifest():
    manifest = {"size": [640, 360]}
    assert l5.shot_size(manifest, {"name": "a"}) == [640, 360]
    assert l5.shot_size(manifest, {"name": "b", "size": [1280, 720]}) == [1280, 720]


def test_capture_checks_each_shot_at_its_own_size(tmp_path, monkeypatch):
    shots = tmp_path / "shots.json"
    shots.write_text(
        json.dumps(
            {
                "size": [W, H],
                "shots": [{"name": "a", "scene": "x"}, {"name": "b", "scene": "x", "size": [300, 50]}],
            }
        )
    )
    out = tmp_path / "out"
    calls = []

    def fake_run(cmd, **kwargs):
        if len(calls) == 0:
            calls.append(cmd)
            return subprocess.CompletedProcess(cmd, 0, "godot\n", "")
        calls.append(cmd)
        # The render: a at the manifest size, b at the wrong size.
        rgb = bytes(image())
        rgb = rgb[:-3] + b"\x00\x00\x00"
        l5.write_png(out / "a.png", W, H, rgb)
        l5.write_png(out / "b.png", W, H, rgb)
        (out / "env.json").write_text(json.dumps(ENV))
        return subprocess.CompletedProcess(cmd, 0, "", "")

    monkeypatch.setattr(l5.shutil, "which", lambda _: "/usr/bin/xvfb-run")
    monkeypatch.setattr(l5.subprocess, "run", fake_run)
    errors = l5.capture(shots, out)
    assert errors == [f"b: rendered {W}x{H}, expected 300x50"]
    # The X screen and window fit the largest shot on each axis.
    render = [str(c) for c in calls[1]]
    assert f"--server-args=-screen 0 300x{H}x24" in render
    assert render[render.index("--resolution") + 1] == f"300x{H}"
