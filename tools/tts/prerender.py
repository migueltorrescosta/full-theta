"""Build-time prerender of authored voice lines and number fragments (FT-AUD-002, FT-DAT-005).

    uv run --project tools/tts python tools/tts/prerender.py [LANG...] [--out DIR] [--jobs N] [--threads 1]

Reads only content/dialogue/*.json (lines files and numbers.json, not the
schemas) and content/voices.json (FT-DAT-005), and writes two packs (D152, D154):

- client pack, OUT/<lang>/ (default audio/prerendered/): `<line id>.ogg`, Ogg
  Vorbis, one per line without slots (key line:<id>, whole, the role's prerender
  voice); clients play these locally, web exports included;
- host pack, HOST/<lang>/ (default audio/prerendered_host/): per role
  `<role>.pcm`, one blob of 16-bit little-endian mono PCM, and `<role>.json`,
  {"rate", "voice", "clips": {key: [first_sample, samples]}} ("voice" is the
  role's runtime voice), holding the clips the host stitches:
  - seg:<id>:<k> piece k of a slotted line's text split at its slots (k counts
                 every piece, empty ones too; only pieces with a letter are
                 rendered), the role's runtime voice;
  - num:<key>    every numbers.json fragment of the language, the role's runtime
                 voice, cut at its first 200 ms silence.

Both language folders get index.json {"language", "clips": [file, ...]}, which the
package inspection checks. Each clip uses the role's synthesis settings from voices.json `roles`, has its
silence trimmed (0.02 of full scale, 10 ms padding, as spike S7b) and is peak
normalised to 0.9. The ship computer's robotic filter is applied by the client
on an audio bus, not here. Both default folders are gitignored: generated audio
is never committed (FT-AUD-002), so any other location inside the repo is refused.
"""

import argparse
import json
import io
import re
import shutil
import sys
import time
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path
from typing import Callable

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = ROOT / "audio" / "prerendered"
LANGS = ("en", "pt_PT", "it")
SLOT = re.compile(r"\{[a-z][a-z0-9_]*\}")
LETTER = re.compile(r"[^\W\d_]")
THRESHOLD = 0.02  # trim: fraction of full scale (S7b)
PAD_S = 0.01  # trim padding (S7b)
# PROVISIONAL: some voices babble after a single word ("and" on cori-medium runs 4-7 s,
# norman-medium's digits 2-2.7 s), so a number fragment keeps only its first utterance:
# it ends at the first silence (below THRESHOLD) of at least this long.
FRAGMENT_GAP_S = 0.2
# PROVISIONAL (D154): libsndfile's Vorbis compression level, 0 best .. 1 smallest;
# 0.8 gives about 53 kbps (6.6 KB per second of 22.05 kHz mono speech) plus about
# 3.5 KB of Vorbis headers per file.
VORBIS_LEVEL = 0.8
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


# --- strand G2 ---
def _is_binding(spec) -> bool:
    return spec == "binding" or (isinstance(spec, dict) and spec.get("kind") == "binding")


def _voiced_slots(line: dict) -> list[str]:
    """The line's slots other than the text-only binding ones."""
    return [name for name, spec in line.get("slots", {}).items() if not _is_binding(spec)]


def strip_bindings(line: dict, text: str) -> str:
    """The text without its binding slots (and the space before each): what is voiced."""
    for name, spec in line.get("slots", {}).items():
        if _is_binding(spec):
            text = re.sub(r"\s*\{" + re.escape(name) + r"\}", "", text)
    return text.strip()


# --- end strand G2 ---
def plan(lines: list[dict], numbers: dict, voices: dict, lang: str) -> dict[str, list[tuple[str, str, str]]]:
    """Per role, the clips to render in blob order: (key, voice name, text)."""
    roles = voices["languages"][lang]
    out: dict[str, list[tuple[str, str, str]]] = {role: [] for role in voices["roles"]}
    for line in lines:
        role, text = line["role"], line["text"][lang]
        # --- strand G2 --- A binding slot is text-only (FT-MIS-039): it is never voiced, so a
        # line whose only slots are bindings is one whole clip of its text without them.
        if not _voiced_slots(line):
            out[role].append((f"line:{line['id']}", roles[role]["prerender"], strip_bindings(line, text)))
            continue
        # --- end strand G2 ---
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


def first_utterance(pcm: np.ndarray, rate: int) -> np.ndarray:
    """Cuts a trimmed clip at its first silence of FRAGMENT_GAP_S or longer."""
    loud = np.flatnonzero(np.abs(pcm.astype(np.int32)) > int(THRESHOLD * 32767))
    if loud.size < 2:
        return pcm
    gaps = np.flatnonzero(np.diff(loud) >= int(FRAGMENT_GAP_S * rate))
    if gaps.size == 0:
        return pcm
    return pcm[: min(pcm.size, loud[gaps[0]] + 1 + int(PAD_S * rate))]


def normalise(pcm: np.ndarray) -> np.ndarray:
    peak = int(np.max(np.abs(pcm.astype(np.int32)))) if pcm.size else 0
    if peak == 0:
        return pcm.astype("<i2")
    return np.clip(np.round(pcm.astype(np.float64) * (PEAK * 32767 / peak)), -32768, 32767).astype("<i2")


def render_clip(
    synth: Synth, voice: str, text: str, settings: dict, fragment: bool = False
) -> tuple[np.ndarray, int]:
    pcm, rate = synth(voice, text, settings)
    clip = trim(np.asarray(pcm, dtype=np.int16), rate)
    if fragment:
        clip = first_utterance(clip, rate)
    clip = normalise(clip)
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
    return [
        (lang, role, key, *render_clip(synth, voice, text, settings, key.startswith("num:")))
        for lang, role, key, text, settings in items
    ]


