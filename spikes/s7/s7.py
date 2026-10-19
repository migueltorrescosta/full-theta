"""S7 spike (T017): render sample lines with Piper, the ship-computer filter, stitching, RTF.

Throwaway. Run from the repo root:
    uv run --project tools/tts python spikes/s7/s7.py render OUT_DIR
    taskset -c 4 uv run --project tools/tts python spikes/s7/s7.py rtf VOICE LANG THREADS

Output is WAV, never committed (FT-AUD-002).
"""

import json
import sys
import time
import wave
from pathlib import Path

import numpy as np
import onnxruntime
from piper import PiperVoice, SynthesisConfig
from piper.config import PiperConfig

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1] / "tools" / "tts"))
from fetch_voices import model_path  # noqa: E402

LINES = json.loads((HERE / "lines.json").read_text(encoding="utf-8"))

# Two voices per language (licence audit in docs/spikes/S7.md). espeak overrides
# the phonemiser voice: faber is a pt_BR model given European pt phonemes.
PLAN = {
    "en": [("en_GB-cori-high", {}), ("en_US-norman-medium", {})],
    "it": [("it_IT-serena-high", {}), ("it_IT-riccardo-x_low", {})],
    "pt_PT": [("pt_PT-tugão-medium", {}), ("pt_BR-faber-medium", {"espeak": "pt"})],
}
# Extra comparisons, not part of the two-voice set.
EXTRA = {
    "it": [("it_IT-paola-medium", {})],
    "en": [("en_US-libritts-high", {"speaker": s}) for s in ("p3922", "p6701", "p922")],
}
# Flatter delivery for the ship computer.
COMPUTER_SYN = SynthesisConfig(noise_scale=0.333, noise_w_scale=0.333, length_scale=1.05)
GAP_S = 0.07  # silence between stitched fragments


def load(voice: str, threads: int = 0, espeak: str | None = None) -> PiperVoice:
    """Load a voice with a fixed ONNX thread count (0 = onnxruntime default)."""
    onnx = model_path(voice)
    config = json.loads(Path(f"{onnx}.json").read_text(encoding="utf-8"))
    if espeak:
        config["espeak"]["voice"] = espeak
    opts = onnxruntime.SessionOptions()
    if threads:
        opts.intra_op_num_threads = threads
        opts.inter_op_num_threads = 1
    session = onnxruntime.InferenceSession(str(onnx), sess_options=opts, providers=["CPUExecutionProvider"])
    return PiperVoice(config=PiperConfig.from_dict(config), session=session)


def synth(voice: PiperVoice, text: str, syn: SynthesisConfig | None = None) -> np.ndarray:
    """Float32 mono audio for text; sentences are joined with 0.2 s of silence."""
    parts = []
    for chunk in voice.synthesize(text, syn):
        if parts:
            parts.append(np.zeros(int(0.2 * chunk.sample_rate), np.float32))
        parts.append(chunk.audio_float_array)
    return np.concatenate(parts) if parts else np.zeros(0, np.float32)


