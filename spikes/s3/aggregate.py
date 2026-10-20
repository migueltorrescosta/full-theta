"""Summarise an S3 run directory (spikes/s3/run.sh) as Markdown tables.

Per phase: tick lateness (start minus due time), the part of it spent in HTTP
polls (FT-NET-039), tick duration, the longest HTTP poll, and HTTP throughput.
Also the curl downloads and the 6-browser join from harness multi.
    python3 -I spikes/s3/aggregate.py OUT_DIR
"""

import csv
import json
import sys
from pathlib import Path


def pct(values: list[int], p: float) -> int:
    if not values:
        return 0
    s = sorted(values)
    return s[min(len(s) - 1, int(p * len(s)))]


def phases(out: Path) -> list[tuple[str, int, int]]:
    marks: dict[str, dict[str, int]] = {}
    order: list[str] = []
    for line in (out / "phases.txt").read_text().split("\n"):
        if not line.strip():
            continue
        name, edge, us = line.split()
        if name not in marks:
            order.append(name)
            marks[name] = {}
        marks[name][edge] = int(us)
    return [(n, marks[n]["start"], marks[n]["end"]) for n in order if "end" in marks[n]]


def tick_table(out: Path) -> list[str]:
    rows = list(csv.DictReader((out / "ticks.csv").open()))
    lines = [
        "| Phase | Ticks | Lateness p50 / p99 / max µs | HTTP share p99 / max µs "
        "| Ticks delayed > 1 ms by HTTP | Tick p50 / p99 / max µs | Longest HTTP poll µs "
        "| HTTP MB/s |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for name, start, end in phases(out):
        sel = [r for r in rows if start <= int(r["unix_us"]) <= end]
        late = [int(r["lateness_us"]) for r in sel]
        share = [int(r["http_delay_us"]) for r in sel]
        tick = [int(r["tick_us"]) for r in sel]
        poll = [int(r["http_max_us"]) for r in sel]
        mbs = sum(int(r["http_bytes"]) for r in sel) / max(1e-9, (end - start) / 1e6) / 1e6
        over = sum(1 for v in share if v > 1000)
        lines.append(
            f"| {name} | {len(sel)} | {pct(late, 0.5)} / {pct(late, 0.99)} / {max(late, default=0)} "
            f"| {pct(share, 0.99)} / {max(share, default=0)} | {over} "
            f"| {pct(tick, 0.5)} / {pct(tick, 0.99)} / {max(tick, default=0)} "
            f"| {max(poll, default=0)} | {mbs:.1f} |"
        )
    return lines


def downloads(out: Path) -> list[str]:
    files = sorted(out.glob("dl-*.txt"))
    if not files:
        return []
    count = 0
    total = 0
    wasm_times: list[float] = []
    for f in files:
        for line in f.read_text().split("\n"):
            if not line.strip():
                continue
            size, secs = line.split()
            count += 1
            total += int(size)
            if int(size) > 5_000_000:
                wasm_times.append(float(secs))
    return [
        f"curl: {len(files)} loops, {count} responses, {total / 1e6:.0f} MB; "
        f"gzip wasm ({len(wasm_times)} fetches) took {min(wasm_times, default=0):.2f}–"
        f"{max(wasm_times, default=0):.2f} s each."
    ]


def multi(out: Path) -> list[str]:
    path = out / "multi.json"
    if not path.exists():
        return []
    m = json.loads(path.read_text())
    if "joins" not in m:
        return [f"multi: {m.get('error', 'no result')}"]
    joins = ", ".join(str(j.get("node_ms", j.get("error"))) for j in m["joins"])
    fps = ", ".join(f"{f.get('mean', 0):.0f}" for f in m["fps"])
    return [
        f"6 browsers: join ms {joins} (max {m['join_max_ms']}, mean {m['join_mean_ms']:.0f}); "
        f"mean fps {fps}; errors {len(m['errors'])}."
    ]


def main() -> None:
    out = Path(sys.argv[1])
    print("\n".join(tick_table(out) + [""] + downloads(out) + multi(out)))


if __name__ == "__main__":
    main()
