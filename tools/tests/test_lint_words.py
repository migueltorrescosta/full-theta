"""Fixture tests for tools/lint_words.py (the retired-words lint, D392 to D407).

Each scope (code, text, docs) has a fixture root under fixtures/lint_words/<case>/ with a
`pass` tree the lint accepts and a `fail` tree whose findings (path:line) are listed here;
the `allow` case is one tree with an allowlisted use. SAMPLES gives every rule one use it flags.
"""

import json
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import lint_words  # noqa: E402

TOOLS = Path(__file__).resolve().parents[1]
FIXTURES = TOOLS / "tests/fixtures/lint_words"

FAILS = {
    "code": [
        "net/server.gd:1",
        "net/server.gd:4",
        "net/server.gd:4",
    ],
    "text": [
        "content/dialogue/npc.json:3",
        "content/i18n/strings.json:4",
        "content/i18n/strings.json:4",
        "content/i18n/strings.json:5",
        "content/tips/tips.json:4",
    ],
    "docs": [
        "docs/protocol.md:3",
        "docs/spec/01-a.md:3",
        "docs/spec/01-a.md:5",
    ],
}
PASS_CASES = {"code", "text", "docs"}
CASES = set(FAILS) | {"allow"}


def run_cli(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run([sys.executable, str(TOOLS / "lint_words.py"), *args], capture_output=True, text=True)


def prefixes(stderr: str) -> list[str]:
    out = []
    for line in stderr.splitlines():
        assert line.startswith("lint_words: "), line
        body = line[len("lint_words: "):]
        sep = body.find(": ")
        rel, line_no = body[:sep].rsplit(":", 1)
        out.append(f"{rel}:{line_no}")
    return out


def test_every_fixture_case_dir_is_listed() -> None:
    assert sorted(p.name for p in FIXTURES.iterdir() if p.is_dir()) == sorted(CASES)


@pytest.mark.parametrize("case", sorted(PASS_CASES))
def test_pass_fixture_is_clean(case: str) -> None:
    result = run_cli("--no-unused", "--root", str(FIXTURES / case / "pass"))
    assert result.returncode == 0, result.stderr
    assert result.stderr == "", result.stderr


@pytest.mark.parametrize("case", sorted(FAILS))
def test_fail_fixture_reports_each_violation(case: str) -> None:
    result = run_cli("--no-unused", "--root", str(FIXTURES / case / "fail"))
    assert result.returncode == 1, result.stderr
    assert prefixes(result.stderr) == FAILS[case], result.stderr


LIVE_RUN = [("tests/sim/replay/live_run.gd", "site_period", r"site_period", "legacy replays")]


def test_allowlist_drops_a_matching_line_and_counts_as_used() -> None:
    root = FIXTURES / "allow" / "tree"
    assert lint_words.run(root, allow=[], check_unused=True) == [
        "tests/sim/replay/live_run.gd:1: site_period: retired (D393); use map_period",
        "tests/sim/replay/live_run.gd:3: site_period: retired (D393); use map_period",
    ]
    assert lint_words.run(root, allow=LIVE_RUN, check_unused=True) == []


def test_unused_allowlist_entry_is_reported() -> None:
    extra = [("tests/sim/replay/other.gd", "*", r"zzz_unused", "unused entry for the test")]
    found = lint_words.run(FIXTURES / "allow" / "tree", allow=LIVE_RUN + extra, check_unused=True)
    assert found == ["unused allowlist entry: tests/sim/replay/other.gd *"], found


# One retired use per rule, as the line it would appear on (code, docs) or "en:" player text.
SAMPLES = {
    "ServerSession": "var game: ServerSession",
    "SessionRules": "SessionRules.HOLDOUT_CAP",
    "SessionOutcome": "func session_outcome() -> int:",
    "SessionMode": "Type.SESSION_MODE",
    "session_over": '"session_over"',
    "SessionLog": "var log: SessionLog",
    "minigame session": "var t: int = sci.session_target[ship]",
    "session (player text)": "en:The host picks one language for the session.",
    "site_period": 'setup["site_period"]',
    "scenario map": "# wraps the scenario map",
    "RunTable": "var ships: RunTable",
    "run_over": "EVENT_RUN_OVER = &\"run_over\"",
    "CloseRunCommand": "CloseRunCommand.new()",
    "StationDef": "var def: StationDef",
    "entry (seat)": 'p["entry"]',
    "team_of": "world.team_of(ship)",
    "SelectTargetCommand": '{"kind": "helm_select_target"}',
    "target_ship": "cmd.target_ship = 3",
    "card target": "spec.target = ship",
    "target view": "# the target view follows the selection",
    "*View": "var v: CommsView",
    "StationViews": "StationViews.BLOCKS",
    "SnapshotBuilder": "SnapshotBuilder.new()",
    "view key": "# one view key per client",
    "ChipText": "ChipText.of(ship)",
    "hint chip": "# a 6 s chip names the Controls key",
    "EnemyDef": "defs.spawn_enemy(&\"raider\")",
    "sci_ping": '"kind": "science_ping"',
    "ping (sweep)": "en:Active ping ready.",
    "enemy ship": "en:That's an enemy ship.",
    "enemy AI": "# the enemy AI attacks",
    "key columns": "table.ship_ids[row]",
}


def test_every_rule_has_a_sample() -> None:
    assert sorted(SAMPLES) == sorted({rule[0] for rule in lint_words.RULES})


@pytest.mark.parametrize("name", sorted(SAMPLES))
def test_each_rule_flags_its_sample(tmp_path: Path, name: str) -> None:
    sample = SAMPLES[name]
    if sample.startswith("en:"):
        (tmp_path / "content/i18n").mkdir(parents=True)
        strings = {"strings": {"k": {"en": sample[3:]}}}
        (tmp_path / "content/i18n/strings.json").write_text(json.dumps(strings))
    else:
        (tmp_path / "x.gd").write_text(sample + "\n")
    rules = [r for r in lint_words.RULES if r[0] == name]
    assert len(lint_words.run(tmp_path, rules=rules, allow=[])) == 1, sample


def test_player_rules_skip_code_and_name_rules_skip_player_text(tmp_path: Path) -> None:
    (tmp_path / "x.gd").write_text("## The session's connection.\n")
    (tmp_path / "content/i18n").mkdir(parents=True)
    (tmp_path / "content/i18n/strings.json").write_text('{"strings": {"k": {"en": "No RunTable here"}}}')
    assert lint_words.run(tmp_path, allow=[]) == []


def test_run_accepts_replacement_rules(tmp_path: Path) -> None:
    (tmp_path / "demo.gd").write_text("var table: RunTable\n")
    rules = [("RunTable", "name", r"RunTable", "ShipStateTable", "D394")]
    assert lint_words.run(tmp_path, rules=rules, allow=[]) == ["demo.gd:1: RunTable: retired (D394); use ShipStateTable"]
