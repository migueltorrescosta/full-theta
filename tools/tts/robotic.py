"""Ship-computer filter (FT-AUD-004, D71), promoted from spike S7 (`robotic` in spikes/s7/s7.py).

Float32 mono in, float32 mono out, peak 0.9. `from_int16` and `to_int16` convert
16-bit PCM. Numpy only. Neither the prerender nor the host's Piper processes
apply it: release builds run the standalone Piper binary, so the client plays
computer lines on an audio bus with effects. This module is the reference for
that bus and lets a listener render filtered samples offline. Every parameter
is PROVISIONAL: the owner judges the sound in #4.
"""

import numpy as np

# PROVISIONAL (#4): S7's chain, in order.
RING_HZ = 70.0  # ring modulation frequency: a buzz under the voice
RING_WET = 0.35
COMB_DELAY_S = 0.006  # feedforward comb: a hollow, metallic resonance
COMB_GAIN = 0.45
BAND_LO_HZ = 300.0  # intercom bandwidth
BAND_HI_HZ = 3400.0
BAND_TAPER_HZ = 150.0  # raised-cosine edge width
CRUSH_HOLD = 2  # sample-and-hold factor (half rate)
CRUSH_LEVELS = 32  # 6-bit quantising over -1..1
CRUSH_WET = 0.3
PEAK = 0.9  # output peak (S7: even level)


def bandpass(x: np.ndarray, rate: int, lo: float, hi: float, taper: float = BAND_TAPER_HZ) -> np.ndarray:
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
    """Ring mod, metallic comb, band-pass, light bitcrush, then peak normalise."""
    if len(x) == 0:
        return np.zeros(0, np.float32)
    t = np.arange(len(x)) / rate
    y = x * ((1 - RING_WET) + RING_WET * np.sin(2 * np.pi * RING_HZ * t))
    d = min(int(COMB_DELAY_S * rate), len(y))
    y = y + COMB_GAIN * np.concatenate([np.zeros(d), y[: len(y) - d]])
    y = bandpass(y.astype(np.float32), rate, BAND_LO_HZ, BAND_HI_HZ)
    held = np.repeat(y[::CRUSH_HOLD], CRUSH_HOLD)[: len(y)]
    crushed = np.round(held * CRUSH_LEVELS) / CRUSH_LEVELS
    y = (1 - CRUSH_WET) * y + CRUSH_WET * crushed
    return (PEAK * y / max(1e-8, float(np.max(np.abs(y))))).astype(np.float32)


def from_int16(pcm: np.ndarray) -> np.ndarray:
    return (np.asarray(pcm, dtype=np.int16).astype(np.float32)) / 32768.0


def to_int16(x: np.ndarray) -> np.ndarray:
    return (np.clip(x, -1.0, 1.0) * 32767.0).round().astype("<i2")


def robotic_pcm(pcm: np.ndarray, rate: int) -> np.ndarray:
    """The filter on 16-bit PCM, as the Piper processes produce it."""
    return to_int16(robotic(from_int16(pcm), rate))
