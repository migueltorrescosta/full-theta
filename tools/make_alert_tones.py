"""Synthesise the alert tones (FT-AUD-009, T056) into assets/sounds/alerts/.

Our own work, dedicated CC0-1.0 (content/provenance.json). Deterministic: rerunning
rewrites the same bytes. 22,050 Hz 16-bit mono WAV, each well under a second, kept soft
(peaks at most -6 dBFS) so they don't fatigue over a long run.

    uv run --project tools python tools/make_alert_tones.py
"""

import math
import random
import struct
import wave
from pathlib import Path

RATE = 22050
OUT = Path(__file__).resolve().parent.parent / "assets" / "sounds" / "alerts"


def tone(
    freq0: float, freq1: float, dur: float, decay: float = 0.0, harm: float = 0.0
) -> list[float]:
    """A sine sweeping freq0 -> freq1 over dur s, with a 5 ms attack and release, an
    optional exponential decay (1/s) and a touch of 3rd harmonic for edge."""
    n = int(RATE * dur)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        f = freq0 + (freq1 - freq0) * t / dur
        phase += 2 * math.pi * f / RATE
        env = min(1.0, t / 0.005, (dur - t) / 0.005) * math.exp(-decay * t)
        out.append(env * (math.sin(phase) + harm * math.sin(3 * phase)) / (1 + harm))
    return out


def silence(dur: float) -> list[float]:
    return [0.0] * int(RATE * dur)


def hit() -> list[float]:
    """A low thump: a falling 90->40 Hz sine with a short noise transient."""
    rng = random.Random(7)
    body = tone(90, 40, 0.28, decay=14)
    for i in range(int(RATE * 0.03)):
        body[i] += 0.5 * rng.uniform(-1, 1) * (1 - i / (RATE * 0.03))
    return body


def fault() -> list[float]:
    """Two-tone, high then low."""
    return tone(660, 660, 0.12, harm=0.2) + silence(0.03) + tone(440, 440, 0.18, harm=0.2)


def shield_low() -> list[float]:
    """Three soft pulses, each a little lower."""
    out: list[float] = []
    for f in (620, 580, 540):
        out += tone(f, f, 0.08) + silence(0.06)
    return out


def proximity() -> list[float]:
    """Four quick high beeps (collision course)."""
    out: list[float] = []
    for _ in range(4):
        out += tone(1000, 1000, 0.05, harm=0.1) + silence(0.04)
    return out


def ping() -> list[float]:
    """A soft bell: a fifth (1,320 and 1,980 Hz) ringing out."""
    a = tone(1320, 1320, 0.6, decay=7)
    b = tone(1980, 1980, 0.6, decay=10)
    return [0.7 * x + 0.3 * y for x, y in zip(a, b)]


def alert_red() -> list[float]:
    """Two rising sweeps, a gentle klaxon."""
    sweep = tone(440, 700, 0.22, harm=0.3)
    return sweep + silence(0.05) + sweep


def alert_yellow() -> list[float]:
    """Two even mid tones."""
    return tone(520, 520, 0.12) + silence(0.06) + tone(520, 520, 0.12)


def alert_normal() -> list[float]:
    """One soft falling tone (stand down)."""
    return tone(660, 440, 0.3, decay=3)


# Name -> (generator, peak in dBFS).
TONES = {
    "hit": (hit, -6.0),
    "fault": (fault, -9.0),
    "shield_low": (shield_low, -9.0),
    "proximity": (proximity, -9.0),
    "ping": (ping, -14.0),
    "alert_red": (alert_red, -9.0),
    "alert_yellow": (alert_yellow, -10.0),
    "alert_normal": (alert_normal, -12.0),
}


def write(path: Path, samples: list[float], peak_db: float) -> None:
    peak = max(abs(s) for s in samples) or 1.0
    gain = 10 ** (peak_db / 20) / peak
    frames = b"".join(struct.pack("<h", round(32767 * s * gain)) for s in samples)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(frames)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, (gen, peak_db) in TONES.items():
        write(OUT / f"{name}.wav", gen(), peak_db)


if __name__ == "__main__":
    main()
