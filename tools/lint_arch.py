#!/usr/bin/env python3
"""Architecture lint (T006): module purity and dependency rules of spec §2.2.

- Pure modules (sim/, director/, scenarios/, shared/) don't extend Node, touch the
  SceneTree, do I/O or networking, or load resources (FT-ARC-010, FT-ARC-020).
- Dependencies are checked on identifiers as well as res:// paths: every class_name
  in the repo resolves to its folder (top level, or sim/api/), and each module may
  name only the folders in ALLOWED (FT-ARC-010, FT-ARC-011, FT-ARC-016, FT-ARC-021,
  FT-DAT-007).
- Space wraps per site, so pure modules read and write the position columns (.px,
  .py, .pz) only through the Kinematics helpers; only the two files that own the
  columns touch them (FT-SIM-035, D124).

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
# Folders each module may name (spec §2.2); modules not listed (app/, tests/, tools/)
# may name anything. sim/api/ is the Scenario API, the only part of sim/ that
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
# Position columns, and the files that own them (FT-SIM-035, D124).
POSITION_COLUMNS = {"px", "py", "pz"}
POSITION_OWNERS = {"sim/core/kinematics.gd", "sim/combat/projectile_table.gd"}


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


def lint(root: Path) -> list[str]:
    files, errors = {}, []
    for path in sorted(root.rglob("*.gd")):
        rel = path.relative_to(root).as_posix()
        if any(p.startswith(".") for p in rel.split("/")) or rel.startswith(SKIP_PREFIX):
            continue
        files[rel] = strip(path.read_text(encoding="utf-8"))
    classes = {}
    for rel, (code, _) in files.items():
        for m in re.finditer(r"\bclass_name\s+(\w+)", code):
            classes[m.group(1)] = module_of(rel)

    for rel, (code, strings) in files.items():
        module = module_of(rel)
        lines = [m.start() for m in re.finditer("\n", code)]

        def report(pos: int, msg: str) -> None:
            errors.append((rel, bisect.bisect_left(lines, pos) + 1, msg))

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
            if module.split("/")[0] not in PURE:
                continue
            for what, names in BANNED.items():
                if word in names:
                    ft = "FT-ARC-020" if what == "resource loading" else "FT-ARC-010"
                    report(pos, f"{word}: no {what} in {module}/ ({ft})")
            if word in POSITION_COLUMNS and dotted and rel not in POSITION_OWNERS:
                report(pos, f".{word}: use Kinematics.relative, relative_to_point, distance, "
                       "point_at or wrap, not raw position columns (FT-SIM-035, D124)")
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
