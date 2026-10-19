"""Summarise one voice latency run directory (server.log, c0.log, c1.log) as Markdown.

    python3 tools/voice_latency/aggregate.py OUT_DIR

Event-to-audible (FT-AUD-015, the S7b method) = c0's hand-off of the line's first part
with audio to an AudioStreamWAV minus the server's event stamp, both unix µs on one
host. The playback gap is how late any later part arrives for gapless playback from
that moment.
"""

import json
import statistics
import sys
from pathlib import Path


def pct(values: list[float], p: float) -> float:
    if len(values) < 2:
        return values[0] if values else float("nan")
    return statistics.quantiles(values, n=100, method="inclusive")[round(p * 100) - 1]


def row(name: str, values: list[float]) -> str:
    if not values:
        return f"| {name} | 0 | | | |"
    return f"| {name} | {len(values)} | {pct(values, 0.5):.0f} | {pct(values, 0.95):.0f} | {max(values):.0f} |"


def read_log(path: Path) -> list[dict]:
    if not path.exists():
        return []
    return [json.loads(ln) for ln in path.read_text(encoding="utf-8").splitlines() if ln.startswith("{")]


def lines_of(server: list[dict], client: list[dict]) -> list[dict]:
    parts: dict[int, list[dict]] = {}
    events = {e["clip"]: e for e in client if e["ev"] == "line"}
    for v in client:
        if v["ev"] == "voice":
            parts.setdefault(v["clip"], []).append(v)
    out = []
    for ln in (e for e in server if e["ev"] == "line"):
        ps = sorted(parts.get(ln["clip"], []), key=lambda p: p["part"])
        audio = [p for p in ps if p["bytes"] > 0]
        event = events.get(ln["clip"], {})
        entry = dict(ln, parts=len(audio), audio_ms=sum(p["audio_ms"] for p in ps), audio=event.get("audio"))
        if audio:
            start = audio[0]["handoff_us"]
            gap, at = 0.0, start
            for p in audio:
                gap = max(gap, (p["handoff_us"] - at) / 1000.0)
                at = max(at, p["handoff_us"]) + p["audio_ms"] * 1000
            entry.update(
                audible_ms=(start - ln["event_us"]) / 1000.0,
                arrival_ms=(audio[0]["arrival_us"] - ln["event_us"]) / 1000.0,
                whole_ms=(ps[-1]["handoff_us"] - ln["event_us"]) / 1000.0,
                gap_ms=gap,
                complete=bool(ps[-1]["last"]),
            )
        out.append(entry)
    return out


def main(out_dir: str) -> int:
    d = Path(out_dir)
    server = read_log(d / "server.log")
    c0 = read_log(d / "c0.log")
    c1 = read_log(d / "c1.log")
    run = (d / "run.txt").read_text(encoding="utf-8").strip() if (d / "run.txt").exists() else ""
    print(f"# Voice latency run {d}\n\n{run}\n")
    for name in ("load-before.txt", "load-after.txt"):
        if (d / name).exists():
            avg = (d / name).read_text().split()[:3]
            print(f"- Host load average {name[5:-4]} (1/5/15 min): {' / '.join(avg)}")
    listening = next((e for e in server if e["ev"] == "listening"), {})
    print(f"- Adapter: {listening.get('adapter', '?')}; sim load {listening.get('sim_ships')} ships, "
          f"{listening.get('sim_proj')} projectiles\n")

    lines = lines_of(server, c0)
    for kind, title in (("free", "Free text (say_free, Piper at runtime)"), ("stitched", "Stitched (say, Start cache)")):
        rows = [ln for ln in lines if ln["kind"] == kind]
        if not rows:
            continue
        heard = [ln for ln in rows if "audible_ms" in ln]
        print(f"## {title}: event to audible, ms\n")
        print("| Set | Lines | p50 | p95 | max |\n|---|---|---|---|---|")
        print(row("audible, all", [ln["audible_ms"] for ln in heard]))
        for lang in sorted({ln["lang"] for ln in heard}):
            print(row(f"audible, {lang}", [ln["audible_ms"] for ln in heard if ln["lang"] == lang]))
        print(row("first part complete at c0", [ln["arrival_ms"] for ln in heard]))
        print(row("whole clip handed off", [ln["whole_ms"] for ln in heard]))
        print(row("playback gap", [ln["gap_ms"] for ln in heard]))
        subtitles = [ln["id"] for ln in rows if ln["audio"] is False]
        missing = [ln["id"] for ln in rows if "audible_ms" not in ln and ln["audio"] is not False]
        partial = [ln["id"] for ln in heard if not ln["complete"]]
        audio = [ln["audio_ms"] for ln in heard] or [0]
        print(f"\nLines {len(rows)}, audible {len(heard)}; audio per line {min(audio):.0f}–{max(audio):.0f} ms; "
              f"parts per line {min((ln['parts'] for ln in heard), default=0)}–"
              f"{max((ln['parts'] for ln in heard), default=0)}; "
              f"lines with a gap: {sum(1 for ln in heard if ln['gap_ms'] > 0)}.")
        if subtitles:
            print(f"\nSubtitles only (audio false; D110 beyond 4 queued free-text lines): {len(subtitles)}, {subtitles}")
        if missing:
            print(f"\nNo audio arrived: {missing}")
        if partial:
            print(f"\nNo last part: {partial}")
        print()

    print("## Routing\n")
    for name, log in (("c0 (target)", c0), ("c1 (bystander)", c1)):
        s = next((e for e in log if e["ev"] == "summary"), {})
        print(f"- {name}: {s.get('voice', '?')} voice parts, {s.get('voice_bytes', '?')} B, {s.get('events', '?')} events")
    print()

    print("## Start (closed set per language)\n\n| Lang | Start ms | Wall ms | Voices |\n|---|---|---|---|")
    for e in server:
        if e["ev"] == "start_lang":
            voices = ", ".join(r for r in ("computer", "npc") if e[r]) or "none"
            print(f"| {e['lang']} | {e['start_ms']} | {e['wall_ms']} | {voices} |")
    print()
    before: dict = {}
    for e in server:
        if e["ev"] == "lang_done":
            delta = {k: v - before.get(k, 0) for k, v in e["stats"].items()}
            before = e["stats"]
            print(f"- {e['lang']} done ({e['why']}): {delta}")
    summary = next((e for e in server if e["ev"] == "summary"), None)
    if summary:
        print(f"\n## Server loop\n\n- S7b sim load step per tick, µs: {summary['sim_us']}")
        print(f"- frame interval, µs: {summary['frame_us']}")
        print(f"- NetServer tick max, µs: {summary['net_tick_us_max']}")
    errors = [e for e in server if e["ev"] == "error"]
    if errors:
        print(f"\nErrors: {errors}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
