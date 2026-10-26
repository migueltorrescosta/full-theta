"""Tests for the conversation checks of tools/check_dialogue.py on copies of the real data."""

import json
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import check_dialogue  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
MALFORMED = Path(__file__).parent / "fixtures/conversations/malformed.json"
CONV = "content/conversations"


def repo_copy(tmp_path: Path) -> Path:
    root = tmp_path / "repo"
    for sub in ("content/dialogue", "content/i18n", CONV, "content/economy/rep"):
        shutil.copytree(REPO / sub, root / sub)
    return root


def edit(root: Path, name: str, fn) -> None:
    path = root / CONV / name
    data = json.loads(path.read_text(encoding="utf-8"))
    fn(data)
    path.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")


# FT: FT-DAT-003
def test_shipped_conversations_pass():
    assert check_dialogue.run(REPO) == []


# FT: FT-DAT-003
def test_malformed_fixture_fails(tmp_path):
    root = repo_copy(tmp_path)
    shutil.copy(MALFORMED, root / CONV / "malformed.json")
    errors = check_dialogue.run(root)
    joined = "\n".join(errors)
    assert errors and all(e.startswith(f"{CONV}/malformed.json") for e in errors)
    assert "'start' is a required property" in joined
    assert "does not match" in joined  # the id pattern
    assert "'radio' is not one of" in joined
    assert "Additional properties are not allowed ('volume'" in joined
    assert "is not valid under any of the given schemas" in joined  # a two-key effect, a bad intent


# FT: FT-DAT-003
def test_invalid_json_fails(tmp_path):
    root = repo_copy(tmp_path)
    (root / CONV / "broken.json").write_text("{ not json", encoding="utf-8")
    assert check_dialogue.run(root)[0].startswith(f"{CONV}/broken.json: not valid JSON")


# FT: FT-DAT-003, FT-COM-007
def test_dangling_references_fail(tmp_path):
    root = repo_copy(tmp_path)

    def break_it(d):
        node = d["nodes"]["n0"]
        node["line"] = "npc.no_such_line"
        node["options"][0]["text"] = "comms.opt.no_such_text"
        node["options"][0]["next"] = "n9"
        node["options"][2]["effects"][1] = {"rep": "rep.no_such"}
        d["nodes"]["orphan"] = {"line": "npc.hail_trader", "options": []}

    edit(root, "trader_bluff.json", break_it)
    assert check_dialogue.run(root) == [
        f"{CONV}/trader_bluff.json: n0: unknown dialogue line npc.no_such_line",
        f"{CONV}/trader_bluff.json: n0.o1: unknown UI string comms.opt.no_such_text",
        f"{CONV}/trader_bluff.json: n0.o1: next names no node: n9",
        f"{CONV}/trader_bluff.json: n0.o3: unknown reputation distribution rep.no_such",
        f"{CONV}/trader_bluff.json: node orphan is unreachable",
    ]


# FT: FT-DAT-003
def test_id_and_start_must_match(tmp_path):
    root = repo_copy(tmp_path)
    edit(root, "escort_contract.json", lambda d: d.update(id="conv.other", start="nowhere"))
    errors = check_dialogue.run(root)
    assert f"{CONV}/escort_contract.json: id conv.other must be conv.escort_contract" in errors
    assert f"{CONV}/escort_contract.json: start names no node: nowhere" in errors
