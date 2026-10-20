"""Summarise one S9 run directory (server.log and p*.log) as Markdown.

python3 spikes/s9/aggregate.py OUT_DIR

Snapshot age = client receive time minus server build stamp, both unix
wall-clock microseconds on the same host, over the server's measured window.
Bytes per client are payload bytes the server handed to the WebSocket
(chunk header plus snapshot), without WebSocket, TCP and IP headers; the
namespace's loopback counters give the wire total.
"""

import json
import sys
from collections import defaultdict
from pathlib import Path


def pct(values, p):
    if not values:
        return float("nan")
    s = sorted(values)
    return s[min(len(s) - 1, int(p / 100 * len(s)))]


def main(out):
    out = Path(out)
    notes = {}
    for line in (out / "server.log").read_text().splitlines():
        us, kind, data = line.split(" ", 2)
        notes[kind] = (int(us), json.loads(data))
    if "summary" not in notes:
        print(f"# S9 run {out.name}: no summary in server.log")
        return 1
    end_us, s = notes["summary"]
    start_us = s["measure_start_us"]
    secs = s["seconds"]
    ages, sizes, fulls = [], [], 0
    per_conn = {}
    failures = 0
    client_cpu, client_wall = 0.0, 0.0
    for path in sorted(out.glob("p*.log")):
        for line in path.read_text().splitlines():
            if line.startswith("s,"):
                _, conn, seq, full, sent, recv, size = line.split(",")
                sent, recv = int(sent), int(recv)
                if start_us <= sent <= end_us:
                    ages.append((recv - sent) / 1000)
                    sizes.append(int(size))
                    fulls += int(full)
                    per_conn.setdefault((path.stem, conn), []).append((recv - sent) / 1000)
            elif line.startswith("x,"):
                _, conn, kind, _, data = line.split(",", 4)
                d = json.loads(data)
                if kind == "cpu":
                    client_cpu += d["cpu_s"]
                    client_wall = max(client_wall, d["wall_s"])
                    continue
                failures += d.get("decode_failures", 0) + d.get("out_of_order", 0)
    tf, sf = s["tick_frames"], s["snapshot_frames"]
    print(f"# S9 run {out.name}\n")
    print(f"{s['clients']} clients, {secs:.1f} s measured, {s['snapshots']} snapshots.\n")
    print("| Server | mean ms | p50 ms | p99 ms | max ms | frames |")
    print("|---|---|---|---|---|---|")
    rows = [("tick frames", tf), ("snapshot frames", sf)]
    if s.get("tick_frames_oncpu"):
        rows += [
            ("tick frames, on CPU", s["tick_frames_oncpu"]),
            ("tick frames, preempted", s["tick_frames_wait"]),
        ]
    for name, d in rows:
        print(
            f"| {name} | {d['mean_us'] / 1000:.2f} | {d['p50_us'] / 1000:.2f} | "
            f"{d['p99_us'] / 1000:.2f} | {d['max_us'] / 1000:.2f} | {d['n']} |"
        )
    b = s["build_us_per_snapshot"]
    print(
        f"\nMean per tick frame: sim {s['sim_mean_us'] / 1000:.2f} ms, snapshot "
        f"{s['snap_mean_us'] / 1000:.2f} ms, pump {s['pump_mean_us'] / 1000:.2f} ms, "
        f"poll {s['poll_mean_us'] / 1000:.2f} ms. Build per snapshot (ms): "
        + ", ".join(f"{k} {v / 1000:.3f}" for k, v in b.items())
        + "."
    )
    print(
        f"\nCPU {s['cpu_s']:.1f} s = {s['cpu_pct_of_2_cores']:.1f} % of 2 cores. "
        f"Per snapshot: {s['section_encodes_per_snapshot']:.1f} section encodes, "
        f"{s['delta_messages_per_snapshot']:.1f} view-key messages, "
        f"{s['sends_per_snapshot']:.1f} sends; {s['full_messages']} full messages."
    )
    print(
        f"\nSnapshot age over {len(ages)} snapshots: p50 {pct(ages, 50):.1f} ms, "
        f"p99 {pct(ages, 99):.1f} ms, max {max(ages):.1f} ms; "
        f"worst per-connection p99 {max(pct(v, 99) for v in per_conn.values()):.1f} ms; "
        f"{fulls} full snapshots; {failures} decode failures."
    )
    roles = defaultdict(list)
    for c in s["per_client"]:
        role = "viewer" if c["entry"] == "viewer" else c["entry"]
        roles[role].append(c["bytes"] / secs)
    print("\n| Role | clients | payload B/s per client (mean) | min | max |")
    print("|---|---|---|---|---|")
    for role, v in sorted(roles.items()):
        print(f"| {role} | {len(v)} | {sum(v) / len(v):.0f} | {min(v):.0f} | {max(v):.0f} |")
    allc = [c["bytes"] / secs for c in s["per_client"]]
    print(f"| all | {len(allc)} | {sum(allc) / len(allc):.0f} | {min(allc):.0f} | {max(allc):.0f} |")
    wire = ""
    if s["lo_bytes"] > 0:
        wire = (
            f"; loopback wire total (both directions, all headers) "
            f"{s['lo_bytes'] * 8 / secs / 1e6:.2f} Mbit/s in {s['lo_packets'] / secs:.0f} packets/s"
        )
    print(f"\nPayload total {s['payload_mbit_s']:.2f} Mbit/s{wire}.")
    if client_wall:
        print(
            f"\nClient processes: {client_cpu:.1f} s CPU over {client_wall:.0f} s "
            f"= {100 * client_cpu / client_wall / 2:.1f} % of their 2 CPUs."
        )
    stalls = sum(c["stalls"] for c in s["per_client"])
    print(f"\nStalls {stalls}, skipped {sum(c['skipped'] for c in s['per_client'])}.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
