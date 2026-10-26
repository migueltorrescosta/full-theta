"""Tests for tools/tts/prerender.py with a fake synthesiser (no Piper)."""

import json
import re
import shutil
import sys
from pathlib import Path

import numpy as np
import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/tts"))
import prerender  # noqa: E402

RATE = 22050
SILENCE = int(0.05 * RATE)


class Spy:
    """Fake synth: silence, a tone whose length and pitch depend on the text, silence."""

    def __init__(self):
        self.calls: list[tuple[str, str, dict]] = []

    def __call__(self, voice: str, text: str, settings: dict) -> tuple[np.ndarray, int]:
        self.calls.append((voice, text, dict(settings)))
        n = int((0.1 + 0.01 * len(text)) * RATE)
        tone = 0.5 * np.sin(2 * np.pi * (200 + 10 * len(text)) * np.arange(n) / RATE)
        pcm = np.concatenate([np.zeros(SILENCE), tone, np.zeros(SILENCE)])
        return (pcm * 32767).astype(np.int16), RATE


def content_root(tmp_path: Path) -> Path:
    """A repo holding only the prerender's inputs: dialogue JSON and voices.json (FT-DAT-005)."""
    root = tmp_path / "repo"
    shutil.copytree(ROOT / "content/dialogue", root / "content/dialogue")
    shutil.copy(ROOT / "content/voices.json", root / "content/voices.json")
    return root


def host(out: Path) -> Path:
    return out.parent / "prerendered_host"


def run(tmp_path: Path, langs=("en", "pt_PT", "it")) -> tuple[Path, Path, Spy, dict]:
    root = content_root(tmp_path)
    out = tmp_path / "out"
    spy = Spy()
    return root, out, spy, prerender.prerender(root, out, list(langs), synth=spy)


def expected_keys(root: Path, lang: str) -> dict[str, set[str]]:
    """Keys derived straight from the dialogue JSON and numbers.json (audio/README.md)."""
    keys: dict[str, set[str]] = {"computer": set(), "npc": set()}
    for f in (root / "content/dialogue").glob("*.json"):
        if f.name.endswith(".schema.json") or f.name == "numbers.json":
            continue
        for line in json.loads(f.read_text())["lines"]:
            text = line["text"][lang]
            # A binding slot is text-only (FT-MIS-039): a line with only those is one whole clip.
            voiced = [n for n, spec in line.get("slots", {}).items() if not (isinstance(spec, dict) and spec.get("kind") == "binding")]
            if not voiced:
                keys[line["role"]].add(f"line:{line['id']}")
                continue
            for k, piece in enumerate(re.split(r"\{[a-z][a-z0-9_]*\}", text)):
                if re.search(r"[A-Za-zÀ-ÿ]", piece):
                    keys[line["role"]].add(f"seg:{line['id']}:{k}")
    numbers = json.loads((root / "content/dialogue/numbers.json").read_text())
    for role in keys:
        keys[role] |= {f"num:{k}" for k in numbers["languages"][lang]["fragments"]}
    return keys


# FT: FT-AUD-002, FT-DAT-005
def test_keys_are_exactly_those_of_the_dialogue_json(tmp_path):
    root, out, _, indexes = run(tmp_path)
    for lang in ("en", "pt_PT", "it"):
        for role, keys in expected_keys(root, lang).items():
            assert set(indexes[(lang, role)]["clips"]) == {k for k in keys if not k.startswith("line:")}
            on_disk = json.loads((host(out) / lang / f"{role}.json").read_text())
            assert on_disk == indexes[(lang, role)]
        lines = {k[5:] + ".ogg" for keys in expected_keys(root, lang).values() for k in keys if k.startswith("line:")}
        assert {f.name for f in (out / lang).glob("*.ogg")} == lines


# FT: FT-DAT-005
def test_new_lines_file_is_read_and_schemas_skipped(tmp_path):
    root = content_root(tmp_path)
    extra = {
        "lines": [
            {
                "id": "npc.extra", "role": "npc", "priority": 2, "max_age_ms": 1000, "coalesce": "x",
                "resume": False, "slots": {"n": "number"},
                "text": {"en": "{n}, then {n} again", "pt_PT": "Olá {n}", "it": "Ciao {n}"},
            }
        ]
    }
    (root / "content/dialogue/extra.json").write_text(json.dumps(extra))
    indexes = prerender.prerender(root, tmp_path / "out", ["en"], synth=Spy())
    clips = indexes[("en", "npc")]["clips"]
    # Pieces: "", ", then ", " again"; the empty piece 0 is counted but not rendered.
    assert {k for k in clips if k.startswith("seg:npc.extra:")} == {"seg:npc.extra:1", "seg:npc.extra:2"}


