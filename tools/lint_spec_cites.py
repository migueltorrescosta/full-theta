"""Spec lines cite the decisions that change them (D-number citation lint).

For every decision in docs/decisions.md that names an FT id as amended, refined, superseded,
replaced or extended ("amends FT-...", "refines FT-...") or lists an FT id in its first
parenthesis, the id's active spec line in docs/spec/NN-*.md must cite that decision's D-number.
A reader of the spec line then finds the decision that last changed it.

Usage: lint_spec_cites.py
"""

import re
import sys
from pathlib import Path

ID = r"FT-[A-Z0-9]+-\d+"
DECISION = re.compile(r"^- (D\d+) (.*)$", re.M)
VERB = re.compile(rf"\b(?:amends?|refines?|supersedes?|replaces?|extends?)\b((?:[ ,;]|and|FT-[A-Z0-9]+-\d+|D\d+'s)*)")
SPEC_LINE = re.compile(rf"^- \*\*({ID})\*\*(.*)$", re.M)


def first_parenthesis(text: str) -> str:
    start = text.find("(")
    if start < 0:
        return ""
    depth = 0
    for i in range(start, len(text)):
        depth += {"(": 1, ")": -1}.get(text[i], 0)
        if depth == 0:
            return text[start : i + 1]
    return text[start:]


def named_ids(text: str) -> set[str]:
    ids = set(re.findall(ID, first_parenthesis(text)))
    for m in VERB.finditer(text):
        ids |= set(re.findall(ID, m.group(1)))
    return ids


def spec_lines(root: Path) -> dict[str, str]:
    lines: dict[str, str] = {}
    for f in sorted((root / "docs/spec").glob("[0-9]*.md")):
        for i, rest in SPEC_LINE.findall(f.read_text()):
            lines[i] = rest
    return lines


def run(root: Path) -> list[str]:
    decisions = root / "docs/decisions.md"
    spec = spec_lines(root)
    errors: list[str] = []
    for d, text in DECISION.findall(decisions.read_text()):
        for i in sorted(named_ids(text)):
            if i in spec and not re.search(rf"\b{d}\b", spec[i]):
                errors.append(f"{i}: its spec line does not cite {d}, which names it")
    return errors


def main() -> int:
    errors = run(Path(__file__).resolve().parent.parent)
    for e in errors:
        print(f"lint_spec_cites: {e}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
