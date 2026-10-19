"""L5 visual gate: screenshots under Xvfb with llvmpipe, diffed against baselines.

Renders every shot in tests/visual/shots.json with tools/l5_capture.gd (Godot,
Compatibility renderer, software GL under xvfb-run) into build/l5/, then
compares each PNG with tests/visual/baselines/<name>.png (FT-TST-003).

A pixel differs when any channel differs by more than THRESHOLD; a shot fails
when more than MAX_FRACTION of its pixels differ. Failing shots leave a
<name>.diff.png in build/l5/ (differing pixels in red).

baselines/env.json records the renderer (llvmpipe and LLVM version), GL
version (Mesa version) and engine the baselines were made with. When the
capture's environment differs, L5 fails with "baseline environment changed"
before any pixel diff (FT-TST-020): regenerate only after checking the diffs.

Usage (tools/gate.sh l5 [--update-baselines] runs the first two):
  l5.py                       check the shots against the baselines
  l5.py --update-baselines    regenerate tests/visual/baselines/
  l5.py --capture-only DIR    render into DIR, compare nothing
  --shots FILE                another shot manifest (default tests/visual/shots.json)

Each shot renders at the manifest's "size" [w, h] unless it gives its own "size".
"""

import argparse
import json
import os
import shutil
import struct
import subprocess
import sys
import time
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHOTS = ROOT / "tests/visual/shots.json"
BASELINES = ROOT / "tests/visual/baselines"
OUT = ROOT / "build/l5"
THRESHOLD = 8  # per-channel difference (0-255) above which a pixel differs
MAX_FRACTION = 0.0001  # fraction of differing pixels a shot may have (23 at 640x360)
ENV_KEYS = ("renderer", "gl_version", "godot")
ENV_HINT = (
    " (compare the renders in build/l5/ with the baselines by eye before"
    " regenerating them with --update-baselines)"
)
CAPTURE_TIMEOUT = 300  # seconds for one Godot run over all shots


def read_png(path: Path) -> tuple[int, int, bytes]:
    """Decode an 8-bit, non-interlaced RGB PNG to (width, height, RGB bytes)."""
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path}: not a PNG")
    pos, idat = 8, b""
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos : pos + 8])
        body = data[pos + 8 : pos + 8 + length]
        if kind == b"IHDR":
            width, height, depth, colour, _, _, interlace = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
        pos += 12 + length
    if depth != 8 or colour != 2 or interlace:
        raise ValueError(f"{path}: only 8-bit non-interlaced RGB PNGs are supported")
    bpp = 3
    stride = width * bpp
    raw = zlib.decompress(idat)
    out = bytearray(height * stride)
    prev = bytearray(stride)
    for y in range(height):
        f = raw[y * (stride + 1)]
        line = bytearray(raw[y * (stride + 1) + 1 : (y + 1) * (stride + 1)])
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if f == 1:
                line[x] = (line[x] + a) & 255
            elif f == 2:
                line[x] = (line[x] + b) & 255
            elif f == 3:
                line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if pa <= pb and pa <= pc else b if pb <= pc else c
                line[x] = (line[x] + pred) & 255
        out[y * stride : (y + 1) * stride] = line
        prev = line
    return width, height, bytes(out)


def write_png(path: Path, width: int, height: int, rgb: bytes) -> None:
    """Write RGB bytes as an 8-bit PNG (filter 0 on every row)."""
    rows = b"".join(b"\0" + rgb[y * width * 3 : (y + 1) * width * 3] for y in range(height))

    def chunk(kind: bytes, body: bytes) -> bytes:
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    png = chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + png)


def diff(a: bytes, b: bytes) -> tuple[int, int, bytearray]:
    """Return (pixels over THRESHOLD, max channel difference, diff mask as RGB)."""
    count, worst = 0, 0
    mask = bytearray(len(a))
    for i in range(0, len(a), 3):
        d = max(abs(a[i] - b[i]), abs(a[i + 1] - b[i + 1]), abs(a[i + 2] - b[i + 2]))
        worst = max(worst, d)
        if d > THRESHOLD:
            count += 1
            mask[i] = 255
    return count, worst, mask


def env_changes(baseline: dict, current: dict) -> list[str]:
    """Return the environment keys whose value differs, as 'key: old -> new' lines."""
    return [
        f"{k}: {baseline.get(k)!r} -> {current.get(k)!r}"
        for k in ENV_KEYS
        if baseline.get(k) != current.get(k)
    ]


def compare(baselines: Path, out: Path, names: list[str]) -> tuple[list[str], dict]:
    """Check out/ against baselines/; return (errors, per-shot stats)."""
    env_file = baselines / "env.json"
    if not env_file.exists():
        return [f"no {show(env_file)}; run with --update-baselines"], {}
    changed = env_changes(json.loads(env_file.read_text()), json.loads((out / "env.json").read_text()))
    if changed:
        return ["baseline environment changed: " + "; ".join(changed) + ENV_HINT], {}
    errors, stats = [], {}
    for name in names:
        base_png = baselines / f"{name}.png"
        if not base_png.exists():
            errors.append(f"{name}: no baseline; run with --update-baselines")
            continue
        bw, bh, base = read_png(base_png)
        w, h, shot = read_png(out / f"{name}.png")
        if (w, h) != (bw, bh):
            errors.append(f"{name}: size {w}x{h}, baseline {bw}x{bh}")
            continue
        count, worst, mask = diff(base, shot)
        fraction = count / (w * h)
        stats[name] = {"differing": count, "fraction": fraction, "max_delta": worst}
        if fraction > MAX_FRACTION:
            write_png(out / f"{name}.diff.png", w, h, bytes(mask))
            errors.append(
                f"{name}: {count} pixels differ by more than {THRESHOLD} "
                f"({fraction:.3%}, limit {MAX_FRACTION:.3%}), max difference {worst}; "
                f"see {show(out / f'{name}.diff.png')}"
            )
    return errors, stats


