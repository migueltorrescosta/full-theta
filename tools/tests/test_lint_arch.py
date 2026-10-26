# FT: FT-ARC-010, FT-ARC-011, FT-ARC-016, FT-ARC-020, FT-ARC-021, FT-DAT-007, FT-SIM-035
"""Fixture tests for tools/lint_arch.py (T006; FT-ARC-010, FT-ARC-011, FT-ARC-020, FT-ARC-021,
FT-SIM-035).

Each pattern has a fixture root under fixtures/lint_arch/<pattern>/ with a `pass`
tree the lint accepts and a `fail` tree whose findings (file:line) are listed here.
"""

import subprocess
import sys
from pathlib import Path

import pytest

TOOLS = Path(__file__).resolve().parents[1]
FIXTURES = TOOLS / "tests/fixtures/lint_arch"

FAILS = {
    "extends": ["director/director.gd:3", "sim/world.gd:2"],
    "scene_tree": ["director/director.gd:4", "director/director.gd:4"],
    "io": ["shared/units.gd:4"] * 3 + ["shared/units.gd:5", "shared/units.gd:6"],
    "network": ["scenarios/raid.gd:3"],
    "load": ["sim/defs.gd:3", "sim/defs.gd:4", "sim/defs.gd:5"],
    # weapons.gd and hud.gd name the sim class World without any res://sim/ path.
    "station_sim": ["input/mapper.gd:3", "presentation/hud.gd:4", "stations/weapons.gd:3"],
    # sim/api/ is the only part of sim/ that director/ and scenarios/ may name.
    "pure_deps": [
        "audio/voice.gd:3",
        "director/director.gd:4",
        "director/director.gd:5",
        "scenarios/raid.gd:1",
        "scenarios/raid.gd:3",
        "scenarios/raid.gd:4",
        "sim/world.gd:4",
        "stations/helm.gd:4",
    ],
    "shared_deps": ["shared/lead.gd:3", "shared/lead.gd:4", "shared/lead.gd:5"],
    # Raw .px/.py/.pz reads and writes outside kinematics.gd and projectile_table.gd
    # (FT-SIM-035, D124); tests/ may read positions.
    "positions": [
        "shared/lead.gd:4",
        "sim/combat/hits.gd:4",
        "sim/combat/hits.gd:4",
        "sim/combat/hits.gd:7",
        "sim/combat/hits.gd:8",
    ],
}


def run(*args: str) -> subprocess.CompletedProcess[str]:
    cmd = [sys.executable, str(TOOLS / "lint_arch.py"), *args]
    return subprocess.run(cmd, capture_output=True, text=True)


def test_every_fixture_pattern_is_listed() -> None:
    assert sorted(p.name for p in FIXTURES.iterdir() if p.is_dir()) == sorted(FAILS)


@pytest.mark.parametrize("pattern", FAILS)
def test_pass_fixture_is_clean(pattern: str) -> None:
    result = run("--root", str(FIXTURES / pattern / "pass"))
    assert result.returncode == 0, result.stderr
    assert result.stderr == ""


@pytest.mark.parametrize("pattern", FAILS)
def test_fail_fixture_reports_each_violation(pattern: str) -> None:
    result = run("--root", str(FIXTURES / pattern / "fail"))
    assert result.returncode == 1
    found = [line.split(": ", 1)[0] for line in result.stderr.splitlines()]
    assert found == FAILS[pattern], result.stderr



# --- strand A: the real scenario case (FT-DAT-007) ---

SAMPLE_SCENARIO = """class_name EnemyWave
extends Scenario


func meta() -> ScenarioMeta:
    var m: ScenarioMeta = ScenarioMeta.new()
    m.id = &"enemy_wave"
    return m


func start(api: ScenarioApi, _params: Dictionary) -> void:
    api.spawn_at_range(&"raider", 2, 0, 3000.0, 12, 0)
"""


def real_tree(tmp_path: Path) -> Path:
    """A copy of the repo's sim/, director/, shared/, content/ and scenarios/ (a sample
    scenario when scenarios/ holds none yet) to put a violation into."""
    import shutil

    repo = TOOLS.parent
    for folder in ("sim", "director", "shared", "content", "scenarios"):
        shutil.copytree(
            repo / folder, tmp_path / folder, ignore=shutil.ignore_patterns("*.uid", "*.tres", "*.json")
        )
    if not list((tmp_path / "scenarios").glob("*.gd")):
        (tmp_path / "scenarios/enemy_wave.gd").write_text(SAMPLE_SCENARIO)
    return tmp_path


def test_real_scenarios_pass_and_one_reaching_simworld_fails(tmp_path: Path) -> None:
    root = real_tree(tmp_path)
    clean = run("--root", str(root))
    assert clean.returncode == 0, clean.stderr
    target = sorted((root / "scenarios").glob("*.gd"))[0]
    target.write_text(target.read_text() + "\nvar _world: SimWorld\n")
    bad = run("--root", str(root))
    assert bad.returncode == 1
    assert f"scenarios/{target.name}:" in bad.stderr
    assert "SimWorld from sim/" in bad.stderr


def test_the_real_director_cannot_name_the_world(tmp_path: Path) -> None:
    root = real_tree(tmp_path)
    director = root / "director/director.gd"
    director.write_text(director.read_text() + "\nvar _table: EncounterTable\n")
    bad = run("--root", str(root))
    assert bad.returncode == 1
    assert "director/director.gd:" in bad.stderr and "EncounterTable" in bad.stderr
