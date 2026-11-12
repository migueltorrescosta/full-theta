"""Check that every touch rail label fits a rail button (C3, FT-STN-005).

A rail button's label is a verb and its object ("Repair part"), at most MAX_CHARS
characters in every language of content/i18n/strings.json, so it fits a half-width
rail button on a phone. The rail labels are the keys under RAIL_PREFIXES; their help
lines (a `.help.` part in the key) are sentences, not labels. A placeholder counts as one
character (%d as "9", %s as "A": a mount number, a crew letter).

Usage: check_rail_labels.py [strings.json]; exits 1 with one line per label too long.
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STRINGS = ROOT / "content/i18n/strings.json"
MAX_CHARS = 14
RAIL_PREFIXES = ("eng.touch.", "touch.helm.", "weapons.touch_", "touch.weapons.")


def is_rail_key(key: str) -> bool:
    return key.startswith(RAIL_PREFIXES) and ".help." not in key


def shown(text: str) -> str:
    return text.replace("%d", "9").replace("%s", "A")


def check(strings: dict) -> list[str]:
    errors = []
    for key, langs in strings.items():
        if not is_rail_key(key):
            continue
        for lang, text in langs.items():
            n = len(shown(text))
            if n > MAX_CHARS:
                errors.append(f"{key} [{lang}]: {text!r} is {n} characters (max {MAX_CHARS})")
    return errors


def main(argv: list[str]) -> int:
    path = Path(argv[1]) if len(argv) > 1 else STRINGS
    errors = check(json.loads(path.read_text(encoding="utf-8"))["strings"])
    for e in errors:
        print(e)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
