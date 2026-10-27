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
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import numpy as np

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
CAPTURE_TIMEOUT = 600  # seconds for the Godot runs over all shots
JOBS = len(os.sched_getaffinity(0))  # processes decoding and diffing PNGs
PARTS = int(os.environ.get("L5_PARTS", "4"))  # Godot processes rendering the shots
SHOTS_PER_PART = 10
# Runs "$@" --part k/N for k in 0..N-1 at once ($1 = N); fails if any part fails.
PARALLEL = 'n=$1; shift; for ((k = 0; k < n; k++)); do "$@" --part "$k/$n" & done; rc=0; '
PARALLEL += "for ((k = 0; k < n; k++)); do wait -n || rc=1; done; exit $rc"


def read_png(path: Path) -> tuple[int, int, bytes]:
    """Decode an 8-bit, non-interlaced RGB PNG to (width, height, RGB bytes)."""
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path}: not a PNG")
    pos, idat = 8, []
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos : pos + 8])
        body = data[pos + 8 : pos + 8 + length]
        if kind == b"IHDR":
            width, height, depth, colour, _, _, interlace = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat.append(body)
        pos += 12 + length
    if depth != 8 or colour != 2 or interlace:
        raise ValueError(f"{path}: only 8-bit non-interlaced RGB PNGs are supported")
    stride = width * 3
    raw = np.frombuffer(zlib.decompress(b"".join(idat)), np.uint8).reshape(height, stride + 1)
    out = np.empty((height, stride), np.uint8)
    prev = np.zeros(stride, np.uint8)
    for y in range(height):
        f, line = raw[y, 0], raw[y, 1:]
        if f == 0:
            out[y] = line
        elif f == 1:  # Sub: a running sum along the row, per channel (uint8 wraps)
            out[y] = np.cumsum(line.reshape(width, 3), axis=0, dtype=np.uint8).reshape(stride)
        elif f == 2:  # Up
            out[y] = line + prev
        else:
            out[y] = np.frombuffer(unfilter_sequential(f, line.tobytes(), prev.tobytes()), np.uint8)
        prev = out[y]
    return width, height, out.tobytes()


