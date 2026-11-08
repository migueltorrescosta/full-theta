"""Colour-blind check of the encodings and the L5 baselines (FT-STN-006).

tools/check_palette.py proves that the palette's roles stay apart under simulated protanopia,
deuteranopia and tritanopia (Machado, Oliveira and Fernandes 2009). This tool adds two things:

1. Letter and shape (static, fast, part of L0): allegiance and alert level must keep a
   distinct letter and a distinct shape each, and every script that tints something with an
   allegiance or alert colour must also draw a shape, an allegiance letter, or tint text
   that carries the callsign (TEXT_CARRIERS); a new colour-only use fails the check.
2. Baselines (slow, run by hand or in tests): for every PNG in tests/visual/baselines it finds
   which palette roles are on screen (pixels within TOLERANCE per channel of the role's
   colour, at least MIN_PIXELS of them) and reports, per simulation, the smallest CIEDE2000
   between two on-screen roles of a group (GROUPS) and, as information, between any two
   on-screen roles that differ by at least APART_DE under normal vision but fall under
   CONFUSED_DE under the simulation. A group pair under MIN_DE00 fails.

Usage:
  check_colourblind.py                    static checks only (L0)
  check_colourblind.py --images [GLOB]    also analyse the baselines (default *.png)
  check_colourblind.py --simulate DIR     also write each analysed image under each simulation
"""

import argparse
import re
import sys
from concurrent.futures import ProcessPoolExecutor
from itertools import combinations
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_palette as cp  # noqa: E402
import l5  # noqa: E402

ROOT = cp.ROOT
BASELINES = ROOT / "tests/visual/baselines"
TOLERANCE = 3  # per channel, 0-255: antialiased edges and blends are not the role's colour
MIN_PIXELS = 12  # fewer pixels than this is not "on screen"
APART_DE = 20.0  # roles this far apart under normal vision are meant to be told apart
CONFUSED_DE = 5.0  # ... and are confusable when a simulation brings them under this

# Scripts that tint with an allegiance or alert colour but are not drawing a shape: the
# tinted text carries the callsign (its first letter is the allegiance) or the alert word.
TEXT_CARRIERS = {
    "stations/science/science_panel.gd": "list rows tinted by allegiance; the row text starts with the callsign",
    "stations/station_screen.gd": "the alert flash; the top bar shows the letter and shape",
    "stations/station_common_actions.gd": "the alert intents set a level; the top bar shows the letter and shape",
    "stations/station_alerts.gd": "the alert flash and tone; the top bar shows the letter and shape",
    "input/intent_table.gd": "intent ids only, no drawing",
    "audio/alert_tones.gd": "tone ids only, no drawing",
}
SHAPE_MARKERS = ("shape_points", "Palette.allegiance(", '["letter"]', "Palette.ALERTS")
COLOUR_USES = re.compile(
    r"Palette\.(allegiance_color|item_color|alert)\(|\"alert_(normal|yellow|red)\"|Palette\.ALERTS"
)


def parse_encodings(text: str) -> tuple[dict[str, str], dict[str, str], list[dict[str, str]]]:
    """Return (allegiance letter -> shape, allegiance letter -> role, alerts) from palette.gd."""

    def block(name: str) -> str:
        m = re.search(rf"^const {name}\b[^=]*=\s*[{{\[](.*?)^[}}\]]", text, re.S | re.M)
        if not m:
            raise ValueError(f"palette: no const {name}")
        return m.group(1)

    pair = re.compile(r'"(\w*)":\s*"(\w+)"')
    shapes = dict(pair.findall(block("ALLEGIANCE_SHAPES")))
    roles = dict(pair.findall(block("ALLEGIANCE_ROLES")))
    alerts = [
        dict(re.findall(r'"(\w+)":\s*"(\w+)"', row)) for row in re.findall(r"\{[^}]*\}", block("ALERTS"))
    ]
    return shapes, roles, alerts


def check_encodings(text: str) -> list[str]:
    """Allegiance and alert level each keep a distinct letter, shape and role."""
    shapes, roles, alerts = parse_encodings(text)
    errors = []
    named = [letter for letter in roles if letter]
    for what, values in (
        ("allegiance shape", [shapes.get(letter) for letter in named]),
        ("allegiance role", [roles[letter] for letter in named]),
        ("alert letter", [a.get("letter") for a in alerts]),
        ("alert shape", [a.get("shape") for a in alerts]),
        ("alert role", [a.get("role") for a in alerts]),
    ):
        if None in values or len(set(values)) != len(values):
            errors.append(f"{what}s are not all present and distinct: {values}")
    if len(named) != 4:
        errors.append(f"allegiance letters {named}: expected the four H, U, F, N")
    return errors


def check_sources(root: Path = ROOT) -> list[str]:
    """Every script that tints by allegiance or alert also encodes it by shape or letter."""
    errors = []
    for path in sorted(root.rglob("*.gd")):
        rel = path.relative_to(root).as_posix()
        if rel.startswith(("tests/", "addons/", "build/", "presentation/palette.gd")):
            continue
        text = path.read_text(encoding="utf-8")
        if not COLOUR_USES.search(text):
            continue
        if rel in TEXT_CARRIERS or any(m in text for m in SHAPE_MARKERS):
            continue
        errors.append(f"{rel}: tints by allegiance or alert with no shape, letter or TEXT_CARRIERS entry")
    return errors


def station_ids(root: Path = ROOT) -> list[str]:
    """The stations and joint views of net/station_views.gd (STATIONS and ENTRIES keys)."""
    text = (root / "net/station_views.gd").read_text(encoding="utf-8")
    ids = []
    for name in ("ENTRIES", "STATIONS"):
        body = re.search(rf"^const {name}\b[^=]*=\s*\{{(.*?)^\}}", text, re.S | re.M)
        if not body:
            raise ValueError(f"station_views: no const {name}")
        ids += re.findall(r'^\t"(\w+)":', body.group(1), re.M)
    return sorted(set(ids))


