"""Check the UI palette for colour-blind safety (FT-STN-006).

Parses ROLES, GROUPS and CONTRAST from presentation/palette.gd and checks them
under normal vision and simulated protanopia, deuteranopia and tritanopia
(Machado, Oliveira and Fernandes 2009, severity 1.0, applied in linear RGB with
the sRGB transfer both ways):

- GROUPS: every pair of roles in a group must differ by at least MIN_DE00
  (CIEDE2000). 2.3 is a just-noticeable difference for flat patches; small
  blips and chips on a dark background need far more to be told apart at a
  glance, so 10 is the floor. Colour is never the only code (letters and
  shapes back it, FT-STN-006); this keeps it a useful one.
- CONTRAST: each [foreground, background] pair must keep a WCAG 2 contrast
  ratio of at least MIN_CONTRAST (4.5, AA body text).

Usage: check_palette.py [palette.gd]; exits 1 with one line per failure.
"""

import math
import re
import sys
from itertools import combinations
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PALETTE = ROOT / "presentation/palette.gd"
MIN_DE00 = 10.0
MIN_CONTRAST = 4.5

# Machado et al. 2009, severity 1.0, linear RGB.
MATRICES = {
    "protanopia": (
        (0.152286, 1.052583, -0.204868),
        (0.114503, 0.786281, 0.099216),
        (-0.003882, -0.048116, 1.051998),
    ),
    "deuteranopia": (
        (0.367322, 0.860646, -0.227968),
        (0.280085, 0.672501, 0.047413),
        (-0.011820, 0.042940, 0.968881),
    ),
    "tritanopia": (
        (1.255528, -0.076749, -0.178779),
        (-0.078411, 0.930809, 0.147602),
        (0.004733, 0.691367, 0.303900),
    ),
}
VISIONS = ("normal", *MATRICES)

Rgb = tuple[float, float, float]


def parse(text: str) -> tuple[dict[str, Rgb], dict[str, list[str]], list[tuple[str, str]]]:
    """Return (roles as sRGB 0..1, groups, contrast pairs) from palette.gd source."""

    def block(name: str) -> str:
        m = re.search(rf"^const {name}\b[^=]*=\s*[{{\[](.*?)^[}}\]]", text, re.S | re.M)
        if not m:
            raise ValueError(f"palette: no const {name}")
        return m.group(1)

    roles = {
        name: tuple(int(h[i : i + 2], 16) / 255.0 for i in (0, 2, 4))
        for name, h in re.findall(r'"(\w+)":\s*Color\("#([0-9a-fA-F]{6})"\)', block("ROLES"))
    }
    groups = {
        name: re.findall(r'"(\w+)"', body)
        for name, body in re.findall(r'"(\w+)":\s*\[([^\]]*)\]', block("GROUPS"))
    }
    pairs = [tuple(p) for p in re.findall(r'\[\s*"(\w+)",\s*"(\w+)"\s*\]', block("CONTRAST"))]
    return roles, groups, pairs


def to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def to_srgb(c: float) -> float:
    c = min(1.0, max(0.0, c))
    return c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def simulate(rgb: Rgb, vision: str) -> Rgb:
    """The sRGB colour seen with `vision` ("normal" or a key of MATRICES)."""
    if vision == "normal":
        return rgb
    lin = [to_linear(c) for c in rgb]
    return tuple(to_srgb(sum(row[i] * lin[i] for i in range(3))) for row in MATRICES[vision])


