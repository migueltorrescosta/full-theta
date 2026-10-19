"""Build-time prerender of authored voice lines and number fragments (FT-AUD-002, FT-DAT-005).

    uv run --project tools/tts python tools/tts/prerender.py [LANG...] [--out DIR] [--jobs N] [--threads 1]

Reads only content/dialogue/*.json (lines files and numbers.json, not the
schemas) and content/voices.json (FT-DAT-005). Per language and role it writes
DIR/<lang>/<role>.pcm, one blob of 16-bit little-endian mono PCM, and
DIR/<lang>/<role>.json, {"rate", "voice", "clips": {key: [first_sample, samples]}}.
"voice" is the role's runtime voice. Keys (audio/README.md):

- line:<id>    a line without slots, whole, the role's prerender voice;
- seg:<id>:<k> piece k of a slotted line's text split at its slots (k counts
               every piece, empty ones too; only pieces with a letter are
               rendered), the role's runtime voice;
- num:<key>    every numbers.json fragment of the language, the role's runtime voice.

Each clip uses the role's synthesis settings from voices.json `roles`, has its
silence trimmed (0.02 of full scale, 10 ms padding, as spike S7b) and is peak
normalised to 0.9. The ship computer's robotic filter is applied by the client
on an audio bus, not here. DIR defaults to content/voice/prerendered/ at the repo root,
which is gitignored: generated audio is never committed (FT-AUD-002), so any
other location inside the repo is refused.
"""

import argparse
import json
import re
import sys
import time
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path
from typing import Callable

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = ROOT / "content" / "voice" / "prerendered"
LANGS = ("en", "pt_PT", "it")
SLOT = re.compile(r"\{[a-z][a-z0-9_]*\}")
LETTER = re.compile(r"[^\W\d_]")
THRESHOLD = 0.02  # trim: fraction of full scale (S7b)
PAD_S = 0.01  # trim padding (S7b)
PEAK = 0.9  # PROVISIONAL loudness: peak normalise each clip (S7 note; no LUFS yet)
SYNTH_KEYS = ("length_scale", "noise_scale", "noise_w_scale", "speaker")

# synth(voice_name, text, settings) -> (int16 mono PCM, rate)
Synth = Callable[[str, str, dict], tuple[np.ndarray, int]]


def load_content(root: Path) -> tuple[list[dict], dict, dict]:
    """Dialogue lines, numbers.json and voices.json: the only inputs (FT-DAT-005)."""
    lines: list[dict] = []
    numbers: dict = {}
    for f in sorted((root / "content/dialogue").glob("*.json")):
        if f.name.endswith(".schema.json"):
            continue
        data = json.loads(f.read_text(encoding="utf-8"))
        if f.name == "numbers.json":
            numbers = data
        else:
            lines += data["lines"]
    voices = json.loads((root / "content/voices.json").read_text(encoding="utf-8"))
    return lines, numbers, voices


def plan(lines: list[dict], numbers: dict, voices: dict, lang: str) -> dict[str, list[tuple[str, str, str]]]:
    """Per role, the clips to render in blob order: (key, voice name, text)."""
    roles = voices["languages"][lang]
    out: dict[str, list[tuple[str, str, str]]] = {role: [] for role in voices["roles"]}
    for line in lines:
        role, text = line["role"], line["text"][lang]
        if not line.get("slots"):
            out[role].append((f"line:{line['id']}", roles[role]["prerender"], text))
            continue
        for k, piece in enumerate(SLOT.split(text)):
            if LETTER.search(piece):
                out[role].append((f"seg:{line['id']}:{k}", roles[role]["runtime"], piece.strip()))
    for role in out:
        for key, text in numbers["languages"][lang]["fragments"].items():
            out[role].append((f"num:{key}", roles[role]["runtime"], text))
    return out


def trim(pcm: np.ndarray, rate: int) -> np.ndarray:
    loud = np.flatnonzero(np.abs(pcm.astype(np.int32)) > int(THRESHOLD * 32767))
    if loud.size == 0:
        return pcm[:0]
    pad = int(PAD_S * rate)
    return pcm[max(0, loud[0] - pad) : min(pcm.size, loud[-1] + 1 + pad)]


def normalise(pcm: np.ndarray) -> np.ndarray:
    peak = int(np.max(np.abs(pcm.astype(np.int32)))) if pcm.size else 0
    if peak == 0:
        return pcm.astype("<i2")
    return np.clip(np.round(pcm.astype(np.float64) * (PEAK * 32767 / peak)), -32768, 32767).astype("<i2")


def render_clip(synth: Synth, voice: str, text: str, settings: dict) -> tuple[np.ndarray, int]:
    pcm, rate = synth(voice, text, settings)
    clip = normalise(trim(np.asarray(pcm, dtype=np.int16), rate))
    if clip.size == 0:
        raise RuntimeError(f"prerender: {voice}: silent clip for {text!r}")
    return clip, rate


