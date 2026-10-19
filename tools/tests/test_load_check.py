# FT: FT-NET-040, FT-NET-014
"""Fixture tests for tools/l4/load_check.py (#11 load gate, D161) on synthetic runs: a
run inside every budget passes, and each broken budget or check fails it on its own."""

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
        seconds += [t, 900, 1000, 2000, 500, 3000]
        conns.append({str(c): [c, "k", bytes_per_s * s, 30 * s, 1, 30 * s, 0, 0] for c in range(64)})
    probe = {
        "marks": {"window_start_unix_us": W0, "window_end_unix_us": W0 + SPAN,
                  "launched_at_start": 6, "launched_at_end": 6},
        "frame_fields": FRAME_FIELDS, "frames": frames,
        "net": {"snap_fields": SNAP_FIELDS, "snaps": snaps,
                "second_fields": ["unix_us", "loops", "poll_us", "pump_us", "ops_us", "snapshot_us"],
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


def _edit(d: Path, name: str, fn) -> None:
    p = d / name
    doc = json.loads(p.read_text())
    fn(doc)
    p.write_text(json.dumps(doc))


def _fails(tmp: Path, name: str, fn) -> bool:
    make_run(tmp)
    _edit(tmp, name, fn)
    return load_check.check(tmp, report_only=False) == 1


def _every_other_frame(p: dict) -> None:
    n = len(p["frame_fields"])
    fr = p["frames"]
    p["frames"] = [x for i in range(0, len(fr), n) if (i // n) % 2 == 0 for x in fr[i : i + n]]


def _shift_ages(p: dict) -> None:
    for c in p["clients"]:
        c["snaps"] = [v - (200_000 if i % 2 else 0) for i, v in enumerate(c["snaps"])]


def _stall(p: dict) -> None:
    for c in p["net"]["conns"]:
        for k, v in c.items():
            c[k] = v[:6] + [5, 0]


def _two_messages_per_key(p: dict) -> None:
    n = len(p["net"]["snap_fields"])
    i_full = p["net"]["snap_fields"].index("full_messages")
    for i in range(0, len(p["net"]["snaps"]), n):
        p["net"]["snaps"][i + i_full] = 5


def test_fewer_ticks_than_real_time_fail(tmp_path: Path) -> None:
    assert _fails(tmp_path, "probe.json", _every_other_frame)


def test_a_ship_that_never_started_fails(tmp_path: Path) -> None:
    assert _fails(tmp_path, "probe.json", lambda p: p["marks"].update(launched_at_end=1))


def test_an_incomplete_window_fails(tmp_path: Path) -> None:
    assert _fails(tmp_path, "probe.json", lambda p: p["marks"].pop("window_end_unix_us"))


def test_a_single_byte_sample_fails(tmp_path: Path) -> None:
    def one(p: dict) -> None:
        p["net"]["seconds"] = p["net"]["seconds"][:6]
        p["net"]["conns"] = p["net"]["conns"][:1]

    assert _fails(tmp_path, "probe.json", one)


def test_negative_ages_fail(tmp_path: Path) -> None:
    assert _fails(tmp_path, "p0.json", _shift_ages)


def test_stalls_fail(tmp_path: Path) -> None:
    assert _fails(tmp_path, "probe.json", _stall)


def test_more_messages_than_view_keys_fail(tmp_path: Path) -> None:
    assert _fails(tmp_path, "probe.json", _two_messages_per_key)


def test_a_silent_client_fails(tmp_path: Path) -> None:
    assert _fails(tmp_path, "p0.json", lambda p: p["clients"][3].update(snaps=[]))


def test_clients_missing_half_the_snapshots_fail(tmp_path: Path) -> None:
    def half(p: dict) -> None:
        for c in p["clients"]:
            c["snaps"] = c["snaps"][:300]

    assert _fails(tmp_path, "p0.json", half)


def test_a_wrong_seat_plan_fails(tmp_path: Path) -> None:
    assert _fails(tmp_path, "p0.json", lambda p: p["clients"][0].update(entry="viewer"))


def test_few_snapshots_scaled_to_30_hz_fail(tmp_path: Path) -> None:
    # 1 snapshot a second at 6 kB/s per client would be 92 Mbit/s at 30 a second.
    def few(p: dict) -> None:
        n = len(p["net"]["snap_fields"])
        s = p["net"]["snaps"]
        p["net"]["snaps"] = [x for i in range(0, len(s), n) if (i // n) % 30 == 0 for x in s[i : i + n]]

    assert _fails(tmp_path, "probe.json", few)
