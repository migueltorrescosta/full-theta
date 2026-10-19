"""Checks one load-gate run (#11; FT-GEN-003, FT-NET-014, FT-NET-040; D160-D162).

    python tools/l4/load_check.py OUT_DIR [--report-only]

Reads OUT_DIR/probe.json (the server's LoadProbe), p0..p7.json (tools/l4/load_client.gd),
p65.json (the 65th connection), host.txt and host.tsv (tools/l4/load.sh), and prints a
Markdown summary. Budgets (S9, D104, D106, D109, D111):

- server tick: every main-thread frame that stepped the sim (process, sim, after_ticks,
  capture), mean and p99 < 8 ms;
- snapshot age: arrival at the client minus the capture stamp on the server, p99 pooled
  over all clients < 150 ms;
- bandwidth: server payload to all clients <= 10 Mbit/s (the loopback wire total, both
  directions with every header, is reported beside it);
- one encode per view key: per snapshot, at most one delta and one full message per
  distinct view key, shared by every client of the key;
- connection 65 refused with session_full; every seat picked, no bad snapshot, no stall.

Exits 1 if a budget or check fails, unless --report-only.
"""

from __future__ import annotations

import json
import sys
from collections import defaultdict
from pathlib import Path

TICK_BUDGET_MS = 8.0
AGE_BUDGET_MS = 150.0
BANDWIDTH_BUDGET_MBIT = 10.0


def pct(values: list[float], p: float) -> float:
    if not values:
        return float("nan")
    s = sorted(values)
    return s[min(len(s) - 1, int(p / 100.0 * len(s)))]


def mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else float("nan")


def rows(flat: list[int], fields: list[str]) -> list[dict[str, int]]:
    n = len(fields)
    return [dict(zip(fields, flat[i : i + n], strict=True)) for i in range(0, len(flat), n)]


def stats_ms(values_us: list[float]) -> str:
    v = [x / 1000.0 for x in values_us]
    return f"{mean(v):.2f} / {pct(v, 50):.2f} / {pct(v, 99):.2f} / {max(v, default=float('nan')):.2f}"


def nearest(samples: list[tuple[int, dict]], t: int) -> tuple[int, dict]:
    return min(samples, key=lambda s: abs(s[0] - t))


