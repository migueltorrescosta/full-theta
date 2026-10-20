"""Summarise one S4 run directory (server.log and c*.log) as Markdown.

python3 spikes/s4/aggregate.py OUT_DIR

Snapshot age = client receive time minus server send stamp, both unix wall-clock
microseconds on the same host. The stalled client's backlog (from the stall's
start until its recovery full snapshot) is reported apart from the steady state.
"""

import json
import sys
from pathlib import Path


def pct(values, p):
    if not values:
        return float("nan")
    s = sorted(values)
    return s[min(len(s) - 1, int(round(p / 100 * (len(s) - 1))))]


def parse_client(path):
    snaps, events, chunks, marks = [], [], [], {}
    for line in path.read_text().splitlines():
        parts = line.split(",", 3)
        if parts[0] == "s":
            seq, full, sent, recv, size = map(int, line.split(",")[1:])
            snaps.append((seq, full, sent, recv, size))
        elif parts[0] == "e":
            _, seq, recv, via = line.split(",")
            events.append((int(seq), int(recv), via))
        elif parts[0] == "k":
            chunks.append(tuple(map(int, line.split(",")[1:])))
        elif parts[0] == "x":
            marks[parts[1]] = (int(parts[2]), json.loads(parts[3]))
    return snaps, events, chunks, marks


def parse_server(path):
    notes = []
    for line in path.read_text().splitlines():
        us, kind, data = line.split(" ", 2)
        notes.append((int(us), kind, json.loads(data)))
    return notes


def ms(us):
    return f"{us / 1000:.1f}"


