"""Tests for tools/check_dialogue.py on copies of the real dialogue data."""

import json
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import check_dialogue  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
MALFORMED = Path(__file__).parent / "fixtures/dialogue/malformed.json"


def repo_copy(tmp_path: Path) -> Path:
    root = tmp_path / "repo"
    for sub in ("content/dialogue", "content/i18n"):
        shutil.copytree(REPO / sub, root / sub)
    return root


def edit(root: Path, name: str, fn) -> None:
    path = root / "content/dialogue" / name
    data = json.loads(path.read_text(encoding="utf-8"))
    fn(data)
    path.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")


# FT: FT-DAT-003, FT-DAT-004, FT-DAT-011
def test_shipped_dialogue_passes():
    assert check_dialogue.run(REPO) == []


# FT: FT-DAT-003
def test_malformed_fixture_fails(tmp_path):
    root = repo_copy(tmp_path)
    shutil.copy(MALFORMED, root / "content/dialogue/malformed.json")
    errors = check_dialogue.run(root)
    joined = "\n".join(errors)
    assert errors and all(e.startswith("content/dialogue/malformed.json") for e in errors)
    assert "'pt_PT' is a required property" in joined
    assert "does not match" in joined  # the id pattern
    assert "'radio' is not one of" in joined
    assert "Additional properties are not allowed ('volume'" in joined


# FT: FT-DAT-003
def test_invalid_json_fails(tmp_path):
    root = repo_copy(tmp_path)
    (root / "content/dialogue/broken.json").write_text("{ not json", encoding="utf-8")
    assert check_dialogue.run(root)[0].startswith("content/dialogue/broken.json: not valid JSON")


# FT: FT-DAT-004
def test_duplicate_line_id_fails(tmp_path):
    root = repo_copy(tmp_path)
    edit(root, "npc.json", lambda d: d["lines"].append(dict(d["lines"][0])))
    assert check_dialogue.run(root) == [
        "content/dialogue/npc.json: duplicate line id npc.hail_trader (also in content/dialogue/npc.json)"
    ]


# FT: FT-DAT-004
def test_id_outside_its_file_fails(tmp_path):
    root = repo_copy(tmp_path)
    edit(root, "npc.json", lambda d: d["lines"][-1].update(id="computer.ambient_traffic"))
    assert check_dialogue.run(root) == [
        "content/dialogue/npc.json: line id computer.ambient_traffic must start with 'npc.'"
    ]


# FT: FT-DAT-004
def test_slot_mismatch_fails(tmp_path):
    root = repo_copy(tmp_path)

    def drop_slot(d):
        d["lines"][3]["text"]["it"] = "Contatto, rilevamento {bearing}, distanza {range} chilometri."

    edit(root, "computer.json", drop_slot)
    errors = check_dialogue.run(root)
    assert len(errors) == 1 and "computer.contact: it: slots" in errors[0]


# FT: FT-DAT-011
def test_missing_translation_fails(tmp_path):
    root = repo_copy(tmp_path)
    edit(root, "computer.json", lambda d: d["lines"][0]["text"].update(it="  "))
    assert any("computer.hull_critical: it: blank text" in e for e in check_dialogue.run(root))


# FT: FT-DAT-011
def test_missing_ui_string_fails(tmp_path):
    root = repo_copy(tmp_path)
    path = root / "content/i18n/strings.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    del data["strings"]["subtitle.computer"]["pt_PT"]
    path.write_text(json.dumps(data), encoding="utf-8")
    assert check_dialogue.run(root) == ["content/i18n/strings.json: subtitle.computer: missing pt_PT"]


# FT: FT-DAT-011
def test_number_table_needs_every_language(tmp_path):
    root = repo_copy(tmp_path)
    edit(root, "numbers.json", lambda d: d["languages"].pop("it"))
    assert check_dialogue.run(root) == [
        "content/dialogue/numbers.json: languages: 'it' is a required property"
    ]