def show(path: Path) -> str:
    """Path relative to the repo root when inside it."""
    return str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path)


def blank(rgb: bytes) -> bool:
    """True when every pixel has the same colour."""
    return rgb == rgb[:3] * (len(rgb) // 3)


def shot_size(manifest: dict, shot: dict) -> list[int]:
    """A shot's [width, height]: its own "size", else the manifest's."""
    return shot.get("size", manifest["size"])


def capture(shots_file: Path, out: Path) -> list[str]:
    """Render every shot into out/ under Xvfb with llvmpipe; return errors."""
    manifest = json.loads(shots_file.read_text())
    sizes = {s["name"]: tuple(shot_size(manifest, s)) for s in manifest["shots"]}
    # The X screen and window start at the largest size; the capture sizes each shot.
    width = max((w for w, _ in sizes.values()), default=manifest["size"][0])
    height = max((h for _, h in sizes.values()), default=manifest["size"][1])
    if not shutil.which("xvfb-run"):
        return ["xvfb-run not found; install the xvfb package"]
    out.mkdir(parents=True, exist_ok=True)
    stale = ["env.json", "timings.json"]
    stale += [f"{s['name']}{ext}" for s in manifest["shots"] for ext in (".png", ".diff.png")]
    for name in stale:
        (out / name).unlink(missing_ok=True)
    if not manifest["shots"]:
        return ["no shots in the manifest"]
    got = subprocess.run([ROOT / "tools/get-godot.sh"], capture_output=True, text=True)
    if got.returncode != 0:
        return [f"get-godot.sh failed: {got.stderr.strip()}"]
    godot = got.stdout.strip()
    env = dict(os.environ, LIBGL_ALWAYS_SOFTWARE="1", GALLIUM_DRIVER="llvmpipe")
    cmd = [
        "xvfb-run", "-a", f"--server-args=-screen 0 {width}x{height}x24",
        godot, "--path", str(ROOT), "--rendering-driver", "opengl3",
        "--resolution", f"{width}x{height}", "--position", "0,0",
        "-s", "res://tools/l5_capture.gd", "--", "--shots", str(shots_file), "--out", str(out),
    ]  # fmt: skip
    try:
        run = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=CAPTURE_TIMEOUT)
    except subprocess.TimeoutExpired:
        return [f"capture timed out after {CAPTURE_TIMEOUT} s"]
    if run.returncode != 0 or not (out / "env.json").exists():
        return [f"capture failed (exit {run.returncode}):\n{run.stdout}{run.stderr}"]
    errors = []
    renderer = json.loads((out / "env.json").read_text())["renderer"]
    if "llvmpipe" not in renderer:
        errors.append(f"renderer is {renderer!r}, not llvmpipe")
    for shot in manifest["shots"]:
        w, h, rgb = read_png(out / f"{shot['name']}.png")
        want_w, want_h = sizes[shot["name"]]
        if (w, h) != (want_w, want_h):
            errors.append(f"{shot['name']}: rendered {w}x{h}, expected {want_w}x{want_h}")
        elif blank(rgb):
            errors.append(f"{shot['name']}: blank image")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--update-baselines", action="store_true")
    mode.add_argument("--capture-only", type=Path, metavar="DIR")
    parser.add_argument("--shots", type=Path, default=SHOTS)
    args = parser.parse_args()
    shots_file = args.shots.resolve()
    out = args.capture_only.resolve() if args.capture_only else OUT
    names = [s["name"] for s in json.loads(shots_file.read_text())["shots"]]

    start = time.monotonic()
    errors = capture(shots_file, out)
    elapsed = time.monotonic() - start
    timings = json.loads((out / "timings.json").read_text()) if not errors else {}
    print(f"l5: rendered {len(names)} shots in {elapsed:.1f} s ({timings})")
    if not errors and args.update_baselines:
        BASELINES.mkdir(parents=True, exist_ok=True)
        for name in names:
            shutil.copy(out / f"{name}.png", BASELINES / f"{name}.png")
        shutil.copy(out / "env.json", BASELINES / "env.json")
        print(f"l5: wrote {len(names)} baselines and env.json to {show(BASELINES)}")
        for stale in sorted(set(p.stem for p in BASELINES.glob("*.png")) - set(names)):
            print(f"l5: {stale}.png is not in the manifest; delete it if the shot is gone")
    elif not errors and not args.capture_only:
        errors, stats = compare(BASELINES, out, names)
        for name, s in stats.items():
            print(f"l5: {name}: {s['differing']} differing pixels, max difference {s['max_delta']}")
    sys.stdout.flush()
    for e in errors:
        print(f"l5: {e}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