def unfilter_sequential(f: int, line: bytes, prev: bytes) -> bytes:
    """Undo an Average (3) or Paeth (4) row filter: each byte needs the one decoded before it."""
    row = bytearray(line)
    for x in range(3):  # no left neighbour: Average halves the byte above, Paeth picks it
        row[x] = (row[x] + (prev[x] >> 1 if f == 3 else prev[x])) & 255
    if f == 3:
        for x in range(3, len(row)):
            row[x] = (row[x] + ((row[x - 3] + prev[x]) >> 1)) & 255
        return bytes(row)
    for x in range(3, len(row)):
        a, b, c = row[x - 3], prev[x], prev[x - 3]
        p = a + b - c
        pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
        row[x] = (row[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
    return bytes(row)


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
    pa = np.frombuffer(a, np.uint8).reshape(-1, 3).astype(np.int16)
    pb = np.frombuffer(b, np.uint8).reshape(-1, 3).astype(np.int16)
    d = np.abs(pa - pb).max(axis=1)
    over = d > THRESHOLD
    mask = np.zeros((len(d), 3), np.uint8)
    mask[over, 0] = 255
    return int(over.sum()), int(d.max(initial=0)), bytearray(mask.tobytes())


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
    with ProcessPoolExecutor(JOBS) as pool:
        results = pool.map(compare_shot, [baselines] * len(names), [out] * len(names), names)
    for name, (error, stat) in zip(names, results):
        if stat:
            stats[name] = stat
        if error:
            errors.append(error)
    return errors, stats


def compare_shot(baselines: Path, out: Path, name: str) -> tuple[str, dict]:
    """Diff one shot against its baseline: (error or '', stats or {})."""
    base_png = baselines / f"{name}.png"
    if not base_png.exists():
        return f"{name}: no baseline; run with --update-baselines", {}
    bw, bh, base = read_png(base_png)
    w, h, shot = read_png(out / f"{name}.png")
    if (w, h) != (bw, bh):
        return f"{name}: size {w}x{h}, baseline {bw}x{bh}", {}
    count, worst, mask = diff(base, shot)
    fraction = count / (w * h)
    stat = {"differing": count, "fraction": fraction, "max_delta": worst}
    if fraction <= MAX_FRACTION:
        return "", stat
    write_png(out / f"{name}.diff.png", w, h, bytes(mask))
    return (
        f"{name}: {count} pixels differ by more than {THRESHOLD} "
        f"({fraction:.3%}, limit {MAX_FRACTION:.3%}), max difference {worst}; "
        f"see {show(out / f'{name}.diff.png')}"
    ), stat


def show(path: Path) -> str:
    """Path relative to the repo root when inside it."""
    return str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path)


def blank(rgb: bytes) -> bool:
    """True when every pixel has the same colour."""
    return rgb == rgb[:3] * (len(rgb) // 3)


def shot_size(manifest: dict, shot: dict) -> list[int]:
    """A shot's [width, height]: its own "size", else the manifest's."""
    return shot.get("size", manifest["size"])


def check_render(png: Path, size: tuple[int, int]) -> str:
    """'' when a render has its shot's size and is not blank, else the problem."""
    w, h, rgb = read_png(png)
    if (w, h) != size:
        return f"rendered {w}x{h}, expected {size[0]}x{size[1]}"
    return "blank image" if blank(rgb) else ""


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
    stale += [p.name for p in out.glob("timings.*.json")]
    for name in stale:
        (out / name).unlink(missing_ok=True)
    if not manifest["shots"]:
        return ["no shots in the manifest"]
    got = subprocess.run([ROOT / "tools/get-godot.sh"], capture_output=True, text=True)
    if got.returncode != 0:
        return [f"get-godot.sh failed: {got.stderr.strip()}"]
    godot = got.stdout.strip()
    env = dict(os.environ, LIBGL_ALWAYS_SOFTWARE="1", GALLIUM_DRIVER="llvmpipe")
    render = [
        godot, "--path", str(ROOT), "--rendering-driver", "opengl3",
        "--resolution", f"{width}x{height}", "--position", "0,0",
        "-s", "res://tools/l5_capture.gd", "--", "--shots", str(shots_file), "--out", str(out),
    ]  # fmt: skip
    # Up to PARTS Godot processes share one X server, each rendering every parts-th shot;
    # each renders at least SHOTS_PER_PART shots, worth its start-up.
    parts = max(1, min(PARTS, len(manifest["shots"]) // SHOTS_PER_PART))
    if parts > 1:
        render = ["bash", "-c", PARALLEL, "l5", str(parts), *render]
    cmd = ["xvfb-run", "-a", f"--server-args=-screen 0 {width}x{height}x24", *render]
    try:
        run = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=CAPTURE_TIMEOUT)
    except subprocess.TimeoutExpired:
        return [f"capture timed out after {CAPTURE_TIMEOUT} s"]
    if run.returncode != 0 or not (out / "env.json").exists():
        return [f"capture failed (exit {run.returncode}):\n{run.stdout}{run.stderr}"]
    if parts > 1:
        timings = {}
        for k in range(parts):
            part = out / f"timings.{k}.json"
            timings.update(json.loads(part.read_text()))
            part.unlink()
        ordered = {s["name"]: timings[s["name"]] for s in manifest["shots"] if s["name"] in timings}
        (out / "timings.json").write_text(json.dumps(ordered, indent=2) + "\n")
    errors = []
    renderer = json.loads((out / "env.json").read_text())["renderer"]
    if "llvmpipe" not in renderer:
        errors.append(f"renderer is {renderer!r}, not llvmpipe")
    names = [s["name"] for s in manifest["shots"]]
    with ProcessPoolExecutor(JOBS) as pool:
        checked = pool.map(check_render, [out / f"{n}.png" for n in names], [sizes[n] for n in names])
    errors += [f"{name}: {e}" for name, e in zip(names, checked) if e]
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
