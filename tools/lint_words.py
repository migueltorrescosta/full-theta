#!/usr/bin/env python3
"""Retired-words lint: the words the glossary (docs/spec/README.md) and D392 to D407 retire.

Each rule in RULES names a retired word, what to use instead and the decision that retired it.
A rule's kind says where it applies:

- "name": an identifier, matched case-sensitively at identifier boundaries, on every line of
  our GDScript (tools/l0.sh's scripts list: tracked and untracked .gd files outside addons/ and
  tools/tests/fixtures/), every line of docs/spec/*.md and docs/protocol.md, and every key of the
  player-text JSON files below (string keys such as `sci.minigame_x` are names);
- "code": an identifier on every line of our GDScript only;
- "words": an English phrase, matched case-insensitively, on those code and doc lines and in
  English player text: every "en" value of content/i18n/strings.json, content/tips/*.json and
  content/dialogue/*.json (not the schemas);
- "player": an English word retired in player text only (where code and docs keep it in
  another sense, as session for a connection).

Nothing else is read, so docs/decisions.md (history), docs/research, docs/spikes, addons/,
tests/golden, the generated app/web/shell.html, tools/l1_times.json and tests/visual/baselines
are exempt.

The "unit suffix" rule (D403, bead w-483) flags names ending `_m`, `_s`, `_kg`, `_rad`, `_j` or `_w` in any case:
SI quantities carry no unit suffix, and a width is `_width`. Non-SI compounds (`_deg_s`, `_px_s`, `_spans_s`)
and `deg_to_rad` pass. tools/rename_units.py rewrites names from tools/rename_units.tsv.

ALLOW lists the legitimate uses: a path glob, a rule name ("*" for any), a regex the line (or
JSON key or value) must match, and the reason. An entry that drops nothing is itself a finding,
so stale entries go.

Usage: lint_words.py [--root DIR] [--no-unused]
Prints `path:line: word: retired (Dnnn); use ...` per finding and exits 1 on any.
"""

import argparse
import bisect
import fnmatch
import json
import re
import subprocess
import sys
from collections.abc import Callable
from pathlib import Path

# A name ending in an SI unit suffix (D403); tools/rename_units.py scans with the same pattern.
UNIT_NAME = r"(?i:[a-z_][a-z0-9_]*?(?<!_deg)(?<!_px)(?<!_spans)(?<!_to)_(?:m|s|kg|rad|j|w))"

# (rule name, kind, pattern, use instead, decision); kinds as in the module docstring.
RULES: list[tuple[str, str, str, str, str]] = [
    # D392: session is one player's connection (NetSession*, SessionTokenFile, WebSession and
    # HostSession keep it); the whole game is a game and Science's scan/hack is a minigame.
    ("ServerSession", "name", r"ServerSession|server_session", "NetGame", "D392"),
    ("SessionRules", "name", r"SessionRules", "GameRules", "D392"),
    ("SessionOutcome", "name", r"SessionOutcome|session_outcome", "GameOutcome, game_outcome", "D392"),
    ("SessionMode", "name", r"SessionMode|SESSION_MODE|session_mode", "GameMode, GAME_MODE, game_mode", "D392"),
    ("session_over", "name", r"session_over", "game_over", "D392"),
    ("SessionLog", "name", r"SessionLog|SessionSound", "ServerLog, ShellSound", "D392"),
    ("minigame session", "name", r"(?:scan|hack|sci|science)_sessions?|session_(?:target|noise|start|probe)|no_session", "minigame_*, no_minigame", "D392"),
    ("minigame session", "words", r"(?:scan|hack|minigame) sessions?", "minigame", "D392"),
    ("session (player text)", "player", r"sessions?", "game", "D392"),
    # D393: a scenario is the script, the map is the cube.
    ("site_period", "name", r"site_period", "map_period", "D393"),
    ("scenario map", "words", r"scenario maps?", "map", "D393"),
    # D394: a run is the fleet's playthrough; a ship has an outcome.
    ("RunTable", "name", r"RunTable", "ShipStateTable", "D394"),
    ("run_over", "name", r"run_over", "ship_outcome", "D394"),
    ("CloseRunCommand", "name", r"CloseRunCommand", "FinishShipCommand", "D394"),
    # D395: a seat is what a player picks; the wire field is seat, not entry.
    ("StationDef", "name", r"StationDef", "SeatDef", "D395"),
    ("entry (seat)", "name", r'(?<=["`])entry(?=["`])', "seat", "D395"),
    # D396: the sim knows only factions; team is a lobby label.
    ("team_of", "name", r"team_of", "the faction", "D396"),
    # D397: target is only what weapons, an AI or guidance aim at.
    ("SelectTargetCommand", "name", r"SelectTargetCommand|helm_select_target", "HelmSelectCommand, helm_select", "D397"),
    ("target_ship", "name", r"target_ship", "contact", "D397"),
    ("card target", "name", r"(?<=spec\.)target|target_flag", "subject", "D397"),
    ("target view", "words", r"target view", "close-up view", "D397"),
    # D398: net/ builders are sections, client decoders readers; view is a main-screen mode.
    ("*View", "name", r"(?:Comms|Science|Feeds|Hazard|Chip|Card|Ship|Site|Encounter|Tips|Qr|Space|Helm)View", "*Section, *Reader, *Info, TipsPanel, QrCode, SpaceScene, HelmScene", "D398"),
    ("StationViews", "name", r"StationViews|ViewFilter|NetViewState", "StationCatalogue, ShortcutFilter, SnapshotState", "D398"),
    ("SnapshotBuilder", "name", r"SnapshotBuilder", "SnapshotWriter", "D398"),
    ("view key", "words", r"view keys?", "stream key", "D398"),
    # D399: chip is only a request chip; the pulse is a sweep; NPCs are not all enemies.
    ("ChipText", "name", r"ChipText|ChipLayout|ControlsChip|SelectionChip", "CalloutText, CalloutLayout, ControlsHint, SelectionBar", "D399"),
    ("hint chip", "words", r"(?:\d+ s|sample-callout|hint|callsign|first-visit) chips?", "hint, callout label", "D399"),
    ("EnemyDef", "name", r"EnemyDef|EnemyAi|spawn_enemy", "NpcDef, NpcAi, spawn_npc", "D399"),
    ("sci_ping", "name", r"sci(?:ence)?_ping", "sci_sweep", "D399"),
    ("ping (sweep)", "words", r"active ping|sensor ping", "Sensor sweep", "D399"),
    ("enemy ship", "words", r"enemy ships?", "hostile ship", "D399"),
    ("enemy AI", "words", r"enemy (?:AI|keys?|catalogue)", "NPC AI, NPC key, NPC catalogue", "D399"),
    # D404: table rows are keyed by owner_ship and owner_faction.
    ("unit suffix", "code", UNIT_NAME, "no suffix on SI quantities: drop it or use a noun (FAR_DISTANCE, hit_energy); a width is _width", "D403"),
    ("key columns", "name", r"(?<=[.\"'`])(?:ship_ids|factions)(?![(])", "owner_ship, owner_faction", "D404"),
]