def check_coverage(names: list[str], ids: list[str]) -> list[str]:
    """Every station and joint view has at least one baseline named for it (l5_<form>_<id>...)."""
    return [
        f"no baseline shows {i}"
        for i in ids
        if not any(re.search(rf"(^|_){i}(_|$)", n) for n in names)
    ]


def simulate_array(rgb: np.ndarray, vision: str) -> np.ndarray:
    """An (h, w, 3) uint8 image as seen with `vision` (same maths as check_palette.simulate)."""
    if vision == "normal":
        return rgb
    c = rgb.astype(np.float64) / 255.0
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    out = np.clip(lin @ np.array(cp.MATRICES[vision]).T, 0.0, 1.0)
    srgb = np.where(out <= 0.0031308, out * 12.92, 1.055 * out ** (1 / 2.4) - 0.055)
    return np.round(srgb * 255.0).astype(np.uint8)


def roles_on_screen(rgb: np.ndarray, roles: dict[str, cp.Rgb]) -> dict[str, int]:
    """Pixel count per role within TOLERANCE of its colour; only roles with MIN_PIXELS or more."""
    flat = rgb.reshape(-1, 3)
    keys = (flat[:, 0].astype(np.uint32) << 16) | (flat[:, 1].astype(np.uint32) << 8) | flat[:, 2]
    uniq, counts = np.unique(keys, return_counts=True)
    colours = np.stack([(uniq >> 16) & 255, (uniq >> 8) & 255, uniq & 255], axis=1).astype(np.int16)
    found = {}
    for name, c in roles.items():
        target = np.array([round(v * 255) for v in c], dtype=np.int16)
        n = int(counts[(np.abs(colours - target) <= TOLERANCE).all(axis=1)].sum())
        if n >= MIN_PIXELS:
            found[name] = n
    return found


def analyse(path: Path) -> dict:
    """The on-screen roles of one baseline and its group and confusion results per vision."""
    roles, groups, _, _ = cp.parse(cp.PALETTE.read_text(encoding="utf-8"))
    w, h, data = l5.read_png(path)
    rgb = np.frombuffer(data, np.uint8).reshape(h, w, 3)
    present = roles_on_screen(rgb, roles)
    result = {"name": path.stem, "roles": present, "groups": {}, "confused": {}}
    for vision in cp.VISIONS:
        seen = {n: cp.simulate(roles[n], vision) for n in present}
        for group, members in groups.items():
            pairs = [(a, b) for a, b in combinations(members, 2) if a in present and b in present]
            if pairs:
                worst = min(pairs, key=lambda p: cp.de2000(cp.lab(seen[p[0]]), cp.lab(seen[p[1]])))
                d = cp.de2000(cp.lab(seen[worst[0]]), cp.lab(seen[worst[1]]))
                result["groups"].setdefault(group, {})[vision] = (d, worst)
        if vision != "normal":
            for a, b in combinations(sorted(present), 2):
                normal = cp.de2000(cp.lab(roles[a]), cp.lab(roles[b]))
                d = cp.de2000(cp.lab(seen[a]), cp.lab(seen[b]))
                if normal >= APART_DE and d < CONFUSED_DE:
                    result["confused"].setdefault(vision, []).append((a, b, normal, d))
    return result


def failures(result: dict) -> list[str]:
    return [
        f"{result['name']}: {group}: {a} vs {b} under {vision}: dE00 {d:.1f} < {cp.MIN_DE00}"
        for group, by_vision in result["groups"].items()
        for vision, (d, (a, b)) in by_vision.items()
        if d < cp.MIN_DE00
    ]


def write_simulations(path: Path, out: Path) -> None:
    w, h, data = l5.read_png(path)
    rgb = np.frombuffer(data, np.uint8).reshape(h, w, 3)
    for vision in cp.MATRICES:
        l5.write_png(out / f"{path.stem}.{vision}.png", w, h, simulate_array(rgb, vision).tobytes())


def _job(args: tuple[Path, Path | None]) -> dict:
    path, out = args
    if out is not None:
        write_simulations(path, out)
    return analyse(path)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    ap.add_argument("--images", nargs="?", const="*.png", metavar="GLOB")
    ap.add_argument("--simulate", type=Path, metavar="DIR")
    ap.add_argument("--verbose", action="store_true", help="print every image's row")
    args = ap.parse_args()
    errors = check_encodings(cp.PALETTE.read_text(encoding="utf-8")) + check_sources()
    if args.images is not None:
        if args.simulate:
            args.simulate.mkdir(parents=True, exist_ok=True)
        paths = sorted(BASELINES.glob(args.images))
        with ProcessPoolExecutor(len(__import__("os").sched_getaffinity(0))) as pool:
            results = list(pool.map(_job, [(p, args.simulate) for p in paths]))
        for r in results:
            errors += failures(r)
            if args.verbose or r["confused"]:
                low = {
                    g: min(v for v, _ in by.values()) for g, by in r["groups"].items()
                }
                print(f"{r['name']}: roles {sorted(r['roles'])} min dE00 by group {low}")
                for vision, rows in r["confused"].items():
                    for a, b, normal, d in rows:
                        print(f"  info: {a} vs {b} under {vision}: {normal:.0f} -> {d:.1f}")
        errors += check_coverage([r["name"] for r in results], station_ids())
        print(f"colourblind: {len(results)} images analysed")
    for e in errors:
        print(f"colourblind: {e}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