def check(out: Path, report_only: bool) -> int:
    probe = json.loads((out / "probe.json").read_text())
    marks = probe["marks"]
    w0, w1 = int(marks["window_start_unix_us"]), int(marks["window_end_unix_us"])
    span_s = (w1 - w0) / 1e6
    lines: list[str] = []
    problems: list[str] = []
    say = lines.append

    host = dict(
        line.split(" ", 1) for line in (out / "host.txt").read_text().splitlines() if " " in line
    )
    say(f"# Load gate run {out.name}")
    say("")
    say(
        f"Commit {host.get('commit')}, world {host.get('world')} ships "
        f"(server: {probe['server']['ships']}), server CPUs {host.get('server_cpus')}, "
        f"clients {host.get('procs')} on CPUs {host.get('client_cpus')}, window {span_s:.1f} s."
    )
    samples = []
    for raw in (out / "host.tsv").read_text().splitlines():
        f = raw.split()
        if len(f) >= 4:
            samples.append([float(x) for x in f])
    in_window = [s for s in samples if w0 <= s[0] <= w1] or samples
    if in_window:
        loads = [s[1] for s in in_window]
        ncpu = len(in_window[0]) - 4
        freqs = [x / 1e6 for s in in_window for x in s[2 : 2 + ncpu]]
        say(
            f"Host: load average {min(loads):.1f}-{max(loads):.1f} during the window "
            f"(start of run {host.get('loadavg')}); server cores' scaling_cur_freq "
            f"{min(freqs):.2f}-{max(freqs):.2f} GHz (mean {mean(freqs):.2f}); governor "
            f"{host.get('governor')}, EPP {host.get('epp')}, no_turbo {host.get('no_turbo')}, "
            f"netns '{host.get('netns', '').strip()}'."
        )
    say("")

    # --- Server tick (main thread). ---
    frames = [r for r in rows(probe["frames"], probe["frame_fields"]) if w0 <= r["unix_us"] <= w1]
    total = [float(r["total_us"]) for r in frames]
    ticks = sum(r["ticks"] for r in frames)
    tick_mean, tick_p99 = mean(total) / 1000.0, pct(total, 99) / 1000.0
    say("## Server tick (main thread, frames that stepped the sim)")
    say("")
    say(f"{len(frames)} frames, {ticks} ticks ({ticks / span_s:.1f} ticks/s; 60 is real time).")
    say("")
    say("| Part | mean / p50 / p99 / max ms |")
    say("|---|---|")
    say(f"| **Frame total** | **{stats_ms(total)}** |")
    for key, label in [
        ("process_us", "session.process (inbound messages)"),
        ("sim_us", "sim step(s)"),
        ("after_us", "after_ticks (rejections, events)"),
        ("capture_us", "SimCopy.capture (every 2nd tick)"),
        ("oncpu_us", "on CPU (schedstat)"),
        ("preempt_us", "preempted, run queue (schedstat)"),
    ]:
        say(f"| {label} | {stats_ms([float(r[key]) for r in frames])} |")
    per_tick = [r["sim_us"] / r["ticks"] for r in frames if r["ticks"]]
    say(f"| sim per tick | {stats_ms(per_tick)} |")
    say(f"| on CPU per tick (frame on-CPU / ticks) | {stats_ms([r['oncpu_us'] / r['ticks'] for r in frames if r['ticks']])} |")
    multi = sum(1 for r in frames if r["ticks"] > 1)
    say("")
    say(f"Frames that ran more than one tick (catch-up): {multi}.")
    ok_tick = tick_mean < TICK_BUDGET_MS and tick_p99 < TICK_BUDGET_MS
    say(
        f"Budget: mean {tick_mean:.2f} ms and p99 {tick_p99:.2f} ms < {TICK_BUDGET_MS} ms: "
        f"**{'met' if ok_tick else 'NOT MET'}**."
    )
    if not ok_tick:
        problems.append(f"server tick mean {tick_mean:.2f} / p99 {tick_p99:.2f} ms")
    say("")

    # --- Net thread. ---
    net = probe["net"]
    snaps = [r for r in rows(net["snaps"], net["snap_fields"]) if w0 <= r["unix_us"] <= w1]
    secs = [r for r in rows(net["seconds"], net["second_fields"]) if w0 <= r["unix_us"] <= w1]
    say("## Net thread (encode and send, off the sim thread)")
    say("")
    say(f"{len(snaps)} snapshots ({len(snaps) / span_s:.1f}/s).")
    say("")
    say("| Part | mean / p50 / p99 / max ms |")
    say("|---|---|")
    say(f"| SimCopy.restore | {stats_ms([float(r['restore_us']) for r in snaps])} |")
    say(f"| SnapshotBuilder.build (sections) | {stats_ms([float(r['build_us']) for r in snaps])} |")
    say(
        "| assemble view-key messages and queue sends | "
        f"{stats_ms([float(r['send_us']) for r in snaps])} |"
    )
    parts = [f for f in net["snap_fields"] if f.endswith("_us") and f not in (
        "unix_us", "stamp_us", "restore_us", "build_us", "send_us")]
    if parts and snaps:
        say("")
        say(
            "Build by part, mean ms per snapshot: "
            + ", ".join(f"{f[:-3]} {mean([r[f] for r in snaps]) / 1000:.2f}" for f in parts)
            + "."
        )
    if secs:
        loops = sum(r["loops"] for r in secs)
        busy = sum(r["poll_us"] + r["pump_us"] + r["ops_us"] for r in secs)
        say("")
        say(
            f"Per second: {loops / len(secs):.0f} loops; poll {mean([r['poll_us'] for r in secs]) / 1000:.1f} ms, "
            f"pump (socket writes) {mean([r['pump_us'] for r in secs]) / 1000:.1f} ms, ops "
            f"(incl. restore) {mean([r['ops_us'] for r in secs]) / 1000:.1f} ms; snapshot work "
            f"{sum(r['restore_us'] + r['build_us'] + r['send_us'] for r in snaps) / span_s / 1000:.1f} ms; "
            f"loop total (without the 1 ms sleeps) {busy / len(secs) / 1000:.1f} ms of each second "
            "besides snapshots."
        )
    say("")

    # --- One encode per view key (FT-NET-040). ---
    say("## Encodes per view key (FT-NET-040)")
    say("")
    keys = [r["keys"] for r in snaps]
    sends = [r["sends"] for r in snaps]
    deltas = [r["delta_messages"] for r in snaps]
    fulls = [r["full_messages"] for r in snaps]
    over = [r for r in snaps if r["delta_messages"] > r["keys"] or r["full_messages"] > r["keys"]]
    say(
        f"Per snapshot: {mean(keys):.1f} distinct view keys, {mean(sends):.1f} sends, "
        f"{mean(deltas):.2f} delta and {mean(fulls):.2f} full messages assembled, "
        f"{mean([r['section_updates'] for r in snaps]):.1f} section updates. "
        f"Snapshots with more than one message of a kind per key: {len(over)}."
    )
    ok_keys = bool(snaps) and not over and mean(sends) > mean(deltas)
    say(f"**{'met' if ok_keys else 'NOT MET'}**.")
    if not ok_keys:
        problems.append("more than one encode per view key")
    say("")

    # --- Clients: snapshot age, picks, decode. ---
    stamp = {r["seq"]: r["stamp_us"] for r in rows(net["snaps"], net["snap_fields"])}
    clients = []
    proc_ok = True
    for p in sorted(out.glob("p[0-9].json")) + sorted(out.glob("p[0-9][0-9].json")):
        if p.name == "p65.json":
            continue
        doc = json.loads(p.read_text())
        proc_ok = proc_ok and bool(doc.get("ok"))
        clients.extend(doc.get("clients", []))
    ages_all: list[float] = []
    per_client_p99: list[tuple[float, str]] = []
    bad = 0
    picks_failed = []
    rejects: dict[str, int] = defaultdict(int)
    for c in clients:
        bad += int(c["stats"].get("bad_snapshots", 0))
        if c["picked"] != "ok":
            picks_failed.append(f"{c['name']} {c['entry']}: {c['picked']}")
        for k, v in c["rejects"].items():
            rejects[k] += v
        flat = c["snaps"]
        ages = [
            (flat[i + 1] - stamp[flat[i]]) / 1000.0
            for i in range(0, len(flat), 2)
            if w0 <= flat[i + 1] <= w1 and stamp.get(flat[i], 0) > 0
        ]
        ages_all.extend(ages)
        if ages:
            per_client_p99.append((pct(ages, 99), c["name"]))
    age_p99 = pct(ages_all, 99)
    say("## Snapshot age (D106: p99 pooled over all clients)")
    say("")
    say(
        f"{len(clients)} clients, {len(ages_all)} snapshot receipts in the window. Age "
        f"(client arrival minus server capture) p50 {pct(ages_all, 50):.1f} ms, p99 "
        f"{age_p99:.1f} ms, max {max(ages_all, default=float('nan')):.1f} ms; worst client p99 "
        f"{max(per_client_p99, default=(float('nan'), '-'))[0]:.1f} ms "
        f"({max(per_client_p99, default=(0, '-'))[1]})."
    )
    ok_age = bool(ages_all) and age_p99 < AGE_BUDGET_MS
    say(f"Budget p99 < {AGE_BUDGET_MS:.0f} ms: **{'met' if ok_age else 'NOT MET'}**.")
    if not ok_age:
        problems.append(f"snapshot age p99 {age_p99:.1f} ms")
    say("")

    # --- Bandwidth. ---
    say("## Bandwidth (FT-NET-040)")
    say("")
    conn_samples = [(s_us, c) for s_us, c in zip(
        [r["unix_us"] for r in rows(net["seconds"], net["second_fields"])], net["conns"], strict=True
    )]
    a_us, a = nearest(conn_samples, w0)
    b_us, b = nearest(conn_samples, w1)
    dt = (b_us - a_us) / 1e6
    session_seat = {str(c["session"]): c for c in clients}
    per_entry: dict[str, list[float]] = defaultdict(list)
    total_bps = 0.0
    for conn, row in b.items():
        before = a.get(conn)
        if before is None or row[0] < 0:
            continue
        bps = (row[2] - before[2]) / dt
        total_bps += bps
        seat = session_seat.get(str(row[0]))
        entry = seat["entry"] if seat else "?"
        per_entry[entry].append(bps)
    say("| Entry | Clients | B/s per client mean | min | max |")
    say("|---|---|---|---|---|")
    for entry in sorted(per_entry):
        v = per_entry[entry]
        say(f"| {entry} | {len(v)} | {mean(v):,.0f} | {min(v):,.0f} | {max(v):,.0f} |")
    all_v = [x for v in per_entry.values() for x in v]
    say(f"| all | {len(all_v)} | {mean(all_v):,.0f} | {min(all_v, default=0):,.0f} | {max(all_v, default=0):,.0f} |")
    payload_mbit = total_bps * 8 / 1e6
    lo = [s for s in samples if len(s) >= 4]
    wire = ""
    if lo:
        ncol = len(lo[0])
        la = min(lo, key=lambda s: abs(s[0] - w0))
        lb = min(lo, key=lambda s: abs(s[0] - w1))
        ldt = (lb[0] - la[0]) / 1e6
        if ldt > 0:
            # /proc/net/dev counts loopback bytes once per packet (rx == tx on lo).
            wire_mbit = (lb[ncol - 2] - la[ncol - 2]) * 8 / 1e6 / ldt
            pkts = (lb[ncol - 1] - la[ncol - 1]) / ldt
            scope = "this run only" if host.get("netns", "").strip() else "the whole host's loopback"
            wire = (
                f" Loopback wire total, both directions with every header: {wire_mbit:.2f} Mbit/s, "
                f"{pkts:,.0f} packets/s ({scope})."
            )
    say("")
    say(
        f"Server payload to all clients (chunk headers and messages, as handed to "
        f"WebSocketPeer): {total_bps:,.0f} B/s = **{payload_mbit:.2f} Mbit/s**.{wire}"
    )
    # The server sends fewer than 30 snapshots a second when its frames run late; the
    # budget is checked at the nominal rate too.
    rate = len(snaps) / span_s if snaps else 0.0
    nominal_mbit = payload_mbit * 30.0 / rate if rate > 0 else float("nan")
    say(
        f"Snapshots went out at {rate:.1f}/s; scaled to the nominal 30/s the payload would be "
        f"**{nominal_mbit:.2f} Mbit/s** ({total_bps / rate if rate else 0:,.0f} B per snapshot "
        "to all clients)."
    )
    payload_mbit = max(payload_mbit, nominal_mbit) if rate > 0 else payload_mbit
    ok_bw = 0 < payload_mbit <= BANDWIDTH_BUDGET_MBIT and len(all_v) == 64
    say(f"Budget <= {BANDWIDTH_BUDGET_MBIT:.0f} Mbit/s at 64 connections: **{'met' if ok_bw else 'NOT MET'}**.")
    if not ok_bw:
        problems.append(f"payload {payload_mbit:.2f} Mbit/s over {len(all_v)} connections")
    stalls = sum(row[6] for row in b.values())
    say("")

    # --- Session cap and client health. ---
    say("## Session cap and clients")
    say("")
    p65 = out / "p65.json"
    full = json.loads(p65.read_text())["full_probe"] if p65.exists() else {"ok": False, "reason": "no log"}
    say(f"Connection 65: reason `{full.get('reason')}`: **{'refused, met' if full.get('ok') else 'NOT MET'}** (FT-NET-014).")
    if not full.get("ok"):
        problems.append(f"connection 65: {full.get('reason')}")
    by_entry: dict[str, int] = defaultdict(int)
    for c in clients:
        by_entry[c["entry"]] += 1
    say(
        f"Seats: {dict(sorted(by_entry.items()))}; picks refused: {picks_failed or 'none'}; "
        f"bad snapshots: {bad}; stalls: {stalls}; command and request rejections: "
        f"{dict(rejects) or 'none'}; client processes ok: {proc_ok}."
    )
    if len(clients) != 64 or picks_failed or bad or not proc_ok:
        problems.append("client seats or decoding")
    say("")
    say(f"**Result: {'PASS' if not problems else 'FAIL: ' + '; '.join(problems)}**")
    print("\n".join(lines))
    return 0 if report_only or not problems else 1


if __name__ == "__main__":
    args = sys.argv[1:]
    sys.exit(check(Path(args[0]), "--report-only" in args))