def write_wav(path: Path, audio: np.ndarray, rate: int) -> float:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = (np.clip(audio, -1, 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(pcm.tobytes())
    return len(audio) / rate


def trim(audio: np.ndarray, rate: int, threshold: float = 0.02, pad_s: float = 0.01) -> np.ndarray:
    """Cut leading and trailing silence, keeping a few ms of padding."""
    loud = np.flatnonzero(np.abs(audio) > threshold)
    if not len(loud):
        return audio
    pad = int(pad_s * rate)
    return audio[max(0, loud[0] - pad) : loud[-1] + pad]


def stitch(voice: PiperVoice, fragments: list[str], syn: SynthesisConfig | None = None) -> np.ndarray:
    rate = voice.config.sample_rate
    gap = np.zeros(int(GAP_S * rate), np.float32)
    out: list[np.ndarray] = []
    for f in fragments:
        if out:
            out.append(gap)
        out.append(trim(synth(voice, f, syn), rate))
    audio = np.concatenate(out)
    return audio / max(1e-8, float(np.max(np.abs(audio))))


def bandpass(x: np.ndarray, rate: int, lo: float, hi: float, taper: float = 150.0) -> np.ndarray:
    """Zero-phase FFT band-pass with raised-cosine edges of width taper Hz."""
    n = len(x)
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1 / rate)
    gain = np.ones_like(f)
    low = f < lo + taper
    gain[low] = 0.5 - 0.5 * np.cos(np.pi * np.clip((f[low] - lo) / taper, 0, 1))
    high = f > hi - taper
    gain[high] = 0.5 + 0.5 * np.cos(np.pi * np.clip((f[high] - (hi - taper)) / taper, 0, 1))
    return np.fft.irfft(spec * gain, n).astype(np.float32)


def robotic(x: np.ndarray, rate: int) -> np.ndarray:
    """Ship-computer filter (FT-AUD-004): ring mod, metallic comb, band-pass, light bitcrush."""
    t = np.arange(len(x)) / rate
    # 1. Ring modulation at 70 Hz, 35 % wet: a buzz under the voice.
    y = x * (0.65 + 0.35 * np.sin(2 * np.pi * 70 * t))
    # 2. Feedforward comb at 6 ms: a hollow, metallic resonance.
    d = int(0.006 * rate)
    y = y + 0.45 * np.concatenate([np.zeros(d), y[:-d]])
    # 3. Band-pass 300-3400 Hz: intercom bandwidth.
    y = bandpass(y.astype(np.float32), rate, 300, 3400)
    # 4. Light bitcrush: 2-sample hold (half rate) and 6-bit quantising, 30 % wet.
    held = np.repeat(y[::2], 2)[: len(y)]
    crushed = np.round(held * 32) / 32
    y = 0.7 * y + 0.3 * crushed
    return (0.9 * y / max(1e-8, float(np.max(np.abs(y))))).astype(np.float32)


def render(out: Path) -> None:
    old = out / "index.md"
    # Keep a hand-written preamble (everything before the first language heading).
    pre = old.read_text(encoding="utf-8").split("\n## ")[0] if old.exists() else "# S7 samples (issue #3, T017)"
    index = [pre.rstrip("\n"), ""]
    texts = {(lang, ln["id"]): ln[lang] for ln in LINES["lines"] for lang in PLAN}
    for lang in PLAN:
        index += [f"## {lang}", ""]
        for voice_name, opts in PLAN[lang] + EXTRA.get(lang, []):
            voice = load(voice_name, espeak=opts.get("espeak"))
            rate = voice.config.sample_rate
            spk = opts.get("speaker")
            syn = None
            label = voice_name + (f"-{spk}" if spk else "") + (f"-espeak_{opts['espeak']}" if "espeak" in opts else "")
            if spk is not None:
                syn = SynthesisConfig(speaker_id=voice.config.speaker_id_map[spk])
            base = out / lang / label
            extra = (voice_name, opts) not in PLAN[lang]
            index += [f"### {label}{' (extra comparison)' if extra else ''}", "", "| File | Text |", "|---|---|"]
            for ln in LINES["lines"]:
                if extra and ln["role"] != "npc":
                    continue
                if extra and spk and ln["id"] not in ("npc01", "npc03", "npc07", "npc08", "npc09"):
                    continue
                f = base / f"{ln['id']}.wav"
                write_wav(f, synth(voice, ln[lang], syn), rate)
                index.append(f"| `{f.relative_to(out)}` | {ln[lang]} |")
            if extra:
                index.append("")
                continue
            for ln in LINES["lines"]:
                if ln["role"] != "computer":
                    continue
                f = base / "computer" / f"{ln['id']}.wav"
                write_wav(f, robotic(synth(voice, ln[lang], COMPUTER_SYN), rate), rate)
                index.append(f"| `{f.relative_to(out)}` | (ship computer, filtered) {texts[(lang, ln['id'])]} |")
            for st in LINES["stitched"]:
                frags = st[lang]
                full_text = " ".join(frags)
                for kind, audio in (
                    ("full", synth(voice, full_text)),
                    ("stitched", stitch(voice, frags)),
                    ("stitched-computer", robotic(stitch(voice, frags, COMPUTER_SYN), rate)),
                ):
                    f = base / "stitched" / f"{st['id']}-{kind}.wav"
                    write_wav(f, audio, rate)
                    shown = full_text if kind == "full" else " | ".join(frags)
                    index.append(f"| `{f.relative_to(out)}` | ({kind}) {shown} |")
            index.append("")
            print(f"render: {label}", file=sys.stderr)
    (out / "index.md").write_text("\n".join(index) + "\n", encoding="utf-8")


def rtf(voice_name: str, lang: str, threads: int, espeak: str | None = None) -> dict:
    """Cold load, first-line latency and warm RTF over the 20 lines."""
    t0 = time.perf_counter()
    voice = load(voice_name, threads, espeak)
    load_s = time.perf_counter() - t0
    texts = [ln[lang] for ln in LINES["lines"]]
    t0 = time.perf_counter()
    synth(voice, texts[0])
    first_s = time.perf_counter() - t0
    synth_s = audio_s = 0.0
    per_line = []
    for text in texts:
        t0 = time.perf_counter()
        a = synth(voice, text)
        dt = time.perf_counter() - t0
        synth_s += dt
        audio_s += len(a) / voice.config.sample_rate
        per_line.append(dt)
    return {
        "voice": voice_name, "lang": lang, "threads": threads,
        "load_s": round(load_s, 3), "first_line_s": round(first_s, 3),
        "audio_s": round(audio_s, 2), "synth_s": round(synth_s, 3),
        "rtf": round(synth_s / audio_s, 4), "max_line_s": round(max(per_line), 3),
        "mean_line_s": round(synth_s / len(texts), 3),
    }


def main(argv: list[str]) -> int:
    if argv[0] == "render":
        render(Path(argv[1]))
    elif argv[0] == "rtf":
        print(json.dumps(rtf(argv[1], argv[2], int(argv[3]), argv[4] if len(argv) > 4 else None)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
