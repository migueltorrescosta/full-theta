#!/usr/bin/env python3
"""Architecture lint (T006): module purity and dependency rules of spec §2.2.

- Pure modules (sim/, director/, scenarios/, shared/) don't extend Node, touch the
  SceneTree, do I/O or networking, or load resources (FT-ARC-010, FT-ARC-020).
- Dependencies are checked on identifiers as well as res:// paths: every class_name
  in the repo resolves to its folder (top level, or sim/api/), and each module may
  name only the folders in ALLOWED (FT-ARC-010, FT-ARC-011, FT-ARC-016, FT-ARC-021,
  FT-DAT-007).
- Space wraps, so pure modules read and write the ship and projectile position columns
  (kin.pos_x, .pos_y, .pos_z and the projectiles') only through the Kinematics helpers;
  only the two files that own those columns touch them (FT-SIM-035, D124, D401). Other
  tables' `<role>_x` columns (sites, probes, aim points) are read directly by hot loops.
- ScenarioApi keeps the world in `_world`, which GDScript can't hide: pure modules
  outside sim/api/ may not access `._world` (FT-ARC-016).
- Every module is classified: a .gd file outside ALLOWED's modules and UNRESTRICTED is a
  finding, so a new top-level folder can't name anything by default (F9, R14-2).
- sim/ subpackages follow SIM_LAYERS: a file names only its own and lower layers; the
  composition roots (SIM_ROOTS) name any, and SIM_BACK_EDGES lists the back-edges that
  exist today, so no new one appears (F9, R14-3).
- Pure modules name only content/ definitions, never its loader classes (a content/ file
  that does I/O, loads resources or translates; F9, R14-5).
- Clients name only the client-safe part of net/ (NET_CLIENT_SAFE: protocol, codec, view
  keys and enums, readers), and those files name no sim/, director/ or server net/ class,
  so a client never compiles the server (F4, R14-1, D103).

A token scan over .gd files with comments and strings stripped; string contents are
checked only for res:// paths. Prints file:line messages and exits 1 on any finding.
"""

import argparse
import bisect
import re
import sys
from pathlib import Path