# (path glob, rule name, line regex, reason)
ALLOW: list[tuple[str, str, str, str]] = [
    # D403: a few names only look like units.
    ("sim/combat/collision_system.gd", "unit suffix", r"\b(?:inv|rel)_j\b", "j is the index of the second body, as in inv_i"),
    ("presentation/controls_diagram.gd", "unit suffix", r"\bwas_j\b", "j is the loop index of the segment"),
    ("tests/stations/test_client_settings.gd", "unit suffix", r"\bKEY_J\b", "Godot's Key enum"),
    ("stations/helm/helm_hud.gd", "unit suffix", r"helm\.range_m", "the translation key in content/i18n/strings.json, which holds its own names"),
    ("net/voice/piper_binary_synth.gd", "unit suffix", r"noise_w\b", "Piper's own command-line flag"),
    ("tests/net/voice/test_piper_adapters.gd", "unit suffix", r"noise_w\b", "Piper's own command-line flag"),
    ("docs/protocol.md", "*", r"^Protocol version: ", "the version history names the wire names each version changed"),
    ("docs/spec/14-open-questions.md", "SessionRules", r"^- D350:", "tools/traceability.py copies D350's title, which docs/decisions.md keeps as history"),
    # D396: a team is a lobby label; outside the sim a ship's team is still looked up by name.
    ("net/net_fleet.gd", "team_of", r"team_of", "the lobby's ship-to-team map, which the wire scoreboard and the winner's team use"),
    ("stations/crew_state.gd", "team_of", r"team_of", "the client's copy of the lobby's ship-to-team map"),
    ("stations/lobby_game_setup.gd", "team_of", r"team_of", "the Game setup sheet's team buttons read that map"),
    ("tests/net/test_fleet_lobby_l3.gd", "team_of", r"fleet\.team_of", "tests the lobby's ship-to-team map"),
    ("tests/sim/run/test_crew_factions.gd", "team_of", r"SimWorld\.team_of used to", "the regression note names the deleted function"),
]


def name_regex(pattern: str) -> re.Pattern[str]:
    return re.compile(rf"(?<![A-Za-z0-9_])(?:{pattern})(?![A-Za-z0-9_])")


def words_regex(pattern: str) -> re.Pattern[str]:
    return re.compile(rf"\b(?:{pattern})\b", re.I)


def compiled(rules=RULES) -> list[tuple[str, str, re.Pattern[str], str, str]]:
    return [
        (name, kind, name_regex(pattern) if kind in ("name", "code") else words_regex(pattern), use, decision)
        for name, kind, pattern, use, decision in rules
    ]


