"""Split the L1 test files into shards of about equal run time (#27).

  l1_shards.py K N             print shard K (0-based) of N: one res:// path per line
  l1_shards.py --update XML... rewrite tools/l1_times.json from gdUnit4 JUnit reports

Every .gd file under tests/ goes to exactly one shard, so a new test file is picked up
without a list to edit (gdUnit4 skips files that are not suites). The split is the
longest-first greedy one over the seconds per file in tools/l1_times.json; a test_*.gd
file missing there counts as the median time, any other file as 0 s. Stale times only
unbalance the shards; refresh them with --update after a full L1 run.
"""

import json
import statistics
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TIMES = ROOT / "tools/l1_times.json"


def test_files() -> list[str]:
    """Every .gd file under tests/, as a sorted list of res:// paths."""
    return sorted(f"res://{p.relative_to(ROOT).as_posix()}" for p in (ROOT / "tests").rglob("*.gd"))


def shards(files: list[str], times: dict[str, float], n: int) -> list[list[str]]:
    """Longest-first greedy split of files into n lists of about equal total time."""
    default = statistics.median(times.values()) if times else 1.0

    def weight(f: str) -> float:
        return times.get(f, default if f.rsplit("/", 1)[-1].startswith("test_") else 0.0)

    loads, out = [0.0] * n, [[] for _ in range(n)]
    for f in sorted(files, key=lambda f: (-weight(f), f)):
        k = loads.index(min(loads))
        loads[k] += weight(f)
        out[k].append(f)
    return [sorted(s) for s in out]


def times_from_junit(paths: list[Path]) -> dict[str, float]:
    """Seconds per suite file from gdUnit4 JUnit XML (package + suite name)."""
    times = {}
    for path in paths:
        for suite in ET.parse(path).getroot().iter("testsuite"):
            f = f"res://{suite.get('package')}/{suite.get('name')}.gd"
            times[f] = round(times.get(f, 0.0) + float(suite.get("time", 0)), 1)
    return times


def main(args: list[str]) -> int:
    if args and args[0] == "--update":
        times = times_from_junit([Path(a) for a in args[1:]])
        TIMES.write_text(json.dumps(dict(sorted(times.items())), indent=1) + "\n")
        print(f"l1_shards: wrote {len(times)} suite times to {TIMES.relative_to(ROOT)}")
        return 0
    if len(args) != 2 or not (0 <= int(args[0]) < int(args[1])):
        print(__doc__, file=sys.stderr)
        return 2
    times = json.loads(TIMES.read_text()) if TIMES.exists() else {}
    print("\n".join(shards(test_files(), times, int(args[1]))[int(args[0])]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