# The real synthesiser: Piper is imported lazily so the tools venv (no Piper) can test this module.
_VOICES: dict = {}
_THREADS = 1


def _init_worker(threads: int) -> None:
    global _THREADS
    _THREADS = threads


def piper_synth(voice: str, text: str, settings: dict) -> tuple[np.ndarray, int]:
    from piper.config import SynthesisConfig

    if voice not in _VOICES:
        sys.path.insert(0, str(Path(__file__).parent))
        from piper_stream import load

        _VOICES[voice] = load(voice, _THREADS)
    v = _VOICES[voice]
    syn = SynthesisConfig(**{k: settings[k] for k in SYNTH_KEYS if k in settings})
    chunks = [c.audio_int16_array for c in v.synthesize(text, syn)]
    pcm = np.concatenate(chunks) if chunks else np.zeros(0, np.int16)
    return pcm, v.config.sample_rate


def _render_voice(synth: Synth, voice: str, items: list[tuple]) -> list[tuple]:
    """Every clip of one voice: [(lang, role, key, pcm, rate)]."""
    return [(lang, role, key, *render_clip(synth, voice, text, settings)) for lang, role, key, text, settings in items]


def _render_voice_piper(voice: str, items: list[tuple]) -> list[tuple]:
    return _render_voice(piper_synth, voice, items)


def check_out(out: Path, root: Path) -> None:
    """Generated audio is never committed (FT-AUD-002): inside the repo only content/voice/prerendered/ is allowed."""
    out, root = out.resolve(), root.resolve()
    if out.is_relative_to(root) and not out.is_relative_to(root / "content" / "voice" / "prerendered"):
        raise SystemExit(f"prerender: refusing {out}: inside the repo only content/voice/prerendered/ (gitignored) is allowed")


def prerender(
    root: Path, out: Path, langs: list[str], synth: Synth | None = None, jobs: int = 1, threads: int = 1
) -> dict[tuple[str, str], dict]:
    """Renders and writes every blob; returns the indexes by (lang, role).

    synth None uses Piper, one process per voice with `jobs` voices in parallel;
    a given synth (tests) runs in this process."""
    check_out(out, root)
    lines, numbers, voices = load_content(root)
    by_voice: dict[str, list[tuple]] = {}
    plans = {lang: plan(lines, numbers, voices, lang) for lang in langs}
    for lang, roles in plans.items():
        for role, clips in roles.items():
            settings = {k: v for k, v in voices["roles"][role].items() if k in SYNTH_KEYS}
            for key, voice, text in clips:
                by_voice.setdefault(voice, []).append((lang, role, key, text, settings))
    if synth is None:
        with ProcessPoolExecutor(max_workers=jobs, initializer=_init_worker, initargs=(threads,)) as pool:
            results = list(pool.map(_render_voice_piper, by_voice, by_voice.values()))
    else:
        results = [_render_voice(synth, voice, items) for voice, items in by_voice.items()]
    rendered = {(lang, role, key): (pcm, rate) for res in results for lang, role, key, pcm, rate in res}
    indexes: dict[tuple[str, str], dict] = {}
    for lang, roles in plans.items():
        (out / lang).mkdir(parents=True, exist_ok=True)
        for role, clips in roles.items():
            rates = {rendered[(lang, role, key)][1] for key, _, _ in clips}
            if len(rates) != 1:
                raise SystemExit(f"prerender: {lang}/{role}: voices disagree on the sample rate {sorted(rates)}")
            index = {"rate": rates.pop(), "voice": voices["languages"][lang][role]["runtime"], "clips": {}}
            parts, at = [], 0
            for key, _, _ in clips:
                pcm = rendered[(lang, role, key)][0]
                index["clips"][key] = [at, int(pcm.size)]
                parts.append(pcm)
                at += pcm.size
            (out / lang / f"{role}.pcm").write_bytes(np.concatenate(parts).astype("<i2").tobytes())
            (out / lang / f"{role}.json").write_text(json.dumps(index, ensure_ascii=False), encoding="utf-8")
            indexes[(lang, role)] = index
    return indexes


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("langs", nargs="*", metavar="LANG", help=f"default: all of {', '.join(LANGS)}")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--jobs", type=int, default=1, help="voices rendered in parallel")
    parser.add_argument("--threads", type=int, default=1, help="onnxruntime threads per voice process")
    args = parser.parse_args(argv)
    langs = args.langs or list(LANGS)
    if unknown := [lang for lang in langs if lang not in LANGS]:
        parser.error(f"unknown language {', '.join(unknown)}")
    start = time.perf_counter()
    indexes = prerender(ROOT, args.out, langs, jobs=args.jobs, threads=args.threads)
    for (lang, role), index in indexes.items():
        samples = sum(n for _, n in index["clips"].values())
        print(f"{lang}/{role}: {len(index['clips'])} clips, {samples / index['rate']:.1f} s, {samples * 2} B")
    print(f"prerender: {time.perf_counter() - start:.1f} s")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
