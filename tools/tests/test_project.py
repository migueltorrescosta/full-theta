"""Engine pin and renderer settings (T002, T003)."""

import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


# FT: FT-ARC-001
def test_tampered_checksum_fails(tmp_path: Path) -> None:
    lines = (ROOT / "tools/godot.sha512").read_text().splitlines()
    bad = ["0" * 128 + line[128:] for line in lines]
    (tmp_path / "bad.sha512").write_text("\n".join(bad) + "\n")
    env = dict(os.environ, GODOT_SHA512=str(tmp_path / "bad.sha512"))
    result = subprocess.run(
        [str(ROOT / "tools/get-godot.sh")], env=env, capture_output=True, text=True
    )
    assert result.returncode != 0
    assert "checksum mismatch" in result.stderr


# FT: FT-ARC-001
def test_pinned_version() -> None:
    assert (ROOT / "tools/godot-version").read_text().strip() == "4.7.2-stable"


# FT: FT-ARC-003
def test_compatibility_renderer() -> None:
    settings = (ROOT / "project.godot").read_text()
    assert 'renderer/rendering_method="gl_compatibility"' in settings
    assert 'renderer/rendering_method.mobile="gl_compatibility"' in settings
