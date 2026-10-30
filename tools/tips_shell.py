"""Copies the tips into the web shell's loading screen, or checks the copy (#28, P28-Tips).

content/tips/tips.json is the source: the game reads it (presentation/tips_view.gd), and
the web page shows the same tips before the engine has loaded, so app/web/shell.html
holds a copy on one line between BEGIN and END. Run after editing the tips:

  python3 tools/tips_shell.py           rewrite the line in shell.html
  python3 tools/tips_shell.py --check   exit 1 when shell.html is out of date

check() also validates tips.json (tools/tests/test_tips.py runs both in l0).
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TIPS = ROOT / "content/tips/tips.json"
SHELL = ROOT / "app/web/shell.html"
BEGIN = "/* tips:begin (tools/tips_shell.py writes the next line from content/tips/tips.json) */"
END = "/* tips:end */"
LANGUAGES = ("en", "pt_PT", "it")
STATIONS = ("helm", "weapons", "engineering", "science", "relay", "comms")
MIN_TIPS = 100
MIN_PER_STATION = 5
# The longest tip in characters: three lines of 20 px text in the 600 px column, four on
# a phone upright.
MAX_CHARS = 120


def load(path: Path = TIPS) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def errors_in(data: dict) -> list[str]:
    """What is wrong with a tips table: missing languages, unknown topics, long tips."""
    errors = []
    topics = data.get("topics", {})
    for key, names in topics.items():
        for lang in LANGUAGES:
            if not str(names.get(lang, "")).strip():
                errors.append(f"topic {key}: no {lang} name")
    tips = data.get("tips", [])
    ids = set()
    per_topic: dict[str, int] = {}
    for tip in tips:
        tid = tip.get("id", "?")
        if tid in ids:
            errors.append(f"{tid}: duplicate id")
        ids.add(tid)
        topic = tip.get("topic")
        if topic not in topics:
            errors.append(f"{tid}: unknown topic {topic}")
        per_topic[topic] = per_topic.get(topic, 0) + 1
        for lang in LANGUAGES:
            text = str(tip.get(lang, "")).strip()
            if not text:
                errors.append(f"{tid}: no {lang} text")
            elif len(text) > MAX_CHARS:
                errors.append(f"{tid}: {lang} text is {len(text)} characters (max {MAX_CHARS})")
    if len(tips) < MIN_TIPS:
        errors.append(f"{len(tips)} tips (at least {MIN_TIPS})")
    for station in STATIONS:
        if per_topic.get(station, 0) < MIN_PER_STATION:
            errors.append(f"{station}: {per_topic.get(station, 0)} tips (at least {MIN_PER_STATION})")
    return errors


def shell_line(data: dict) -> str:
    """The shell's copy: topic names and tips without ids, in each language."""
    copy = {
        "topics": data["topics"],
        "tips": [{k: v for k, v in t.items() if k != "id"} for t in data["tips"]],
    }
    return "const FT_TIPS = " + json.dumps(copy, ensure_ascii=False, separators=(",", ":")) + ";"


def rewrite(html: str, line: str) -> str:
    start = html.index(BEGIN) + len(BEGIN)
    end = html.index(END, start)
    return html[:start] + "\n" + line + "\n" + html[end:]


def check() -> list[str]:
    data = load()
    errors = errors_in(data)
    html = SHELL.read_text(encoding="utf-8")
    if BEGIN not in html or END not in html:
        errors.append("shell.html: no tips block")
    elif rewrite(html, shell_line(data)) != html:
        errors.append("shell.html: tips out of date (run python3 tools/tips_shell.py)")
    return errors


def main(argv: list[str]) -> int:
    if "--check" in argv:
        errors = check()
        for e in errors:
            print("tips:", e, file=sys.stderr)
        return 1 if errors else 0
    data = load()
    SHELL.write_text(rewrite(SHELL.read_text(encoding="utf-8"), shell_line(data)), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
