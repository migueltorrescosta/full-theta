"""Fixture tests for tools/check_licences.py."""

import json
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import check_licences  # noqa: E402

BASE = Path(__file__).parent / "fixtures/licences/base"


def fixture(tmp_path: Path) -> Path:
    root = tmp_path / "repo"
    shutil.copytree(BASE, root)
    return root


def edit_entry(root: Path, index: int, **fields) -> None:
    manifest = root / "content/provenance.json"
    data = json.loads(manifest.read_text())
    data["entries"][index].update(fields)
    manifest.write_text(json.dumps(data))


# FT: FT-LIC-005
def test_listed_files_pass(tmp_path):
    assert check_licences.run(fixture(tmp_path)) == []


# FT: FT-LIC-005
def test_unlisted_addon_file_fails(tmp_path):
    root = fixture(tmp_path)
    (root / "addons/other").mkdir()
    (root / "addons/other/plugin.gd").write_text("")
    assert check_licences.run(root) == [
        "addons/other/plugin.gd: not listed in content/provenance.json"
    ]


# FT: FT-LIC-005
def test_unlisted_asset_fails(tmp_path):
    root = fixture(tmp_path)
    (root / "assets/art/loose.png").write_text("")
    assert check_licences.run(root) == ["assets/art/loose.png: not listed in content/provenance.json"]


# FT: FT-LIC-005
def test_entry_without_attribution_fails(tmp_path):
    root = fixture(tmp_path)
    edit_entry(root, 0, attribution="")
    assert check_licences.run(root) == ["Tool: missing attribution"]


# FT: FT-LIC-006
def test_non_cc0_art_fails(tmp_path):
    root = fixture(tmp_path)
    edit_entry(root, 1, licence="CC-BY-4.0")
    assert check_licences.run(root) == ["Art pack: art must be CC0-1.0, not CC-BY-4.0"]


# FT: FT-LIC-006
def test_non_cc0_sound_fails(tmp_path):
    root = fixture(tmp_path)
    edit_entry(root, 1, kind="sound", licence="CC-BY-SA-4.0")
    assert check_licences.run(root) == ["Art pack: sound must be CC0-1.0, not CC-BY-SA-4.0"]
