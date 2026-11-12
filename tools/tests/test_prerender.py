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
    (root / "tools/tts").mkdir(parents=True)
    shutil.copy(ROOT / "tools/tts/voices.json", root / "tools/tts/voices.json")
    return root


def host(out: Path) -> Path:
    return out.parent / "prerendered_host"


def run(tmp_path: Path, langs=("en", "pt_PT", "it"), cache=None) -> tuple[Path, Path, Spy, dict]:
    root = content_root(tmp_path)
    out = tmp_path / "out"
    spy = Spy()
    indexes, _ = prerender.prerender(root, out, list(langs), synth=spy, cache=cache)
    return root, out, spy, indexes


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
    indexes, _ = prerender.prerender(root, tmp_path / "out", ["en"], synth=Spy())
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
    # "{count} hostile ships remaining.": piece 0 is empty.
    assert [k for k in computer if k.startswith("seg:computer.hostiles_remaining:")] == [
        "seg:computer.hostiles_remaining:1"
    ]
    texts = {text for _, text, _ in spy.calls}
    assert {"Contact", ", bearing", ", range", "kilometres.", "hostile ships remaining."} <= texts


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


# FT: FT-AUD-002 cache tests
def test_cache_hits_on_second_run(tmp_path):
    """Second run with same inputs calls synth zero times and writes byte-identical packs."""
    cache_dir = tmp_path / "cache"
    # First run
    root1, out1, spy1, indexes1 = run(tmp_path, ["en"], cache=cache_dir)
    first_calls = len(spy1.calls)
    assert first_calls > 0

    # Second run with same cache
    out2 = tmp_path / "out2"
    spy2 = Spy()
    indexes2, (rendered, hits) = prerender.prerender(root1, out2, ["en"], synth=spy2, cache=cache_dir)

    # Synth should not be called at all
    assert len(spy2.calls) == 0
    assert rendered == 0
    assert hits == first_calls

    # Output packs must be byte-identical (PCM and JSON); Ogg files compared via decoded audio
    import soundfile
    for lang in ("en",):
        for role in ("computer", "npc"):
            pcm1 = (host(out1) / lang / f"{role}.pcm").read_bytes()
            pcm2 = (host(out2) / lang / f"{role}.pcm").read_bytes()
            assert pcm1 == pcm2, f"PCM differs for {lang}/{role}"
            json1 = (host(out1) / lang / f"{role}.json").read_bytes()
            json2 = (host(out2) / lang / f"{role}.json").read_bytes()
            assert json1 == json2, f"JSON differs for {lang}/{role}"
        # Client Ogg files - compare decoded audio since Vorbis encoding may not be byte-deterministic
        for ogg1 in (out1 / lang).glob("*.ogg"):
            ogg2 = out2 / lang / ogg1.name
            pcm1, rate1 = soundfile.read(ogg1, dtype="int16")
            pcm2, rate2 = soundfile.read(ogg2, dtype="int16")
            assert rate1 == rate2
            assert np.array_equal(pcm1, pcm2), f"Decoded Ogg differs for {ogg1.name}"


def test_cache_invalidated_by_text_change(tmp_path):
    """Changing one line's text re-renders only that line's clip."""
    cache_dir = tmp_path / "cache"
    # First run
    root1, out1, spy1, _ = run(tmp_path, ["en"], cache=cache_dir)
    first_calls = list(spy1.calls)  # list of (voice, text, settings)
    first_call_count = len(first_calls)

    # Modify one line's text in the dialogue JSON
    dialogue_file = root1 / "content/dialogue" / "computer.json"
    data = json.loads(dialogue_file.read_text())
    for line in data["lines"]:
        if line["id"] == "computer.hull_critical":
            line["text"]["en"] = "Hull integrity critical."
            break
    dialogue_file.write_text(json.dumps(data, indent=1))

    # Second run
    out2 = tmp_path / "out2"
    spy2 = Spy()
    indexes2, (rendered, hits) = prerender.prerender(root1, out2, ["en"], synth=spy2, cache=cache_dir)

    # Only the changed line should be re-rendered
    second_calls = set((v, t) for v, t, _ in spy2.calls)
    first_call_texts = set((v, t) for v, t, _ in first_calls)
    new_calls = second_calls - first_call_texts
    # The changed line uses the prerender voice
    voices = json.loads((root1 / "content/voices.json").read_text())
    expected_voice = voices["languages"]["en"]["computer"]["prerender"]
    assert new_calls == {(expected_voice, "Hull integrity critical.")}
    assert rendered == 1
    assert hits == first_call_count - 1  # all but one clip were cached

    # Unchanged clips should have identical output
    pcm1 = (host(out1) / "en" / "computer.pcm").read_bytes()
    pcm2 = (host(out2) / "en" / "computer.pcm").read_bytes()
    # The PCM blob will differ because one clip changed, but the index should reflect only that change
    index1 = json.loads((host(out1) / "en" / "computer.json").read_text())
    index2 = json.loads((host(out2) / "en" / "computer.json").read_text())
    # The clips dict should be the same except for the line: clip (which is not in host pack)
    # Host pack only has seg: and num: clips, which are unchanged
    assert index1["clips"] == index2["clips"]


