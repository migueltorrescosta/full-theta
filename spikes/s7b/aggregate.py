"""Summarise one S7b run directory (server.log, c0.log, c1.log) as Markdown.

    python3 spikes/s7b/aggregate.py OUT_DIR

Event-to-audible latency = client hand-off to AudioStreamWAV minus the server's
sim-event stamp (both unix µs on one host).
"""

import json
import sys
from pathlib import Path


def pct(values: list[float], p: float) -> float:
    s = sorted(values)
    if not s:
        return float("nan")
    k = (len(s) - 1) * p
    lo = int(k)
    hi = min(lo + 1, len(s) - 1)
    return s[lo] + (s[hi] - s[lo]) * (k - lo)


def row(name: str, values: list[float]) -> str:
    return f"| {name} | {len(values)} | {pct(values, 0.5):.0f} | {pct(values, 0.95):.0f} | {max(values):.0f} |"


def server_notes(path: Path) -> list[tuple[str, dict]]:
    notes = []
    for line in path.read_text(encoding="utf-8").splitlines():
        parts = line.split(" ", 2)
        if len(parts) == 3 and parts[2].startswith("{"):
            notes.append((parts[1], json.loads(parts[2])))
    return notes


def clips(path: Path) -> tuple[list[dict], dict]:
    out, summary = [], {}
    if not path.exists():
        return out, summary
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("v,"):
            out.append(json.loads(line[2:]))
        elif line.startswith("x,summary,"):
            summary = json.loads(line.split(",", 3)[3])
    return out, summary


def group(parts: list[dict]) -> list[dict]:
    """One entry per line: audible at the first part with audio; the playback
    gap is how late any later part arrives for gapless playback from there."""
    by_line: dict[str, list[dict]] = {}
    for p in parts:
        by_line.setdefault(p["line"], []).append(p)
    out = []
    for line, ps in by_line.items():
        ps.sort(key=lambda p: p.get("part", 0))
        audio = [p for p in ps if p["audio_ms"] > 0]
        first = audio[0] if audio else ps[0]
        start = first["handoff_us"]
        underrun = 0.0
        at = start
        for p in audio:
            underrun = max(underrun, (p["handoff_us"] - at) / 1000.0)
            at = max(at, p["handoff_us"]) + p["audio_ms"] * 1000
        out.append({
            "line": line, "kind": first["kind"], "voice": first["voice"], "first": first, "all": ps,
            "audible_ms": (start - first["event_us"]) / 1000.0,
            "whole_ms": (ps[-1]["handoff_us"] - first["event_us"]) / 1000.0,
            "underrun_ms": underrun, "audio_ms": sum(p["audio_ms"] for p in ps), "parts": len(audio),
        })
    return out


def main(out_dir: str) -> int:
    d = Path(out_dir)
    run = (d / "run.txt").read_text(encoding="utf-8").strip() if (d / "run.txt").exists() else ""
    notes = server_notes(d / "server.log")
    c0, c0_sum = clips(d / "c0.log")
    c1, c1_sum = clips(d / "c1.log")
    ms = lambda a, b: (a - b) / 1000.0  # noqa: E731
    print(f"# S7b run {d}\n\n{run}\n")
    for name in ("load-before.txt", "load-after.txt"):
        if (d / name).exists():
            print(f"Host load average ({name[5:-4]}): {(d / name).read_text().splitlines()[0]}\n")

    lines = group(c0)
    for kind, title in (("free", "Free text (Piper at runtime)"), ("stitched", "Stitched from the Start cache")):
        rows = [ln for ln in lines if ln["kind"] == kind]
        if not rows:
            continue
        print(f"## {title}: event to audible, ms\n")
        print("Audible = the first part with audio handed to AudioStreamWAV; whole = the last part.\n")
        print("| Set | Lines | p50 | p95 | max |\n|---|---|---|---|---|")
        print(row("audible, all", [ln["audible_ms"] for ln in rows]))
        for key in sorted({ln["voice"] for ln in rows}):
            print(row(f"audible, {key}", [ln["audible_ms"] for ln in rows if ln["voice"] == key]))
        print(row("whole clip delivered", [ln["whole_ms"] for ln in rows]))
        print(row("playback gap (underrun)", [ln["underrun_ms"] for ln in rows]))
        print("\nStages of the first audible part (ms):\n\n| Stage | n | p50 | p95 | max |\n|---|---|---|---|---|")
        stages = [
            ("event to synthesis start (queue)", "started_us", "event_us"),
            ("synthesis start to part ready", "done_us", "started_us"),
            ("part ready to send queue (main loop)", "sent_us", "done_us"),
            ("send queue to first chunk at client", "first_chunk_us", "sent_us"),
            ("send queue to whole part at client", "complete_us", "sent_us"),
            ("whole part to AudioStreamWAV", "handoff_us", "complete_us"),
        ]
        for name, a, b in stages:
            print(row(name, [ms(ln["first"][a], ln["first"][b]) for ln in rows]))
        audio = [ln["audio_ms"] for ln in rows]
        parts = [ln["parts"] for ln in rows]
        print(f"\nAudio per line: {min(audio)}–{max(audio)} ms, mean {sum(audio) / len(audio):.0f} ms; "
              f"parts with audio per line: {min(parts)}–{max(parts)}.")
        errors = [c for ln in rows for c in ln["all"] if c.get("error")]
        if errors:
            print(f"\nErrors: {errors}")
        print()

    print("## Routing\n")
    print(f"- c0 (target): {c0_sum.get('voice', len(c0))} clips, {c0_sum.get('voice_bytes', 0)} B")
    if "frame_us" in c0_sum:
        print(f"- c0 rendered frames (µs between frames): {c0_sum['frame_us']}")
    print(f"- c1 (bystander): {c1_sum.get('voice', len(c1))} clips, {c1_sum.get('voice_bytes', 0)} B\n")

    print("## Start (closed set per language)\n")
    print("| Lang | Items | Synthesis s | Synth bytes | Fragments | Fragment load ms | Cache MB | Total s |")
    print("|---|---|---|---|---|---|---|---|")
    ready = None
    for kind, n in notes:
        if kind == "voices_ready":
            ready = n
        if kind == "start_lang":
            print(
                f"| {n['lang']} | {n['items']} | {n['synth_us'] / 1e6:.2f} | {n['synth_bytes']} | "
                f"{n['fragments']} | {n['fragment_load_us'] / 1e3:.0f} | {n['cache_bytes'] / 1e6:.1f} | "
                f"{n['total_us'] / 1e6:.2f} |"
            )
    if ready:
        loads = ", ".join(f"{k} {v / 1e6:.2f} s" for k, v in ready["load_us"].items())
        print(f"\nVoices ready after {ready['wall_us'] / 1e6:.2f} s (load and warm-up per process: {loads}).\n")

    print("## Server loop\n")
    for kind, n in notes:
        if kind == "summary":
            print(f"- sim tick (S6 world + S4 stub), µs: {n['sim_us']}")
            print(f"- frame work, µs: {n['frame_work_us']}")
            print(f"- per client: {n['clients']}")
    stats = [n for k, n in notes if k == "stats"]
    if stats:
        busy = [s for s in stats if s["synth_pending"] > 0]
        late = max(s["late_max_us"] for s in stats)
        print(f"- worst frame work in any second: {max(s['work_max_us'] for s in stats)} µs; "
              f"while synthesis was pending: {max((s['work_max_us'] for s in busy), default=0)} µs")
        print(f"- worst tick lateness: {late} µs")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