# FT: FT-AUD-002
def test_segment_indices_follow_the_split_rule(tmp_path):
    _, _, spy, indexes = run(tmp_path, ["en"])
    computer = indexes[("en", "computer")]["clips"]
    # "Contact {callsign}, bearing {bearing}, range {range} kilometres."
    assert sorted(k for k in computer if k.startswith("seg:computer.contact:")) == [
        f"seg:computer.contact:{k}" for k in range(4)
    ]
    # "{count} enemy ships remaining.": piece 0 is empty.
    assert [k for k in computer if k.startswith("seg:computer.enemies_remaining:")] == [
        "seg:computer.enemies_remaining:1"
    ]
    texts = {text for _, text, _ in spy.calls}
    assert {"Contact", ", bearing", ", range", "kilometres.", "enemy ships remaining."} <= texts


# FT: FT-AUD-001, FT-AUD-002
def test_voices_and_role_settings(tmp_path):
    root, _, spy, indexes = run(tmp_path, ["en"])
    voices = json.loads((root / "content/voices.json").read_text())
    en = voices["languages"]["en"]
    computer_settings = {"length_scale": 1.05, "noise_scale": 0.333, "noise_w_scale": 0.333}
    for voice, text, settings in spy.calls:
        assert settings in (computer_settings, {})
        assert "robotic" not in settings  # the client's audio bus filters (FT-AUD-004)
    by_text = {(v, t) for v, t, _ in spy.calls}
    assert (en["computer"]["prerender"], "Hull critical.") in by_text  # a client Ogg line
    assert (en["computer"]["runtime"], "Contact") in by_text
    assert (en["npc"]["runtime"], "hundred") in by_text
    assert sum(1 for v, t, s in spy.calls if t == "hundred") == 2  # once per role
    assert indexes[("en", "computer")]["voice"] == en["computer"]["runtime"]


# FT: FT-AUD-002
def test_blobs_and_indexes_agree(tmp_path):
    _, out, spy, indexes = run(tmp_path)
    for (lang, role), index in indexes.items():
        blob = np.frombuffer((host(out) / lang / f"{role}.pcm").read_bytes(), dtype="<i2")
        at = 0
        for key, (first, n) in index["clips"].items():
            assert first == at and n > 0, key
            clip = blob[first : first + n].astype(np.int32)
            assert abs(int(np.max(np.abs(clip))) - round(0.9 * 32767)) <= 1  # peak normalised
            # Trimmed to the tone plus 10 ms padding: 220 silent samples, plus the
            # tone's first few samples below 0.02 of full scale.
            loud = np.flatnonzero(clip)
            assert 220 <= loud[0] <= 240 and 220 <= n - 1 - loud[-1] <= 240, key
            at += n
        assert at == blob.size
        assert index["rate"] == RATE


# FT: FT-AUD-002
def test_refuses_tracked_locations(tmp_path):
    with pytest.raises(SystemExit):
        prerender.check_out(ROOT / "content", ROOT)
    with pytest.raises(SystemExit):
        prerender.check_out(ROOT / "build/voice", ROOT)
    prerender.check_out(ROOT / "audio/prerendered", ROOT)
    prerender.check_out(ROOT / "audio/prerendered_host", ROOT)
    prerender.check_out(tmp_path / "anywhere", ROOT)


# FT: FT-AUD-018
def test_number_fragment_keeps_only_its_first_utterance():
    rate = 1000
    word = np.full(100, 20000, dtype=np.int16)
    babble = np.concatenate([word, np.zeros(300, dtype=np.int16), word, np.zeros(50, dtype=np.int16), word])
    cut = prerender.first_utterance(babble, rate)
    assert cut.size == 100 + int(prerender.PAD_S * rate)
    short_pause = np.concatenate([word, np.zeros(100, dtype=np.int16), word])
    assert prerender.first_utterance(short_pause, rate).size == short_pause.size


# FT: FT-AUD-002
def test_each_pack_lists_its_files_and_lines_decode(tmp_path):
    import soundfile

    _, out, _, _ = run(tmp_path, langs=("en", "it"))
    for lang in ("en", "it"):
        client = json.loads((out / lang / "index.json").read_text())
        assert client["language"] == lang
        assert client["clips"] == sorted(f.name for f in (out / lang).glob("*.ogg"))
        assert "computer.hull_critical.ogg" in client["clips"]
        pcm, rate = soundfile.read(out / lang / "computer.hull_critical.ogg", dtype="int16")
        assert rate == RATE and pcm.size > 0
        server = json.loads((host(out) / lang / "index.json").read_text())
        assert server == {"language": lang, "clips": ["computer.json", "computer.pcm", "npc.json", "npc.pcm"]}
    assert not (out / "pt_PT").exists()


# FT: FT-AUD-014
def test_dev_only_languages_are_refused_without_dev(capsys):
    import prerender_release

    with pytest.raises(SystemExit):
        prerender_release.main(["pt_PT", "--out", "/tmp/never-written"])
    assert "dev_only" in capsys.readouterr().err
    with pytest.raises(SystemExit):
        prerender.main(["pt_PT"])