def lab(rgb: Rgb) -> Rgb:
    """CIELAB (D65) of an sRGB colour."""
    r, g, b = (to_linear(c) for c in rgb)
    xyz = (
        (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047,
        (0.2126729 * r + 0.7151522 * g + 0.0721750 * b) / 1.0,
        (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883,
    )
    fx, fy, fz = (t ** (1 / 3) if t > 216 / 24389 else (24389 / 27 * t + 16) / 116 for t in xyz)
    return 116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)


def de2000(lab1: Rgb, lab2: Rgb) -> float:
    """CIEDE2000 colour difference (Sharma, Wu and Dalal 2005), kL = kC = kH = 1."""
    l1, a1, b1 = lab1
    l2, a2, b2 = lab2
    c_bar = (math.hypot(a1, b1) + math.hypot(a2, b2)) / 2
    g = 0.5 * (1 - math.sqrt(c_bar**7 / (c_bar**7 + 25**7)))
    a1p, a2p = a1 * (1 + g), a2 * (1 + g)
    c1p, c2p = math.hypot(a1p, b1), math.hypot(a2p, b2)
    h1p = math.degrees(math.atan2(b1, a1p)) % 360 if c1p else 0.0
    h2p = math.degrees(math.atan2(b2, a2p)) % 360 if c2p else 0.0
    dlp, dcp = l2 - l1, c2p - c1p
    dh = h2p - h1p
    if c1p * c2p == 0:
        dh = 0.0
    elif dh > 180:
        dh -= 360
    elif dh < -180:
        dh += 360
    dhp = 2 * math.sqrt(c1p * c2p) * math.sin(math.radians(dh / 2))
    lp_bar, cp_bar = (l1 + l2) / 2, (c1p + c2p) / 2
    if c1p * c2p == 0:
        hp_bar = h1p + h2p
    elif abs(h1p - h2p) <= 180:
        hp_bar = (h1p + h2p) / 2
    else:
        hp_bar = (h1p + h2p + 360) / 2 if h1p + h2p < 360 else (h1p + h2p - 360) / 2
    t = (
        1
        - 0.17 * math.cos(math.radians(hp_bar - 30))
        + 0.24 * math.cos(math.radians(2 * hp_bar))
        + 0.32 * math.cos(math.radians(3 * hp_bar + 6))
        - 0.20 * math.cos(math.radians(4 * hp_bar - 63))
    )
    sl = 1 + 0.015 * (lp_bar - 50) ** 2 / math.sqrt(20 + (lp_bar - 50) ** 2)
    sc = 1 + 0.045 * cp_bar
    sh = 1 + 0.015 * cp_bar * t
    d_theta = 30 * math.exp(-(((hp_bar - 275) / 25) ** 2))
    rc = 2 * math.sqrt(cp_bar**7 / (cp_bar**7 + 25**7))
    rt = -math.sin(math.radians(2 * d_theta)) * rc
    return math.sqrt(
        (dlp / sl) ** 2 + (dcp / sc) ** 2 + (dhp / sh) ** 2 + rt * (dcp / sc) * (dhp / sh)
    )


def contrast(fg: Rgb, bg: Rgb) -> float:
    """WCAG 2 contrast ratio."""

    def lum(c: Rgb) -> float:
        r, g, b = (to_linear(x) for x in c)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b

    hi, lo = sorted((lum(fg), lum(bg)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)


def check(text: str) -> list[str]:
    """Return one message per failing pair (or unknown role)."""
    roles, groups, pairs = parse(text)
    errors = []
    for name in sorted({r for g in groups.values() for r in g} | {r for p in pairs for r in p}):
        if name not in roles:
            errors.append(f"unknown role {name!r}")
    if errors:
        return errors
    for vision in VISIONS:
        seen = {name: simulate(rgb, vision) for name, rgb in roles.items()}
        for group, members in groups.items():
            for a, b in combinations(members, 2):
                d = de2000(lab(seen[a]), lab(seen[b]))
                if d < MIN_DE00:
                    errors.append(f"{group}: {a} vs {b} under {vision}: dE00 {d:.1f} < {MIN_DE00}")
        for fg, bg in pairs:
            r = contrast(seen[fg], seen[bg])
            if r < MIN_CONTRAST:
                errors.append(f"contrast: {fg} on {bg} under {vision}: {r:.2f} < {MIN_CONTRAST}")
    return errors


def main() -> int:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else PALETTE
    errors = check(path.read_text(encoding="utf-8"))
    for e in errors:
        print(f"palette: {e}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
