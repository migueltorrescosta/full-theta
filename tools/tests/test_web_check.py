# FT: FT-TST-021
"""tools/l4/web_check.py on synthetic server logs: a browser that joined, rejoined and
sent commands passes; a missing resumed join fails."""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "l4"))
import web_check  # noqa: E402


def write(path: Path, lines: list[dict]) -> Path:
    path.write_text("\n".join(json.dumps(x) for x in lines) + "\n")
    return path


def good() -> list[dict]:
    web = {"client": "web", "n": 40, "age_p50_ms": 50, "age_p99_ms": 200, "gap_p99_ms": 100}
    return [
        {"kind": "join", "client": "web", "resumed": False},
        {"kind": "join", "client": "web", "resumed": True},
        {"kind": "snapshot_age", "clients": [web]},
        {"kind": "summary", "counters": {"commands": 5}},
    ]


def test_a_browser_that_rejoined_passes(tmp_path: Path) -> None:
    assert web_check.main(write(tmp_path / "s.jsonl", good())) == 0


def test_no_resumed_join_fails(tmp_path: Path, capsys) -> None:
    lines = [x for x in good() if not x.get("resumed")]
    assert web_check.main(write(tmp_path / "s.jsonl", lines)) == 1
    assert "no resumed join" in capsys.readouterr().out