PURE = {"sim", "director", "scenarios", "shared"}
CLIENTS = {"stations", "input", "presentation", "audio"}
BASE = {"shared", "content"}
# Modules that may name anything (spec §2.2): the app that composes everything, the tests,
# the tools and the vendored addons. Every other .gd file's module must be in ALLOWED.
UNRESTRICTED = {"app", "tests", "tools", "addons"}
# Folders each module may name (spec §2.2). sim/api/ is the Scenario API, the only part of sim/ that
# director/ and scenarios/ see (FT-ARC-016, FT-DAT-007).
ALLOWED = {
    "sim": {"sim", "sim/api"} | BASE,
    "sim/api": {"sim", "sim/api"} | BASE,
    "director": {"director", "sim/api"} | BASE,
    "scenarios": {"scenarios", "sim/api"} | BASE,
    "shared": {"shared"},
    "content": BASE,
    "net": {"net", "sim", "sim/api", "director"} | BASE,
    **{c: CLIENTS | {"net"} | BASE for c in CLIENTS},
}
# sim/ subpackages, lowest first (R14-3): core tables and helpers, then the systems, then
# story and economy, the run, flight, hazards and the AI on top. A file names its own layer
# and those below it.
SIM_LAYERS = [
    "core", "damage", "power", "knowledge", "combat", "relay", "shields", "science",
    "story", "economy", "run", "flight", "hazard", "ai", "api",
]
# The world and the command registry put every subpackage together.
SIM_ROOTS = {"sim/core/sim_world.gd", "sim/core/sim_commands.gd", "sim/core/hit_resolver.gd"}
# Back-edges that exist today (file, class named): each is a cycle to untangle, none may be
# added (R14-3; remove an entry when its edge goes).
SIM_BACK_EDGES = {
    ("sim/combat/guidance_system.gd", "ProbeSystem"),
    ("sim/combat/guidance_system.gd", "ScienceSystem"),
    ("sim/damage/damage_system.gd", "KnowledgeSystem"),
    ("sim/damage/damage_table.gd", "PowerSystem"),
    ("sim/knowledge/knowledge_system.gd", "ProbeSystem"),
    ("sim/knowledge/knowledge_system.gd", "ScienceKnowledge"),
    ("sim/run/m1_encounter.gd", "HazardSystem"),
    ("sim/run/outcome_system.gd", "AiTable"),
    ("sim/run/run_setup.gd", "HazardSystem"),
    ("sim/science/science_knowledge.gd", "StoryRules"),
    ("sim/story/story.gd", "Reputation"),
    ("sim/story/story_rules.gd", "Economy"),
    ("sim/story/story_rules.gd", "Reputation"),
}
# The net/ files clients may name (F4, R14-1): the wire protocol and codec, view keys and
# enums, and the readers of snapshots and events. They name only each other, shared/ and
# content/; every other net/ file is the server's.
NET_CLIENT_SAFE = {
    "net/block_schema.gd",
    "net/chip_view.gd",
    "net/crew_marks.gd",
    "net/data_toggles.gd",
    "net/fleet_messages.gd",
    "net/load_probe.gd",
    "net/main_screen.gd",
    "net/net_block.gd",
    "net/net_chunker.gd",
    "net/net_client.gd",
    "net/net_codec.gd",
    "net/net_event_inbox.gd",
    "net/net_protocol.gd",
    "net/net_send_queue.gd",
    "net/net_view_state.gd",
    "net/snapshot_reader.gd",
    "net/station_def.gd",
    "net/station_views.gd",
    "net/view_filter.gd",
    "net/voice/dialogue_lines.gd",
}
# Tokens that make a content/ file a loader rather than a definition (R14-5).
LOADER_TOKENS = {"FileAccess", "DirAccess", "ResourceLoader", "TranslationServer"}
PURE_BASES = {"RefCounted", "Object", "Resource"}
BANNED = {
    "scene tree access": {"SceneTree", "get_tree", "get_main_loop", "get_node"},
    "I/O": {"FileAccess", "DirAccess", "OS", "ResourceSaver"},
    "networking": {
        "HTTPClient", "HTTPRequest", "IP", "StreamPeerTCP", "StreamPeerTLS", "TCPServer",
        "PacketPeerUDP", "PacketPeerDTLS", "UDPServer", "DTLSServer", "WebSocketPeer",
        "WebSocketMultiplayerPeer", "ENetConnection", "ENetMultiplayerPeer",
        "MultiplayerAPI", "MultiplayerPeer", "WebRTCPeerConnection", "WebRTCMultiplayerPeer",
    },
    "resource loading": {"ResourceLoader"},
}
LOADERS = {"load", "preload"}  # banned only as bare calls, not as methods (x.load())
SKIP_PREFIX = ("tools/tests/fixtures/",)
# Position columns, the receivers that name the ship and projectile tables, and the files
# that own them (FT-SIM-035, D124, D401).
POSITION_COLUMNS = {"pos_x", "pos_y", "pos_z"}
POSITION_RECEIVERS = {"kin", "kinematics", "proj", "projectiles"}
# Scenario API members that hold the world; GDScript has no private, so the lint does.
PRIVATE_API = {"_world"}
POSITION_OWNERS = {"sim/core/kinematics.gd", "sim/combat/projectile_table.gd"}


def receiver(code: str, dot: int) -> str:
    """The identifier just before the dot at code[dot] (spaces skipped), or ""."""
    k = dot - 1
    while k >= 0 and code[k] in " \t":
        k -= 1
    m = re.search(r"\w+$", code[: k + 1])
    return m.group() if m else ""


def strip(text: str) -> tuple[str, list[tuple[int, str]]]:
    """Returns the code with comments and strings blanked (newlines kept) and the
    strings with their offsets."""
    code, strings, i, n = [], [], 0, len(text)
    while i < n:
        c = text[i]
        if c == "#":
            while i < n and text[i] != "\n":
                i += 1
            continue
        if c in "\"'":
            raw = i > 0 and text[i - 1] == "r"
            quote = text[i : i + 3] if text[i : i + 3] in ('"""', "'''") else c
            start, i = i, i + len(quote)
            while i < n and not text.startswith(quote, i):
                i += 2 if text[i] == "\\" and not raw else 1
            i = min(i + len(quote), n)
            strings.append((start, text[start:i]))
            code.append("".join("\n" if ch == "\n" else " " for ch in text[start:i]))
            continue
        code.append(c)
        i += 1
    return "".join(code), strings


def module_of(rel: str) -> str:
    if rel.startswith("sim/api/"):
        return "sim/api"
    return rel.split("/", 1)[0] if "/" in rel else ""


def may_name(module: str, target: str) -> bool:
    return target == module or target in ALLOWED.get(module, {target})


def sim_layer(rel: str) -> str | None:
    """The SIM_LAYERS entry of a file in a sim/ subpackage, or None (not in one)."""
    parts = rel.split("/")
    return parts[1] if parts[0] == "sim" and len(parts) > 2 and parts[1] in SIM_LAYERS else None


def is_loader(code: str) -> bool:
    """Whether a content/ file does I/O, loads resources or translates."""
    words = set(re.findall(r"[A-Za-z_]\w*", code))
    bare_load = re.search(r"(?<![.\w])(load|preload)\s*\(", code) is not None
    return bool(words & LOADER_TOKENS) or bare_load


