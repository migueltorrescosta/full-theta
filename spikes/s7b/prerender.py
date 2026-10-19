"""S7b build-time step: prerender number and word fragments per language (D101).

    uv run --project tools/tts python spikes/s7b/prerender.py LANG [--out DIR] [--threads 1]

Renders the numbers 0-999 and the authored words of closed_set.json with the
language's computer voice, trims each fragment's silence (0.02 of full scale,
10 ms padding, as in S7's stitching) and writes one blob of 16-bit mono PCM
plus an index: DIR/LANG.pcm and DIR/LANG.json {"rate", "voice", "frags":
{key: [first_sample, samples]}}. DIR defaults to ~/.cache/full-theta/s7b/fragments.
Generated audio stays outside the repo (FT-AUD-002).
"""

import argparse
import json
import sys
import time
from pathlib import Path

import numpy as np

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE.parent.parent / "tools" / "tts"))
from piper_stream import load  # noqa: E402

THRESHOLD = int(0.02 * 32767)


def trim(pcm: np.ndarray, rate: int) -> np.ndarray:
    loud = np.flatnonzero(np.abs(pcm.astype(np.int32)) > THRESHOLD)
    if loud.size == 0:
        return pcm[:0]
    pad = rate // 100
    return pcm[max(0, loud[0] - pad) : min(pcm.size, loud[-1] + 1 + pad)]


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("lang")
    parser.add_argument("--out", default=str(Path.home() / ".cache/full-theta/s7b/fragments"))
    parser.add_argument("--threads", type=int, default=1)
    args = parser.parse_args(argv)
    spec = json.loads((HERE / "closed_set.json").read_text(encoding="utf-8"))
    lang = spec["languages"][args.lang]
    voice = load(lang["computer"], args.threads)
    rate = voice.config.sample_rate
    texts = {f"num:{n}": str(n) for n in range(1000)}
    texts.update({f"word:{k}": v for k, v in lang["words"].items()})
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    frags: dict[str, list[int]] = {}
    parts: list[np.ndarray] = []
    at = 0
    start = time.perf_counter()
    for key, text in texts.items():
        pcm = np.concatenate([c.audio_int16_array for c in voice.synthesize(text)])
        pcm = trim(pcm, rate)
        frags[key] = [at, int(pcm.size)]
        parts.append(pcm)
        at += pcm.size
    (out / f"{args.lang}.pcm").write_bytes(np.concatenate(parts).astype("<i2").tobytes())
    index = {"rate": rate, "voice": lang["computer"], "frags": frags}
    (out / f"{args.lang}.json").write_text(json.dumps(index), encoding="utf-8")
    took = time.perf_counter() - start
    print(f"{args.lang}: {len(frags)} fragments, {at / rate:.1f} s audio, {at * 2} B, {took:.1f} s")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
