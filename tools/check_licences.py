"""Check every file under assets/ and addons/ against content/provenance.json.

Fails on a file no manifest entry covers (entries match by path prefix, so
"addons/gdUnit4/" covers the whole addon), on an entry missing name, source,
licence or attribution (FT-LIC-005), and on art or sound that isn't CC0
(FT-LIC-006).
"""

import json
import sys
from pathlib import Path

REQUIRED = ("name", "source", "licence", "attribution")
CC0_KINDS = ("art", "sound")
OWN = {"addons/VERSIONS.md"}  # our own pin record, not third-party


def run(root: Path) -> list[str]:
    entries = json.loads((root / "content/provenance.json").read_text())["entries"]
    errors = []
    for e in entries:
        missing = [k for k in REQUIRED if not e.get(k)]
        if missing:
            errors.append(f"{e.get('name', e)}: missing {', '.join(missing)}")
        if e.get("kind") in CC0_KINDS and e.get("licence") != "CC0-1.0":
            errors.append(f"{e.get('name')}: {e['kind']} must be CC0-1.0, not {e.get('licence')}")
    prefixes = [e["path"] for e in entries if e.get("path")]
    for base in ("assets", "addons"):
        for f in sorted((root / base).rglob("*")):
            rel = f.relative_to(root).as_posix()
            if f.is_file() and rel not in OWN and not any(rel.startswith(p) for p in prefixes):
                errors.append(f"{rel}: not listed in content/provenance.json")
    return errors


def main() -> int:
    errors = run(Path(__file__).resolve().parent.parent)
    for e in errors:
        print(f"licences: {e}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