def lint(root: Path) -> list[str]:
    files, errors = {}, []
    for path in sorted(root.rglob("*.gd")):
        rel = path.relative_to(root).as_posix()
        if any(p.startswith(".") for p in rel.split("/")) or rel.startswith(SKIP_PREFIX):
            continue
        files[rel] = strip(path.read_text(encoding="utf-8"))
    classes, class_file, loaders = {}, {}, set()
    for rel, (code, _) in files.items():
        for m in re.finditer(r"\bclass_name\s+(\w+)", code):
            classes[m.group(1)] = module_of(rel)
            class_file[m.group(1)] = rel
            if module_of(rel) == "content" and is_loader(code):
                loaders.add(m.group(1))

    for rel, (code, strings) in files.items():
        module = module_of(rel)
        lines = [m.start() for m in re.finditer("\n", code)]

        def report(pos: int, msg: str) -> None:
            errors.append((rel, bisect.bisect_left(lines, pos) + 1, msg))

        if module not in ALLOWED and module not in UNRESTRICTED:
            report(0, f"{module or 'the root'}/ is not a classified module: add it to "
                   "tools/lint_arch.py ALLOWED or UNRESTRICTED (spec §2.2)")
        layer = None if rel in SIM_ROOTS else sim_layer(rel)
        client_safe = rel in NET_CLIENT_SAFE

        for pos, s in strings:
            for m in re.finditer(r"res://([^\"']+/)", s):
                target = module_of(m.group(1))
                if not may_name(module, target):
                    report(pos, f"{module}/ must not use res://{target}/ (spec §2.2)")
        for m in re.finditer(r"[A-Za-z_]\w*", code):
            word, pos = m.group(), m.start()
            j = pos - 1
            while j >= 0 and code[j] in " \t":
                j -= 1
            dotted = j >= 0 and code[j] == "."
            target = classes.get(word)
            if target is not None and not dotted and not may_name(module, target):
                report(pos, f"{module}/ must not use {word} from {target}/ (spec §2.2)")
            elif target is not None and not dotted:
                where = class_file[word]
                if module in CLIENTS and target == "net" and where not in NET_CLIENT_SAFE:
                    report(pos, f"{module}/ must not use {word}: {where} is the server's; "
                           "clients name only NET_CLIENT_SAFE (F4, D103)")
                if client_safe and where != rel and (
                    target in {"sim", "sim/api", "director"}
                    or (target == "net" and where not in NET_CLIENT_SAFE)
                ):
                    report(pos, f"{word}: client-safe {rel} must not name {where} (F4, D103)")
                to_layer = sim_layer(where)
                if (
                    layer is not None and to_layer is not None
                    and SIM_LAYERS.index(to_layer) > SIM_LAYERS.index(layer)
                    and (rel, word) not in SIM_BACK_EDGES
                ):
                    report(pos, f"sim/{layer}/ must not use {word} from the higher sim/{to_layer}/ "
                           "(SIM_LAYERS, R14-3)")
                if module.split("/")[0] in PURE and word in loaders:
                    report(pos, f"{word}: {module}/ may name content/ definitions, not loaders "
                           "(FT-ARC-020, R14-5)")
            if module.split("/")[0] not in PURE:
                continue
            for what, names in BANNED.items():
                if word in names:
                    ft = "FT-ARC-020" if what == "resource loading" else "FT-ARC-010"
                    report(pos, f"{word}: no {what} in {module}/ ({ft})")
            if (
                word in POSITION_COLUMNS and dotted and rel not in POSITION_OWNERS
                and receiver(code, j) in POSITION_RECEIVERS
            ):
                report(pos, f".{word}: use Kinematics.relative, relative_to_point, relative_to_column, "
                       "point, point_at, wrap, place or translate, not raw position columns "
                       "(FT-SIM-035, D124, D401)")
            if word in PRIVATE_API and dotted and module != "sim/api":
                report(pos, f".{word}: the Scenario API's world is private; GDScript can't hide it, "
                       "so only sim/api/ may reach it (FT-ARC-016)")
            if word in LOADERS and not dotted and code[m.end() :].lstrip().startswith("("):
                report(pos, f"{word}(): no resource loading in {module}/ (FT-ARC-020)")
        if module.split("/")[0] in PURE:
            for m in re.finditer(r"\bextends\s+(\w+)", code):
                base = m.group(1)
                if base not in PURE_BASES and base not in classes:
                    report(m.start(), f"extends {base}: {module}/ may extend only "
                           "RefCounted, Resource, Object or repo classes (FT-ARC-010)")
    return [f"{rel}:{line}: {msg}" for rel, line, msg in sorted(errors)]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    errors = lint(parser.parse_args().root)
    for error in errors:
        print(error, file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
