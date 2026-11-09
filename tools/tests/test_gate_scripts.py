"""Fixture tests for the gate plumbing: tools/run_limited.sh, tools/lib.sh, the L1 split
and the CI shard matrix. None needs Godot."""

import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import l1_shards  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent.parent
RUN_LIMITED = ROOT / "tools/run_limited.sh"
LIB = ROOT / "tools/lib.sh"


def run_limited(tmp_path: Path, done: str | None) -> subprocess.CompletedProcess:
    """Runs a command that never exits under run_limited.sh with a 3 s limit."""
    if done is not None:
        (tmp_path / "done.txt").write_text(done + "\n")
    return subprocess.run(
        [str(RUN_LIMITED), "3", str(tmp_path / "hang-stack.txt"), "sleep", "60"],
        env={"PATH": "/usr/bin:/bin", "EXIT_GRACE": "1"},
        capture_output=True,
        text=True,
        timeout=40,
    )


def test_a_hang_after_a_passed_run_is_kept_as_a_pass(tmp_path: Path) -> None:
    r = run_limited(tmp_path, "passed")
    assert r.returncode == 0
    assert "every test finished and passed" in r.stderr


def test_a_hang_without_the_done_marker_fails(tmp_path: Path) -> None:
    assert run_limited(tmp_path, None).returncode == 124


def test_a_hang_after_a_failed_run_fails(tmp_path: Path) -> None:
    assert run_limited(tmp_path, "failed").returncode == 124


def lib(script: str, tmp_path: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["bash", "-c", f"source {LIB}; {script}"],
        cwd=tmp_path,
        capture_output=True,
        text=True,
        timeout=30,
    )


def test_wait_ready_parses_the_ready_line(tmp_path: Path) -> None:
    (tmp_path / "s.log").write_text("noise\nready ws=127.0.0.1:5001 http=127.0.0.1:5000\n")
    r = lib('ft_wait_ready s.log $$ 2 && echo "$WS_URL $HTTP_URL"', tmp_path)
    assert r.stdout.strip() == "ws://127.0.0.1:5001 http://127.0.0.1:5000"
    (tmp_path / "s.log").write_text("ready ws=127.0.0.1:5001 http=127.0.0.1:0\n")
    r = lib('ft_wait_ready s.log $$ 2 && echo "$WS_URL [$HTTP_URL]"', tmp_path)
    assert r.stdout.strip() == "ws://127.0.0.1:5001 []"


def test_wait_ready_fails_loudly_when_the_server_died(tmp_path: Path) -> None:
    (tmp_path / "s.log").write_text("boom\n")
    r = lib("sleep 0 & p=$!; wait $p; ft_wait_ready s.log $p 5", tmp_path)
    assert r.returncode == 1
    assert "exited before it was ready: boom" in r.stderr


def test_wait_for_times_out_loudly(tmp_path: Path) -> None:
    r = lib("ft_wait_for 'a thing' 1 false", tmp_path)
    assert r.returncode == 1
    assert "timed out waiting for a thing" in r.stderr


def test_pick_cpus_stays_inside_the_allowed_set_and_skips_excluded(tmp_path: Path) -> None:
    r = lib("taskset -c 0,1,2,3 bash -c 'source " + str(LIB) + "; ft_pick_cpus 2; ft_pick_cpus 4 0'", tmp_path)
    first, second = r.stdout.split()
    assert set(first.split(",")) <= {"0", "1", "2", "3"}
    assert "0" not in second.split(",")


def test_every_l1_test_file_lands_in_exactly_one_shard() -> None:
    files = l1_shards.test_files()
    parts = l1_shards.shards(files, {}, 3)
    assert sorted(f for part in parts for f in part) == files


def test_the_ci_matrix_runs_every_shard_once() -> None:
    ci = (ROOT / ".github/workflows/ci.yml").read_text()
    shards = [int(x) for x in re.search(r"shard: \[([\d, ]+)\]", ci).group(1).split(",")]
    n = int(re.search(r"\bn: \[(\d+)\]", ci).group(1))
    assert shards == list(range(n))
