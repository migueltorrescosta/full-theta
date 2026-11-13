#!/usr/bin/env python3
"""Drops SI unit suffixes from identifiers (D403, bead w-483) from the table tools/rename_units.tsv.

Table columns: old<TAB>new<TAB>scope<TAB>note (scope: a path glob or `*`; `#` starts a comment).
Each `old` is replaced at identifier boundaries in tracked *.gd, *.tscn and *.tres files outside
addons/, tests/golden and tests/visual/baselines. Inside a string literal only a string that is
the identifier alone (a dict key such as "left_s") changes; CLI flags and translation keys stay.

Usage: rename_units.py [--check | --scan]
  (none)   edit in place, print `N renames in M files`
  --check  print each change as file:line, exit 1 if any
  --scan   list identifiers with a unit suffix that the table and lint_words.ALLOW do not cover
"""

import argparse
import fnmatch
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lint_words  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
TABLE = Path(__file__).with_name("rename_units.tsv")
SKIP = ("addons/", "tests/golden/", "tests/visual/baselines/")
TOKEN = re.compile(r'"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'|#.*|[A-Za-z_][A-Za-z0-9_]*')
IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


def load_table() -> list[tuple[str, str, str]]:
    rows = []
    for line in TABLE.read_text(encoding="utf-8").splitlines():
        if line.strip() and not line.startswith("#"):
            old, new, scope, *_ = line.split("\t")
            rows.append((old, new, scope))
    return rows


def files() -> list[str]:
    out = subprocess.run(["git", "-C", str(ROOT), "ls-files", "*.gd", "*.tscn", "*.tres"], capture_output=True, text=True, check=True)
    return [f for f in out.stdout.splitlines() if not f.startswith(SKIP)]


def rewrite(line: str, names: dict[str, str]) -> tuple[str, list[str]]:
    hits: list[str] = []

    def fix(m: re.Match[str]) -> str:
        text = m.group(0)
        if text[0] in "\"'":
            inner = text[1:-1]
            if inner in names and IDENT.fullmatch(inner):
                hits.append(inner)
                return text[0] + names[inner] + text[0]
            return text
        if text[0] == "#":
            return IDENT.sub(lambda i: hit(i.group(0)), text)
        return hit(text)

    def hit(word: str) -> str:
        if word in names:
            hits.append(word)
            return names[word]
        return word

    return TOKEN.sub(fix, line), hits


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--scan", action="store_true")
    args = parser.parse_args()
    rows = load_table()
    if args.scan:
        known = {old for old, _, _ in rows}
        rx = lint_words.name_regex(lint_words.UNIT_NAME)
        found: Counter[str] = Counter()
        for rel in files():
            for line in (ROOT / rel).read_text(encoding="utf-8").splitlines():
                for m in rx.finditer(line):
                    allowed = any(
                        r == "unit suffix" and fnmatch.fnmatch(rel, g) and re.search(lr, line) for g, r, lr, _ in lint_words.ALLOW
                    )
                    if m.group(0) not in known and not allowed:
                        found[m.group(0)] += 1
        for name, count in sorted(found.items()):
            print(f"{name}\t{count}")
        return 0
    total, changed = 0, 0
    for rel in files():
        names: dict[str, str] = {}
        for old, new, scope in rows:
            if scope == "*" or fnmatch.fnmatch(rel, scope):
                names.setdefault(old, new)
        path = ROOT / rel
        lines = path.read_text(encoding="utf-8").split("\n")
        file_hits = 0
        for i, line in enumerate(lines):
            new_line, hits = rewrite(line, names)
            if hits:
                file_hits += len(hits)
                if args.check:
                    print(f"{rel}:{i + 1}: " + ", ".join(f"{h} -> {names[h]}" for h in hits))
                lines[i] = new_line
        if file_hits:
            total, changed = total + file_hits, changed + 1
            if not args.check:
                path.write_text("\n".join(lines), encoding="utf-8")
    if not args.check:
        print(f"{total} renames in {changed} files")
    return 1 if args.check and total else 0


if __name__ == "__main__":
    sys.exit(main())