def _render_voice_piper(voice: str, items: list[tuple]) -> list[tuple]:
    return _render_voice(piper_synth, voice, items)


def check_out(out: Path, root: Path) -> None:
    """Generated audio is never committed (FT-AUD-002): inside the repo only the
    gitignored audio/prerendered/ and audio/prerendered_host/ are allowed."""
    out, root = out.resolve(), root.resolve()
    allowed = (root / "audio" / "prerendered", root / "audio" / "prerendered_host")
    if out.is_relative_to(root) and not any(out.is_relative_to(a) for a in allowed):
        raise SystemExit(
            f"prerender: refusing {out}: inside the repo only audio/prerendered/ and "
            "audio/prerendered_host/ (gitignored) are allowed"
        )


def encode_ogg(pcm: np.ndarray, rate: int) -> bytes:
    """Ogg Vorbis for the client pack (D154); soundfile (libsndfile) is imported here so
    the module loads without it."""
    import soundfile

    buf = io.BytesIO()
    soundfile.write(buf, pcm, rate, format="OGG", subtype="VORBIS", compression_level=VORBIS_LEVEL)
    return buf.getvalue()


def write_index(folder: Path, lang: str) -> list[str]:
    """index.json for the package inspection: every file of the pack's language folder."""
    clips = sorted(p.name for p in folder.iterdir() if p.is_file() and p.name != "index.json")
    index = {"language": lang, "clips": clips}
    (folder / "index.json").write_text(json.dumps(index, indent=1) + "\n", encoding="utf-8")
    return clips


def prerender(
    root: Path,
    out: Path,
    langs: list[str],
    synth: Synth | None = None,
    jobs: int = 1,
    threads: int = 1,
    host_out: Path | None = None,
) -> dict[tuple[str, str], dict]:
    """Renders and writes both packs; returns the host indexes by (lang, role).

    Client pack, `out/<lang>/`: one Ogg Vorbis file per line without slots,
    `<line id>.ogg`. Host pack, `host_out/<lang>/` (default: out's sibling
    `prerendered_host`): per role a PCM blob and its index of the seg:* and num:*
    clips. Each folder gets an index.json listing its files. synth None uses Piper,
    one process per voice with `jobs` voices in parallel; a given synth (tests) runs
    in this process."""
    host_out = host_out if host_out is not None else out.parent / "prerendered_host"
    check_out(out, root)
    check_out(host_out, root)
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
        for folder in (out / lang, host_out / lang):
            if folder.exists():
                shutil.rmtree(folder)
            folder.mkdir(parents=True)
        for role, clips in roles.items():
            for key, _, _ in clips:
                if key.startswith("line:"):
                    pcm, rate = rendered[(lang, role, key)]
                    (out / lang / f"{key[5:]}.ogg").write_bytes(encode_ogg(pcm, rate))
            stitched = [key for key, _, _ in clips if not key.startswith("line:")]
            rates = {rendered[(lang, role, key)][1] for key in stitched}
            if len(rates) != 1:
                raise SystemExit(f"prerender: {lang}/{role}: voices disagree on the sample rate {sorted(rates)}")
            index = {"rate": rates.pop(), "voice": voices["languages"][lang][role]["runtime"], "clips": {}}
            parts, at = [], 0
            for key in stitched:
                pcm = rendered[(lang, role, key)][0]
                index["clips"][key] = [at, int(pcm.size)]
                parts.append(pcm)
                at += pcm.size
            (host_out / lang / f"{role}.pcm").write_bytes(np.concatenate(parts).astype("<i2").tobytes())
            (host_out / lang / f"{role}.json").write_text(json.dumps(index, ensure_ascii=False), encoding="utf-8")
            indexes[(lang, role)] = index
        write_index(out / lang, lang)
        write_index(host_out / lang, lang)
    return indexes


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("langs", nargs="*", metavar="LANG", help=f"default: all of {', '.join(LANGS)}")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help="client pack (Ogg lines)")
    parser.add_argument(
        "--dev", action="store_true", help="also allow languages whose voices are dev_only (never shipped)"
    )
    parser.add_argument("--host-out", type=Path, default=None, help="host pack [OUT/../prerendered_host]")
    parser.add_argument("--jobs", type=int, default=1, help="voices rendered in parallel")
    parser.add_argument("--threads", type=int, default=1, help="onnxruntime threads per voice process")
    args = parser.parse_args(argv)
    voices = json.loads((ROOT / "content/voices.json").read_text(encoding="utf-8"))["languages"]
    dev_only = [lang for lang in LANGS if voices[lang].get("dev_only")]
    langs = args.langs or [lang for lang in LANGS if args.dev or lang not in dev_only]
    if unknown := [lang for lang in langs if lang not in LANGS]:
        parser.error(f"unknown language {', '.join(unknown)}")
    if not args.dev and (refused := [lang for lang in langs if lang in dev_only]):
        parser.error(f"{', '.join(refused)}: dev_only voices are never shipped (D105); pass --dev for a development build")
    start = time.perf_counter()
    out = args.out.resolve()
    host_out = args.host_out.resolve() if args.host_out else None
    indexes = prerender(ROOT, out, langs, jobs=args.jobs, threads=args.threads, host_out=host_out)
    for (lang, role), index in indexes.items():
        samples = sum(n for _, n in index["clips"].values())
        print(f"host {lang}/{role}: {len(index['clips'])} clips, {samples / index['rate']:.1f} s, {samples * 2} B")
    for lang in langs:
        files = list((out / lang).glob("*.ogg"))
        print(f"client {lang}: {len(files)} lines, {sum(f.stat().st_size for f in files)} B Ogg")
    print(f"prerender: {time.perf_counter() - start:.1f} s")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