def code_files(root: Path) -> list[Path]:
    result = subprocess.run(
        ["git", "-C", str(root), "ls-files", "--cached", "--others", "--exclude-standard", "*.gd"],
        capture_output=True, text=True,
    )
    if result.returncode == 0:
        rels = [line for line in result.stdout.splitlines() if line]
    else:
        rels = [p.relative_to(root).as_posix() for p in sorted(root.rglob("*.gd"))]
    files = []
    for rel in rels:
        if rel.startswith("addons/") or rel.startswith("tools/tests/fixtures/"):
            continue
        files.append(root / rel)
    return files


def text_files(root: Path) -> list[Path]:
    files: list[Path] = []
    strings = root / "content/i18n/strings.json"
    if strings.is_file():
        files.append(strings)
    tips = root / "content/tips"
    if tips.is_dir():
        files.extend(sorted(tips.glob("*.json")))
    dialogue = root / "content/dialogue"
    if dialogue.is_dir():
        files.extend(p for p in sorted(dialogue.glob("*.json")) if not p.name.endswith(".schema.json"))
    return files


def line_of(lines: list[str], needle: str) -> int:
    for i, line in enumerate(lines, 1):
        if needle in line:
            return i
    return 1


def run(root: Path, rules=RULES, allow=ALLOW, check_unused=False) -> list[str]:
    root = Path(root)
    table = compiled(rules)
    name_rules = [(name, rx, use, decision) for name, kind, rx, use, decision in table if kind == "name"]
    text_rules = [(name, rx, use, decision) for name, kind, rx, use, decision in table if kind in ("words", "player")]
    line_rules = [(name, rx, use, decision) for name, kind, rx, use, decision in table if kind not in ("player", "code")]
    code_rules = line_rules + [(name, rx, use, decision) for name, kind, rx, use, decision in table if kind == "code"]
    findings: list[tuple[str, int, str, str, str]] = []
    used = [False] * len(allow)

    def check(rel: str, line_no: int | Callable[[], int], line_text: str, name: str, rx: re.Pattern[str], use: str, decision: str) -> None:
        m = rx.search(line_text)
        if not m:
            return
        for i, (glob, rule_name, line_regex, _reason) in enumerate(allow):
            if rule_name != "*" and rule_name != name:
                continue
            if not fnmatch.fnmatch(rel, glob):
                continue
            if re.search(line_regex, line_text):
                used[i] = True
                return
        findings.append((rel, line_no if isinstance(line_no, int) else line_no(), m.group(0), decision, use))

    def scan_lines(rel: str, text: str, rxs: list[tuple[str, re.Pattern[str], str, str]]) -> None:
        # Each rule scans the whole file once (fast), then checks each line it matched.
        starts = [0] + [m.end() for m in re.finditer("\n", text)]
        lines = text.split("\n")
        for name, rx, use, decision in rxs:
            seen: set[int] = set()
            for m in rx.finditer(text):
                i = bisect.bisect_right(starts, m.start())
                if i not in seen:
                    seen.add(i)
                    check(rel, i, lines[i - 1], name, rx, use, decision)

    # code: the same scripts as tools/l0.sh
    for path in code_files(root):
        rel = path.relative_to(root).as_posix()
        scan_lines(rel, path.read_text(encoding="utf-8"), code_rules)

    # player text: every key is a name, every "en" value is English
    for path in text_files(root):
        rel = path.relative_to(root).as_posix()
        raw = path.read_text(encoding="utf-8")
        lines = raw.splitlines()
        data = json.loads(raw)

        def walk(node: object) -> None:
            if isinstance(node, dict):
                for key, value in node.items():
                    for name, rx, use, decision in name_rules:
                        check(rel, lambda: line_of(lines, '"' + key + '"'), key, name, rx, use, decision)
                    if key == "en" and isinstance(value, str):
                        for name, rx, use, decision in text_rules:
                            check(rel, lambda: line_of(lines, json.dumps(value, ensure_ascii=False)[1:-1]), value, name, rx, use, decision)
                    walk(value)
            elif isinstance(node, list):
                for item in node:
                    walk(item)

        walk(data)

    # docs
    for path in [*sorted(root.glob("docs/spec/*.md")), *root.glob("docs/protocol.md")]:
        scan_lines(path.relative_to(root).as_posix(), path.read_text(encoding="utf-8"), line_rules)

    findings.sort(key=lambda f: (f[0], f[1]))
    out = [f"{rel}:{line}: {matched}: retired ({decision}); use {use}" for rel, line, matched, decision, use in findings]
    if check_unused:
        for i, (glob, rule_name, _line_regex, _reason) in enumerate(allow):
            if not used[i]:
                out.append(f"unused allowlist entry: {glob} {rule_name}")
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--no-unused", action="store_true", help="do not report unused allowlist entries")
    args = parser.parse_args()
    findings = run(args.root, check_unused=not args.no_unused)
    for f in findings:
        print(f"lint_words: {f}", file=sys.stderr)
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
