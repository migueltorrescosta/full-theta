# FT: FT-NET-040, FT-NET-014
"""Fixture tests for tools/l4/load_check.py (#11 load gate, D161) on synthetic runs:
a run inside every budget passes, and a slow tick, a late snapshot, too many bytes or an
admitted 65th connection each fail it."""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "l4"))
import load_check  # noqa: E402

W0 = 1_000_000_000_000_000
SPAN = 10_000_000  # 10 s window
SNAP_FIELDS = ["unix_us", "seq", "stamp_us", "restore_us", "build_us", "send_us", "keys", "sends",
               "delta_messages", "full_messages", "section_updates", "near_sets_us", "kin_us"]
FRAME_FIELDS = ["unix_us", "total_us", "process_us", "sim_us", "after_us", "capture_us", "ticks",
                "oncpu_us", "preempt_us"]
ENTRIES = ["helm", "weapons", "engineering", "science", "relay", "comms"]


def make_run(tmp: Path, tick_us: int = 3000, age_us: int = 20_000, bytes_per_s: int = 6000,
             refused: bool = True) -> Path:
    frames, snaps, seconds, conns = [], [], [], []
    for i in range(600):
        t = W0 + i * SPAN // 600
        frames += [t, tick_us, 100, tick_us - 300, 100, 100, 1, tick_us, 0]
    for k in range(300):
        t = W0 + k * SPAN // 300
        snaps += [t, k + 1, t, 200, 1000, 500, 48, 64, 48, 0, 49, 100, 50]
    for s in range(12):
        t = W0 - 1_000_000 + s * 1_000_000
        seconds += [t, 900, 1000, 2000, 500]
        conns.append({str(c): [c, "k", bytes_per_s * s, 30 * s, 1, 30 * s, 0] for c in range(64)})
    probe = {
        "marks": {"window_start_unix_us": W0, "window_end_unix_us": W0 + SPAN},
        "frame_fields": FRAME_FIELDS, "frames": frames,
        "net": {"snap_fields": SNAP_FIELDS, "snaps": snaps,
                "second_fields": ["unix_us", "loops", "poll_us", "pump_us", "ops_us"],
                "seconds": seconds, "conns": conns},
        "sessions": {}, "server": {"ships": 12},
    }
    (tmp / "probe.json").write_text(json.dumps(probe))
    clients = []
    for c in range(64):
        entry = ENTRIES[c % 6] if c < 36 else ("captain" if c < 42 else "viewer")
        log = []
        for k in range(300):
            log += [k + 1, W0 + k * SPAN // 300 + age_us]
        clients.append({"seat": c, "name": f"load{c:02d}", "ship": c % 6, "entry": entry,
                        "session": c, "picked": "ok", "rejects": {},
                        "stats": {"bad_snapshots": 0}, "snaps": log})
    (tmp / "p0.json").write_text(json.dumps({"ok": True, "clients": clients}))
    reason = "session_full" if refused else "welcomed"
    (tmp / "p65.json").write_text(json.dumps({"full_probe": {"ok": refused, "reason": reason}}))
    (tmp / "host.txt").write_text("commit abc\nworld 12\nloadavg 1 1 1\n")
    (tmp / "host.tsv").write_text(
        "\n".join(f"{W0 + s * 1_000_000} 1.0 2300000 2300000 {s * 10_000} {s * 10}"
                  for s in range(-1, 12))
    )
    return tmp


def test_a_run_inside_every_budget_passes(tmp_path: Path) -> None:
    assert load_check.check(make_run(tmp_path), report_only=False) == 0


def test_a_slow_tick_fails(tmp_path: Path) -> None:
    assert load_check.check(make_run(tmp_path, tick_us=9000), report_only=False) == 1
    assert load_check.check(tmp_path, report_only=True) == 0


def test_late_snapshots_fail(tmp_path: Path) -> None:
    assert load_check.check(make_run(tmp_path, age_us=160_000), report_only=False) == 1


def test_too_many_bytes_fail(tmp_path: Path) -> None:
    # 64 x 25 kB/s = 12.8 Mbit/s
    assert load_check.check(make_run(tmp_path, bytes_per_s=25_000), report_only=False) == 1


def test_an_admitted_65th_connection_fails(tmp_path: Path) -> None:
    assert load_check.check(make_run(tmp_path, refused=False), report_only=False) == 1
