# FT: FT-TST-011
"""tools/l4/check.py: a relaunched client stays in the run it left, so its KIN hashes are
compared with the other clients' in that run (a run reset restarts the tick)."""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "l4"))
import check  # noqa: E402


def log(path: Path, snaps: list[tuple[int, str]], end: bool = True) -> None:
    lines = [{"ev": "snap", "tick": t, "k": k, "gap_ms": 0} for t, k in snaps]
    if end:
        lines.append({"ev": "end", "ok": True, "stats": {}})
    path.write_text("\n".join(json.dumps(x) for x in lines) + "\n")


def test_a_relaunch_after_a_reset_counts_its_run_on(tmp_path: Path) -> None:
    # Run 0 ticks 10 and 20, then the reset; run 1 tick 10 has another state.
    log(tmp_path / "b.1.jsonl", [(10, "r0"), (20, "r0b"), (10, "r1")])
    log(tmp_path / "a.1.jsonl", [(10, "r0"), (20, "r0b")], end=False)
    log(tmp_path / "a.2.jsonl", [(10, "r1")])
    (tmp_path / "events.txt").write_text("1.0 SIGKILL a\n")
    assert check.check(tmp_path) == []


def test_a_real_divergence_in_the_same_run_fails(tmp_path: Path) -> None:
    log(tmp_path / "b.1.jsonl", [(10, "x")])
    log(tmp_path / "a.1.jsonl", [(10, "y")])
    assert any("KIN differs" in p for p in check.check(tmp_path))
