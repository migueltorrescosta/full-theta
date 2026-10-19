"""Checks one load-gate run (#11; FT-GEN-003, FT-NET-014, FT-NET-040; D160-D162).

    python tools/l4/load_check.py OUT_DIR [--report-only]

Reads OUT_DIR/probe.json (the server's LoadProbe), p0..p7.json (tools/l4/load_client.gd),
p65.json (the 65th connection), host.txt and host.tsv (tools/l4/load.sh), and prints a
Markdown summary. Budgets and checks (S9, D104, D106, D109, D111, D161):

- server tick: every main-thread frame that stepped the sim (process, sim, after_ticks,
  capture), mean and p99 < 8 ms; the sim keeps real time (at least 59 ticks a second);
  every crewable ship (6) has started;
- snapshot age: arrival at the client minus the capture stamp on the server, p99 pooled
  over all clients < 150 ms, no age below -1 ms (clock or stamp error);
- every client receives at least 90 % of the window's snapshots, with no stall;
- bandwidth: server payload to all clients <= 10 Mbit/s, also when scaled to 30
  snapshots a second (the loopback wire total, both directions with every header, is
  reported beside it);
- one encode per view key: per snapshot, the delta and full messages assembled together
  are at most the distinct view keys, shared by every client of a key;
- the seat plan (6 of each station, 6 Captains, 22 viewers) all picked, no bad snapshot,
  and connection 65 refused with session_full.

Exits 1 if a budget or check fails, unless --report-only.
"""

from __future__ import annotations

import json
import sys
from collections import defaultdict
from collections.abc import Callable
from pathlib import Path

TICK_BUDGET_MS = 8.0
MIN_TICKS_PER_S = 59.0
AGE_BUDGET_MS = 150.0
MIN_AGE_MS = -1.0
MIN_RECEIPT_SHARE = 0.9
BANDWIDTH_BUDGET_MBIT = 10.0
CREW_SHIPS = 6
SEATS = {
    "helm": 6, "weapons": 6, "engineering": 6, "science": 6, "relay": 6, "comms": 6,
    "captain": 6, "viewer": 22,
}


def pct(values: list[float], p: float) -> float:
    if not values:
        return float("nan")
    s = sorted(values)
    return s[min(len(s) - 1, int(p / 100.0 * len(s)))]


def mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else float("nan")


def rows(flat: list[int], fields: list[str]) -> list[dict[str, int]]:
    n = len(fields)  # a cut-off last row (a killed run) is dropped
    return [dict(zip(fields, flat[i : i + n], strict=True)) for i in range(0, len(flat) - n + 1, n)]


def stats_ms(values_us: list[float]) -> str:
    v = [x / 1000.0 for x in values_us]
    return f"{mean(v):.2f} / {pct(v, 50):.2f} / {pct(v, 99):.2f} / {max(v, default=float('nan')):.2f}"


def verdict(ok: bool) -> str:
    return "met" if ok else "NOT MET"


def check(out: Path, report_only: bool) -> int:
    lines: list[str] = []
    problems: list[str] = []
    complete = _check(out, lines.append, problems)
    lines.append("")
    lines.append(f"**Result: {'PASS' if not problems else 'FAIL: ' + '; '.join(problems)}**")
    print("\n".join(lines))
    return 0 if report_only or (complete and not problems) else 1