def main(out):
    out = Path(out)
    server = parse_server(out / "server.log")
    clients = {p.stem: parse_client(p) for p in sorted(out.glob("c*.log"))}
    print(f"# S4 run {out.name}\n")
    steady, rows = [], []
    for name, (snaps, events, _, marks) in clients.items():
        lo, hi = None, None
        if "stall_start" in marks:
            lo = marks["stall_start"][0]
            hi = marks.get("stall_recovered", (lo,))[0]
        ages = [r - s for _, _, s, r, _ in snaps if not (lo and lo <= r <= hi)]
        steady += ages
        deltas = [z for _, f, _, _, z in snaps if not f]
        rows.append(
            f"| {name} | {len(ages)} | {ms(pct(ages, 50))} | {ms(pct(ages, 99))} "
            f"| {ms(max(ages) if ages else 0)} | {sum(deltas) // max(1, len(deltas))} |"
        )
    print("## Snapshot age (ms), stalled backlog excluded\n")
    print("| Client | Snapshots | p50 | p99 | max | mean delta bytes |")
    print("|---|---|---|---|---|---|")
    print("\n".join(rows))
    print(
        f"| all | {len(steady)} | {ms(pct(steady, 50))} | {ms(pct(steady, 99))} "
        f"| {ms(max(steady))} | |\n"
    )

    summary = next((d for _, k, d in server if k == "summary"), {})
    stats = [d for _, k, d in server if k == "stats"]
    work = [d["work_max_us"] for d in stats]
    print("## Server\n")
    print(
        f"snapshots {summary.get('snapshots')}, events {summary.get('events')}, "
        f"full snapshot {summary.get('full_bytes')} B, mean delta "
        f"{summary.get('delta_mean_bytes')} B, delta sends {summary.get('delta_sends')}, "
        f"delta encodes {summary.get('delta_encodes')}; frame work max {max(work, default=0)} µs "
        f"(per-second maxima p50 {pct(work, 50)} µs)\n"
    )
    for name, c in summary.get("clients", {}).items():
        print(f"- {name}: {json.dumps(c)}")
    print()

    print("## Events\n")
    for name, (_, events, _, marks) in clients.items():
        seqs = [s for s, _, _ in events]
        start = marks.get("welcome", (0, {}))[1].get("ev_from", 0)
        contiguous = seqs == list(range(start + 1, start + 1 + len(seqs)))
        via_full = sum(1 for _, _, v in events if v == "full")
        summ = marks.get("summary", (0, {}))[1]
        print(
            f"- {name}: delivered {len(seqs)} ({start + 1}..{seqs[-1] if seqs else '-'}), "
            f"contiguous {contiguous}, via full snapshot {via_full}, "
            f"duplicates {summ.get('event_duplicates')}, waiting {summ.get('events_waiting')}, "
            f"missing delta base {summ.get('missing_base')}, chunk errors {summ.get('chunk_errors')}"
        )
    print()

    for name, (snaps, events, _, marks) in clients.items():
        if not name.endswith(".restart"):
            continue
        orig = clients[name.removesuffix(".restart")]
        killed_last = orig[1][-1][0] if orig[1] else 0
        welcome = marks["welcome"][1]
        first = marks["first_full"][1]
        print("## Reconnect\n")
        print(
            f"- {name}: resumed {welcome['resumed']}, seat restored {welcome['seat_restored']}, "
            f"launch to first applied full snapshot {ms(first['since_launch_us'])} ms; "
            f"killed process delivered events up to {killed_last}, restart resumes after "
            f"{welcome['ev_from']} (no hole: {welcome['ev_from'] <= killed_last})\n"
        )

    for name, (snaps, events, _, marks) in clients.items():
        if "stall_start" not in marks:
            continue
        t0 = marks["stall_start"][0]
        t1 = marks["stall_end"][0]
        rec = marks["stall_recovered"]
        stall_note = next(
            (u for u, k, d in server if k == "stall" and d["client"] == name and u >= t0), None
        )
        full_note = next(
            (
                u
                for u, k, d in server
                if k == "full" and d["client"] == name and d["resync"] and u >= t0
            ),
            None,
        )
        others = sum(1 for u, k, d in server if k == "stall" and d["client"] == name and u < t0)
        backlog = [x for x in snaps if t1 <= x[3] <= rec[0]]
        pre = [x for x in snaps if t0 <= x[2] < (stall_note or 0) and not x[1]]
        late_sent = [x for x in snaps if (stall_note or 0) <= x[2] < (full_note or 0) and not x[1]]
        print("## Stalled reader\n")
        print(
            f"- {name}: stall {ms(t1 - t0)} ms; server marked it stalled "
            f"{ms(stall_note - t0) if stall_note else '-'} ms after the stall began and sent "
            f"its resync full {ms(full_note - t1) if full_note else '-'} ms after it resumed; "
            f"deltas sent between stall start and detection {len(pre)}, after detection "
            f"{len(late_sent)}; "
            f"backlog applied on resume {len(backlog)} snapshots; recovered "
            f"{ms(rec[1]['after_resume_us'])} ms after resuming with one full snapshot "
            f"carrying {rec[1]['events']} events; earlier loss-induced stalls of this client "
            f"{others}\n"
        )

    for name, (_, _, chunks, marks) in clients.items():
        if "voice" not in marks:
            continue
        queued = next(u for u, k, d in server if k == "voice_queued")
        voice_msg = next(d["msg"] for _, k, d in server if k == "voice_queued")
        window = [c for c in chunks if c[4] >= queued]
        voice = [c for c in window if c[0] == 2]
        v_last = voice[-1][4]
        snaps_in = [c for c in window if c[0] == 1 and c[4] <= v_last]
        order = " ".join(
            ("V" if c[0] == 2 else "S") + f"{c[2]}/{c[3]}" for c in window if c[4] <= v_last
        )
        print("## Chunking\n")
        v = marks["voice"][1]
        print(
            f"- {name}: voice msg {voice_msg}, {v['bytes']} B in {len(voice)} chunks, intact "
            f"{v['ok']}; first voice chunk {ms(voice[0][4] - queued)} ms and last "
            f"{ms(v_last - queued)} ms after queueing; snapshot chunks received meanwhile "
            f"{len(snaps_in)}"
        )
        print(f"- arrival order (S = snapshot chunk i/n, V = voice): {order}\n")


if __name__ == "__main__":
    main(sys.argv[1])
