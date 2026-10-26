"""The text-only binding slot of dialogue lines (FT-MIS-039): checked, never voiced."""

import copy
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tts"))
import check_dialogue  # noqa: E402
import prerender  # noqa: E402
from test_check_dialogue import edit, repo_copy  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
LANGS = ("en", "pt_PT", "it")
LINE = {
    "id": "shakedown.helm.face",
    "role": "computer",
    "priority": 1,
    "max_age_ms": 15000,
    "slots": {"binding": {"kind": "binding", "intent": "face"}},
    "text": {
        "en": "Face the drone. {binding}",
        "pt_PT": "Vira-te para o drone. {binding}",
        "it": "Punta verso il drone. {binding}",
    },
}


def shakedown_lines() -> list[dict]:
    data = json.loads((REPO / "content/dialogue/shakedown.json").read_text(encoding="utf-8"))
    return data["lines"]


# FT: FT-DAT-003, FT-MIS-039
def test_shipped_binding_lines_pass_and_name_real_intents(tmp_path):
    root = repo_copy(tmp_path)
    (root / "input").mkdir()
    (root / "input/intent_table.gd").write_text(
        (REPO / "input/intent_table.gd").read_text(encoding="utf-8"), encoding="utf-8"
    )
    assert check_dialogue.run(root) == []
    bound = [line for line in shakedown_lines() if "slots" in line]
    assert len(bound) > 100


# FT: FT-DAT-003, FT-MIS-039
def test_a_binding_slot_must_name_an_intent(tmp_path):
    root = repo_copy(tmp_path)
    (root / "input").mkdir()
    (root / "input/intent_table.gd").write_text(
        (REPO / "input/intent_table.gd").read_text(encoding="utf-8"), encoding="utf-8"
    )

    def bad(data):
        data["lines"][0]["slots"]["binding"]["intent"] = "no_such_intent"

    edit(root, "shakedown.json", bad)
    errors = check_dialogue.run(root)
    assert len(errors) == 1 and "names no IntentTable intent: no_such_intent" in errors[0]

    def missing(data):
        del data["lines"][0]["slots"]["binding"]["intent"]

    edit(root, "shakedown.json", missing)
    assert any("names no IntentTable intent: None" in e for e in check_dialogue.run(root))


# FT: FT-DAT-003, FT-AUD-010
def test_a_binding_slot_cannot_share_a_line_with_a_voiced_slot(tmp_path):
    root = repo_copy(tmp_path)
    (root / "input").mkdir()
    (root / "input/intent_table.gd").write_text(
        (REPO / "input/intent_table.gd").read_text(encoding="utf-8"), encoding="utf-8"
    )

    def mixed(data):
        line = data["lines"][0]
        line["slots"]["n"] = "number"
        for lang in LANGS:
            line["text"][lang] += " {n}"

    edit(root, "shakedown.json", mixed)
    errors = check_dialogue.run(root)
    assert len(errors) == 1 and "can't share a line with a voiced slot" in errors[0]


# FT: FT-AUD-010, FT-DAT-005
def test_the_prerender_never_voices_a_binding_slot():
    voices = json.loads((REPO / "content/voices.json").read_text(encoding="utf-8"))
    numbers = {"languages": {lang: {"fragments": {}} for lang in LANGS}}
    for lang in LANGS:
        planned = prerender.plan([copy.deepcopy(LINE)], numbers, voices, lang)["computer"]
        # One whole clip of the text without the slot: no segments, no placeholder.
        assert [key for key, _, _ in planned] == ["line:shakedown.helm.face"]
        text = planned[0][2]
        assert "{" not in text and "binding" not in text
        assert text == LINE["text"][lang].replace(" {binding}", "")


# FT: FT-AUD-010, FT-DAT-005
def test_every_shipped_shakedown_line_is_one_clip_without_slot_text():
    voices = json.loads((REPO / "content/voices.json").read_text(encoding="utf-8"))
    numbers = {"languages": {lang: {"fragments": {}} for lang in LANGS}}
    lines = shakedown_lines()
    for lang in LANGS:
        planned = prerender.plan(lines, numbers, voices, lang)["computer"]
        assert len(planned) == len(lines)
        assert all(key.startswith("line:shakedown.") for key, _, _ in planned)
        assert not any("{" in text for _, _, text in planned)


# FT: FT-AUD-010
def test_strip_bindings_keeps_a_voiced_slot_line_apart():
    mixed = {"slots": {"n": "number", "binding": {"kind": "binding", "intent": "face"}}}
    assert prerender._voiced_slots(mixed) == ["n"]
    assert prerender._voiced_slots(LINE) == []