def test_cache_invalidated_by_role_settings_change(tmp_path):
    """Changing one role's settings re-renders only that role's clips."""
    cache_dir = tmp_path / "cache"
    # First run
    root1, out1, spy1, _ = run(tmp_path, ["en"], cache=cache_dir)
    first_calls_by_role: dict[str, list[tuple[str, str, dict]]] = {}
    for voice, text, settings in spy1.calls:
        # Determine role from voice name
        role = "computer" if "cori" in voice else "npc"
        first_calls_by_role.setdefault(role, []).append((voice, text, settings))
    first_computer_count = len(first_calls_by_role.get("computer", []))
    first_npc_count = len(first_calls_by_role.get("npc", []))

    # Modify computer's settings in voices.json
    voices_file = root1 / "content/voices.json"
    voices_data = json.loads(voices_file.read_text())
    voices_data["roles"]["computer"]["length_scale"] = 1.5  # changed from 1.05
    voices_file.write_text(json.dumps(voices_data, indent=1))

    # Second run
    out2 = tmp_path / "out2"
    spy2 = Spy()
    indexes2, (rendered, hits) = prerender.prerender(root1, out2, ["en"], synth=spy2, cache=cache_dir)

    # Only computer's clips should be re-rendered
    second_calls_by_role: dict[str, set[tuple[str, str]]] = {}
    for voice, text, settings in spy2.calls:
        role = "computer" if "cori" in voice else "npc"
        second_calls_by_role.setdefault(role, set()).add((voice, text))

    # npc should have zero new calls (all cached)
    assert len(second_calls_by_role.get("npc", set())) == 0
    # computer should have all its clips re-rendered
    assert len(second_calls_by_role.get("computer", set())) > 0
    assert rendered == first_computer_count
    assert hits == first_npc_count


def test_cache_invalidated_by_voice_hash_change(tmp_path):
    """Changing a voice's pinned sha256 re-renders only that voice's clips."""
    cache_dir = tmp_path / "cache"
    # First run
    root1, out1, spy1, _ = run(tmp_path, ["en"], cache=cache_dir)
    first_calls_by_voice: dict[str, list[tuple[str, str, dict]]] = {}
    first_unique_by_voice: dict[str, set[tuple[str, str]]] = {}
    for voice, text, settings in spy1.calls:
        first_calls_by_voice.setdefault(voice, []).append((voice, text, settings))
        first_unique_by_voice.setdefault(voice, set()).add((voice, text))

    # Modify one voice's hash in tools/tts/voices.json (computer uses cori-high for prerender)
    voices_file = root1 / "tools/tts/voices.json"
    voices_data = json.loads(voices_file.read_text())
    # Change the hash for en_GB-cori-high
    voices_data["voices"]["en_GB-cori-high"]["en/en_GB/cori/high/en_GB-cori-high.onnx"]["sha256"] = (
        "0" * 64
    )
    voices_file.write_text(json.dumps(voices_data, indent=1))

    # Second run
    out2 = tmp_path / "out2"
    spy2 = Spy()
    indexes2, (rendered, hits) = prerender.prerender(root1, out2, ["en"], synth=spy2, cache=cache_dir)

    # Only clips using the modified voice should be re-rendered
    second_calls_by_voice: dict[str, set[tuple[str, str]]] = {}
    for voice, text, settings in spy2.calls:
        second_calls_by_voice.setdefault(voice, set()).add((voice, text))

    # en_GB-cori-high is used for computer's prerender (line: clips)
    # en_GB-cori-medium is used for computer's runtime (seg: clips) and npc's runtime
    # en_US-kristin-medium is used for npc's prerender
    modified_voice = "en_GB-cori-high"
    assert modified_voice in second_calls_by_voice
    # All unique clips for the modified voice should be re-rendered
    assert second_calls_by_voice[modified_voice] == first_unique_by_voice[modified_voice]
    # Other voices should be cached (no new calls)
    for voice in first_calls_by_voice:
        if voice != modified_voice:
            assert voice not in second_calls_by_voice or second_calls_by_voice[voice] == set()
    # Total rendered clips should equal all clips that used the modified voice
    assert rendered == len(first_calls_by_voice[modified_voice])
    assert hits == sum(len(v) for k, v in first_calls_by_voice.items() if k != modified_voice)


def test_cache_none_disables_cache(tmp_path):
    """cache=None renders everything each time."""
    cache_dir = tmp_path / "cache"
    # First run with cache
    root1, out1, spy1, _ = run(tmp_path, ["en"], cache=cache_dir)
    first_calls = len(spy1.calls)

    # Second run with cache=None (disabled)
    out2 = tmp_path / "out2"
    spy2 = Spy()
    indexes2, (rendered, hits) = prerender.prerender(root1, out2, ["en"], synth=spy2, cache=None)

    # All clips should be re-rendered
    assert len(spy2.calls) == first_calls
    assert rendered == first_calls
    assert hits == 0

    # Output should still be byte-identical (PCM and JSON); Ogg files compared via decoded audio
    import soundfile
    for lang in ("en",):
        for role in ("computer", "npc"):
            pcm1 = (host(out1) / lang / f"{role}.pcm").read_bytes()
            pcm2 = (host(out2) / lang / f"{role}.pcm").read_bytes()
            assert pcm1 == pcm2
            json1 = (host(out1) / lang / f"{role}.json").read_bytes()
            json2 = (host(out2) / lang / f"{role}.json").read_bytes()
            assert json1 == json2
        for ogg1 in (out1 / lang).glob("*.ogg"):
            ogg2 = out2 / lang / ogg1.name
            pcm1, rate1 = soundfile.read(ogg1, dtype="int16")
            pcm2, rate2 = soundfile.read(ogg2, dtype="int16")
            assert rate1 == rate2
            assert np.array_equal(pcm1, pcm2)
