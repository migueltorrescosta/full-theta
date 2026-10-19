"""Fixture tests for tools/check_licences.py."""

import json
import shutil
import subprocess
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


VOICES = {
    "languages": {
        "en": {"computer": {"runtime": "a-medium", "prerender": "a-high"}, "npc": {"runtime": "b", "prerender": "b"}},
        "pt_PT": {"dev_only": True, "computer": {"runtime": "c", "prerender": "c"}, "npc": {"runtime": "c", "prerender": "c"}},
    }
}


def with_voices(root: Path, statuses: dict) -> None:
    (root / "content/voices.json").write_text(json.dumps(VOICES))
    manifest = root / "content/provenance.json"
    data = json.loads(manifest.read_text())
    for name, status in statuses.items():
        data["entries"].append(
            {"name": f"Voice {name}", "kind": "voice", "voice": name, "status": status,
             "source": "https://example.org/v", "licence": "MIT", "attribution": "x"}
        )
    manifest.write_text(json.dumps(data))


# FT: FT-AUD-014
def test_listed_voices_pass(tmp_path):
    root = fixture(tmp_path)
    with_voices(root, {"a-medium": "accept", "a-high": "accept", "b": "accept", "c": "dev-only"})
    assert check_licences.run(root) == []


# FT: FT-AUD-014
def test_unlisted_voice_fails(tmp_path):
    root = fixture(tmp_path)
    with_voices(root, {"a-medium": "accept", "a-high": "accept", "c": "dev-only"})
    assert check_licences.run(root) == ["b: voice (en npc) not listed in content/provenance.json"]


# FT: FT-AUD-014
def test_shipped_language_with_dev_only_voice_fails(tmp_path):
    root = fixture(tmp_path)
    with_voices(root, {"a-medium": "dev-only", "a-high": "accept", "b": "accept", "c": "dev-only"})
    assert check_licences.run(root) == ["a-medium: en ships, so its voice must have status accept"]


# FT: FT-AUD-014
def test_unknown_voice_status_fails(tmp_path):
    root = fixture(tmp_path)
    with_voices(root, {"a-medium": "accept", "a-high": "accept", "b": "accept", "c": "unclear"})
    assert check_licences.run(root) == ["c: voice status must be one of ('accept', 'dev-only')"]


# FT: FT-GEN-008
def test_speech_recognition_dependency_fails(tmp_path):
    root = fixture(tmp_path)
    (root / "tools").mkdir()
    (root / "tools/pyproject.toml").write_text('dependencies = ["gdtoolkit==4.5.0", "vosk==0.3.45"]\n')
    (root / "addons/whisper_stt").mkdir()
    (root / "addons/whisper_stt/plugin.gd").write_text("")
    errors = check_licences.run(root)
    assert "tools/pyproject.toml: speech recognition dependency 'vosk' (FT-GEN-008)" in errors
    assert "addons/whisper_stt: speech recognition addon (FT-GEN-008)" in errors


# FT: FT-GEN-008
def test_repository_has_no_speech_recognition():
    assert check_licences.check_no_speech_recognition(Path(__file__).resolve().parents[2]) == []


# FT: FT-AUD-002
def test_committed_audio_fails(tmp_path):
    root = fixture(tmp_path)
    (root / "content/voice/prerendered/en").mkdir(parents=True)
    (root / "content/voice/prerendered/en/npc.pcm").write_bytes(b"\0\0")
    (root / "assets/art/pack/ok.ogg").write_bytes(b"")
    git = ["git", "-C", str(root)]
    subprocess.run(git + ["init", "-q"], check=True)
    subprocess.run(git + ["add", "-A"], check=True)
    assert check_licences.run(root) == [
        "content/voice/prerendered/en/npc.pcm: audio must not be committed outside assets/ (FT-AUD-002)"
    ]