def _check(out: Path, say: Callable[[str], None], problems: list[str]) -> bool:  # noqa: C901
    """Writes the report through say and appends each failed check to problems; False
    when the run is too incomplete to check."""
    probe = json.loads((out / "probe.json").read_text())
    marks = probe["marks"]
    say(f"# Load gate run {out.name}")
    say("")
    if "window_start_unix_us" not in marks or "window_end_unix_us" not in marks:
        problems.append(f"window incomplete (marks: {sorted(marks)})")
        return False
    w0, w1 = int(marks["window_start_unix_us"]), int(marks["window_end_unix_us"])
    span_s = (w1 - w0) / 1e6
    if span_s <= 0:
        problems.append("window incomplete (empty)")
        return False

    host = dict(
        line.split(" ", 1) for line in (out / "host.txt").read_text().splitlines() if " " in line
    )
    say(
        f"Commit {host.get('commit')}, world {host.get('world')} ships "
        f"(server: {probe['server']['ships']}), server CPUs {host.get('server_cpus')}, "
        f"clients {host.get('procs')} on CPUs {host.get('client_cpus')}, window {span_s:.1f} s."
    )
    samples = []
    tsv = out / "host.tsv"
    for raw in tsv.read_text().splitlines() if tsv.exists() else []:
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
            f"{min(freqs, default=0):.2f}-{max(freqs, default=0):.2f} GHz (mean {mean(freqs):.2f}); "
            f"governor {host.get('governor')}, EPP {host.get('epp')}, no_turbo "
            f"{host.get('no_turbo')}, netns '{host.get('netns', '').strip()}'."
        )
    prof = out / "sim_profile.txt"
    if prof.exists():
        last = [x for x in prof.read_text().splitlines() if x.startswith("tick ")]
        if last:
            say(f"Sim alone (sim_profile.txt, same cores and world): {last[-1]}")
    say("")

    # --- Server tick (main thread). ---
    frames = [r for r in rows(probe["frames"], probe["frame_fields"]) if w0 <= r["unix_us"] <= w1]
    total = [float(r["total_us"]) for r in frames]
    ticks = sum(r["ticks"] for r in frames)
    rate_ticks = ticks / span_s
    tick_mean, tick_p99 = mean(total) / 1000.0, pct(total, 99) / 1000.0
    launched = marks.get("launched_at_end", marks.get("launched_at_start"))
    say("## Server tick (main thread, frames that stepped the sim)")
    say("")
    say(
        f"{len(frames)} frames, {ticks} ticks ({rate_ticks:.1f} ticks/s; 60 is real time); "
        f"ships started: {launched if launched is not None else 'not recorded'} of {CREW_SHIPS}."
    )
    say("")
    say("| Part | mean / p50 / p99 / max ms |")
    say("|---|---|")
    say(f"| **Frame total (gating, D161)** | **{stats_ms(total)}** |")
    say(f"| frame total / ticks | {stats_ms([r['total_us'] / r['ticks'] for r in frames if r['ticks']])} |")
    for key, label in [
        ("process_us", "session.process (inbound messages)"),
        ("sim_us", "sim step(s)"),
        ("after_us", "after_ticks (rejections, events)"),
        ("capture_us", "SimCopy.capture (every 2nd tick)"),
        ("oncpu_us", "on CPU (schedstat)"),
        ("preempt_us", "preempted, run queue (schedstat)"),
    ]:
        say(f"| {label} | {stats_ms([float(r[key]) for r in frames])} |")
    say(f"| sim per tick | {stats_ms([r['sim_us'] / r['ticks'] for r in frames if r['ticks']])} |")
    say(f"| on CPU per tick | {stats_ms([r['oncpu_us'] / r['ticks'] for r in frames if r['ticks']])} |")
    say("")
    say(f"Frames that ran more than one tick (catch-up): {sum(1 for r in frames if r['ticks'] > 1)}.")
    ok_tick = bool(frames) and tick_mean < TICK_BUDGET_MS and tick_p99 < TICK_BUDGET_MS
    say(
        f"Budget: mean {tick_mean:.2f} ms and p99 {tick_p99:.2f} ms < {TICK_BUDGET_MS} ms: "
        f"**{verdict(ok_tick)}**. Real time (>= {MIN_TICKS_PER_S:.0f} ticks/s): "
        f"**{verdict(rate_ticks >= MIN_TICKS_PER_S)}**. Every ship started: "
        f"**{verdict(launched is not None and launched >= CREW_SHIPS)}**."
    )
    if not ok_tick:
        problems.append(f"server tick mean {tick_mean:.2f} / p99 {tick_p99:.2f} ms")
    if rate_ticks < MIN_TICKS_PER_S:
        problems.append(f"{rate_ticks:.1f} ticks/s")
    if launched is None or launched < CREW_SHIPS:
        problems.append(f"ships started: {launched}")
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
    say(f"| assemble view-key messages and queue sends | {stats_ms([float(r['send_us']) for r in snaps])} |")
    parts = [
        f for f in net["snap_fields"]
        if f.endswith("_us") and f not in ("unix_us", "stamp_us", "restore_us", "build_us", "send_us")
    ]
    if parts and snaps:
        say("")
        say(
            "Build by part, mean ms per snapshot: "
            + ", ".join(f"{f[:-3]} {mean([r[f] for r in snaps]) / 1000:.2f}" for f in parts)
            + "."
        )
    if secs:
        # ops_us holds the restores; snapshot_us (newer probes) the build and queueing, so
        # nothing is counted twice.
        parts_s = [f for f in ("poll_us", "pump_us", "ops_us", "snapshot_us") if f in secs[0]]
        busy = mean([sum(r[f] for f in parts_s) for r in secs])
        if "snapshot_us" not in secs[0]:
            busy += sum(r["build_us"] + r["send_us"] for r in snaps) / span_s
        say("")
        say(
            f"Per second: {mean([r['loops'] for r in secs]):.0f} loops; "
            + ", ".join(f"{f[:-3]} {mean([r[f] for r in secs]) / 1000:.1f} ms" for f in parts_s)
            + f" (ops include the restores); busy {busy / 1000:.0f} ms of each second, "
            f"{busy / 1e6:.2f} of a core."
        )
    say("")

    # --- One encode per view key (FT-NET-040). ---
    say("## Encodes per view key (FT-NET-040)")
    say("")
    sends = [r["sends"] for r in snaps]
    messages = [r["delta_messages"] + r["full_messages"] for r in snaps]
    over = [r for r in snaps if r["delta_messages"] + r["full_messages"] > r["keys"]]
    under = [r for r in snaps if r["delta_messages"] + r["full_messages"] < r["keys"]]
    say(
        f"Per snapshot: {mean([r['keys'] for r in snaps]):.1f} distinct view keys, "
        f"{mean(sends):.1f} sends, {mean(messages):.2f} messages assembled "
        f"({mean([r['full_messages'] for r in snaps]):.2f} full), "
        f"{mean([r['section_updates'] for r in snaps]):.1f} section updates. Snapshots with "
        f"more messages than keys: {len(over)}; with fewer: {len(under)}."
    )
    ok_keys = bool(snaps) and not over and mean(sends) > mean(messages)
    say(f"**{verdict(ok_keys)}**.")
    if not ok_keys:
        problems.append(f"encodes per view key ({len(over)} snapshots over)")
    say("")

    # --- Clients: receipts, gaps, age. ---
    stamp = {r["seq"]: r["stamp_us"] for r in rows(net["snaps"], net["snap_fields"])}
    clients = []
    proc_ok = True
    for p in sorted(out.glob("p[0-9]*.json")):
        if p.name == "p65.json":
            continue
        doc = json.loads(p.read_text())
        proc_ok = proc_ok and bool(doc.get("ok"))
        clients.extend(doc.get("clients", []))
    ages_all: list[float] = []
    gaps_all: list[float] = []
    per_client_p99: list[tuple[float, str]] = []
    per_client_gap: list[tuple[float, str]] = []
    starved: list[str] = []
    bad = 0
    picks_failed = []
    rejects: dict[str, int] = defaultdict(int)
    need = MIN_RECEIPT_SHARE * len(snaps)
    for c in clients:
        bad += int(c["stats"].get("bad_snapshots", 0))
        if c["picked"] != "ok":
            picks_failed.append(f"{c['name']} {c['entry']}: {c['picked']}")
        for k, v in c["rejects"].items():
            rejects[k] += v
        flat = c["snaps"]
        got = [(flat[i], flat[i + 1]) for i in range(0, len(flat), 2) if w0 <= flat[i + 1] <= w1]
        if not got or len(got) < need:
            starved.append(f"{c['name']} {len(got)}")
        ages = [(t - stamp[s]) / 1000.0 for s, t in got if stamp.get(s, 0) > 0]
        gaps = [(got[i][1] - got[i - 1][1]) / 1000.0 for i in range(1, len(got))]
        ages_all.extend(ages)
        gaps_all.extend(gaps)
        if ages:
            per_client_p99.append((pct(ages, 99), c["name"]))
        if gaps:
            per_client_gap.append((pct(gaps, 99), c["name"]))
    age_p99 = pct(ages_all, 99)
    age_min = min(ages_all, default=float("nan"))
    worst = max(per_client_p99, default=(float("nan"), "-"))
    worst_gap = max(per_client_gap, default=(float("nan"), "-"))
    say("## Snapshot age (D106: p99 pooled over all clients)")
    say("")
    say(
        f"{len(clients)} clients, {len(ages_all)} snapshot receipts in the window. Age "
        f"(client arrival minus server capture) min {age_min:.1f}, p50 {pct(ages_all, 50):.1f}, "
        f"p99 {age_p99:.1f}, max {max(ages_all, default=float('nan')):.1f} ms; worst client p99 "
        f"{worst[0]:.1f} ms ({worst[1]}). Gap between a client's receipts: p99 "
        f"{pct(gaps_all, 99):.1f} ms pooled, worst client p99 {worst_gap[0]:.1f} ms "
        f"({worst_gap[1]}). Clients below {MIN_RECEIPT_SHARE:.0%} of the window's "
        f"{len(snaps)} snapshots: {starved or 'none'}."
    )
    ok_age = bool(ages_all) and age_p99 < AGE_BUDGET_MS and age_min >= MIN_AGE_MS
    say(
        f"Budget p99 < {AGE_BUDGET_MS:.0f} ms (and no age below {MIN_AGE_MS:.0f} ms): "
        f"**{verdict(ok_age)}**. Every client fed: **{verdict(not starved)}**."
    )
    if not ok_age:
        problems.append(f"snapshot age p99 {age_p99:.1f} ms, min {age_min:.1f} ms")
    if starved:
        problems.append(f"{len(starved)} clients starved")
    say("")

    # --- Bandwidth. ---
    say("## Bandwidth (FT-NET-040)")
    say("")
    seconds_all = rows(net["seconds"], net["second_fields"])
    conn_samples = list(zip([r["unix_us"] for r in seconds_all], net["conns"], strict=False))
    if len(conn_samples) < 2:
        problems.append("bandwidth: fewer than two byte samples")
        return False
    a_us, a = min(conn_samples, key=lambda s: abs(s[0] - w0))
    b_us, b = min(conn_samples, key=lambda s: abs(s[0] - w1))
    dt = (b_us - a_us) / 1e6
    if dt <= 0:
        problems.append("bandwidth: no byte samples spanning the window")
        return False
    session_seat = {str(c["session"]): c for c in clients}
    per_entry: dict[str, list[float]] = defaultdict(list)
    total_bps = 0.0
    stalls = 0
    skipped: list[int] = []
    for conn, row in b.items():
        if row[0] < 0:
            continue
        stalls += row[6]
        before = a.get(conn)
        if before is None:
            continue
        if len(row) > 7:
            skipped.append(row[7] - before[7])
        bps = (row[2] - before[2]) / dt
        total_bps += bps
        seat = session_seat.get(str(row[0]))
        per_entry[seat["entry"] if seat else "?"].append(bps)
    say("| Entry | Clients | B/s per client mean | min | max |")
    say("|---|---|---|---|---|")
    for entry in sorted(per_entry):
        v = per_entry[entry]
        say(f"| {entry} | {len(v)} | {mean(v):,.0f} | {min(v):,.0f} | {max(v):,.0f} |")
    all_v = [x for v in per_entry.values() for x in v]
    say(
        f"| all | {len(all_v)} | {mean(all_v):,.0f} | {min(all_v, default=0):,.0f} | "
        f"{max(all_v, default=0):,.0f} |"
    )
    payload_mbit = total_bps * 8 / 1e6
    wire = ""
    if len(samples) >= 2:
        ncol = len(samples[0])
        la = min(samples, key=lambda s: abs(s[0] - w0))
        lb = min(samples, key=lambda s: abs(s[0] - w1))
        ldt = (lb[0] - la[0]) / 1e6
        if ldt > 0:
            # /proc/net/dev counts loopback bytes once per packet (rx == tx on lo).
            wire_mbit = (lb[ncol - 2] - la[ncol - 2]) * 8 / 1e6 / ldt
            pkts = (lb[ncol - 1] - la[ncol - 1]) / ldt
            scope = "this run only" if host.get("netns", "").strip() else "the whole host's loopback"
            wire = (
                f" Loopback wire total, both directions with every header: {wire_mbit:.2f} "
                f"Mbit/s, {pkts:,.0f} packets/s ({scope})."
            )
    say("")
    say(
        f"Server payload to all clients (chunk headers and messages, as handed to "
        f"WebSocketPeer): {total_bps:,.0f} B/s = **{payload_mbit:.2f} Mbit/s**.{wire}"
    )
    # The server sends fewer than 30 snapshots a second when its frames run late; the
    # budget is checked at the nominal rate too (an upper bound: deltas grow with the gap).
    rate = len(snaps) / span_s
    if rate > 0:
        nominal = payload_mbit * 30.0 / rate
        say(
            f"Snapshots went out at {rate:.1f}/s; scaled to the nominal 30/s the payload would "
            f"be **{nominal:.2f} Mbit/s** ({total_bps / rate:,.0f} B per snapshot to all clients)."
        )
        payload_mbit = max(payload_mbit, nominal)
    ok_bw = 0 < payload_mbit <= BANDWIDTH_BUDGET_MBIT and len(all_v) == 64
    say(f"Budget <= {BANDWIDTH_BUDGET_MBIT:.0f} Mbit/s at 64 connections: **{verdict(ok_bw)}**.")
    if not ok_bw:
        problems.append(f"payload {payload_mbit:.2f} Mbit/s over {len(all_v)} connections")
    say("")

    # --- Session cap and client health. ---
    say("## Session cap and clients")
    say("")
    p65 = out / "p65.json"
    full = json.loads(p65.read_text())["full_probe"] if p65.exists() else {"ok": False, "reason": "no log"}
    say(
        f"Connection 65: reason `{full.get('reason')}`: "
        f"**{'refused, met' if full.get('ok') else 'NOT MET'}** (FT-NET-014)."
    )
    if not full.get("ok"):
        problems.append(f"connection 65: {full.get('reason')}")
    by_entry: dict[str, int] = defaultdict(int)
    for c in clients:
        by_entry[c["entry"]] += 1
    seats_ok = dict(by_entry) == SEATS
    say(
        f"Seats: {dict(sorted(by_entry.items()))} ({verdict(seats_ok)}); picks refused: "
        f"{picks_failed or 'none'}; bad snapshots: {bad}; stalls: {stalls}; snapshots skipped "
        f"in the window: {sum(skipped) if skipped else 'not recorded'} (max per connection "
        f"{max(skipped, default=0)}); command and request rejections: {dict(rejects) or 'none'}; "
        f"client processes ok: {proc_ok}."
    )
    if not seats_ok or picks_failed or bad or stalls or not proc_ok:
        problems.append("client seats, decoding or stalls")
    return True


if __name__ == "__main__":
    args = sys.argv[1:]
    sys.exit(check(Path(args[0]), "--report-only" in args))
