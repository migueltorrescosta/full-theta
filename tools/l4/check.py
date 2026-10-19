"""Checks one L4 scenario's client logs (T048): run by tools/l4/run.sh after the clients.

    python tools/l4/check.py OUT_DIR

Each client launch writes OUT_DIR/<name>.<launch>.jsonl (tools/l4/l4_client.gd). Fails if
a final launch did not end with every step passed, if a launch that was not the last of
its name ended on its own (only a SIGKILL may cut one short), if any client applied a
bad snapshot, or if two clients disagree on their ship's KIN at the same tick
(convergence after a rejoin, FT-NET-027). Prints one line per launch, with the time from
the SIGKILL to the relaunched client's Welcome (run.sh's events.txt).
"""

from __future__ import annotations

import json
import re
import sys
from collections import defaultdict
from pathlib import Path

LOG = re.compile(r"^(?P<name>.+)\.(?P<launch>\d+)\.jsonl$")


def read(path: Path) -> list[dict]:
    lines = []
    for raw in path.read_text().splitlines():
        try:
            lines.append(json.loads(raw))
        except json.JSONDecodeError:
            pass  # a SIGKILL may cut the last line
    return lines


def check(out: Path) -> list[str]:
    logs: dict[str, dict[int, list[dict]]] = defaultdict(dict)
    for p in sorted(out.glob("*.jsonl")):
        m = LOG.match(p.name)
        if m:
            logs[m["name"]][int(m["launch"])] = read(p)
    kills: dict[str, list[float]] = defaultdict(list)
    events = out / "events.txt"
    for row in events.read_text().splitlines() if events.exists() else []:
        f = row.split()
        if len(f) >= 3 and f[1] == "SIGKILL":
            kills[f[2]].append(float(f[0]))
    problems: list[str] = []
    kin: dict[int, dict[str, str]] = defaultdict(dict)  # tick -> client launch -> hash
    for name, launches in sorted(logs.items()):
        last = max(launches)
        for launch, lines in sorted(launches.items()):
            who = f"{name}.{launch}"
            end = next((x for x in lines if x.get("ev") == "end"), None)
            steps = sum(1 for x in lines if x.get("ev") == "step" and x.get("ok"))
            snaps = [x for x in lines if x.get("ev") == "snap"]
            for s in snaps:
                kin[s["tick"]][who] = s["k"]
            if end is None:
                state = "killed"
                if launch == last:
                    problems.append(f"{who}: no end line (killed or crashed)")
            else:
                st = end.get("stats", {})
                state = "ok" if end.get("ok") else f"FAIL {end.get('why')}"
                if not end.get("ok"):
                    problems.append(f"{who}: {end.get('why')}")
                elif launch != last:
                    problems.append(f"{who}: ended by itself but was relaunched")
                if st.get("bad_snapshots", 0) or end.get("view_rejected", 0):
                    problems.append(f"{who}: bad snapshots {st}")
            gap = max((s.get("gap_ms", 0) for s in snaps[1:]), default=0)
            rejoin = ""
            start = next((x for x in lines if x.get("ev") == "start"), {})
            welcome = next((x for x in lines if x.get("ev") == "welcome"), None)
            if launch > 1 and len(kills[name]) >= launch - 1 and welcome and "unix_ms" in start:
                at = start["unix_ms"] / 1000 + (welcome["ms"] - start["ms"]) / 1000
                rejoin = f", Welcome {at - kills[name][launch - 2]:.1f} s after the SIGKILL"
            print(
                f"{who}: {state}, {steps} steps, {len(snaps)} snapshot frames, "
                f"max gap {gap} ms{rejoin}"
            )
    common = 0
    for tick, by in sorted(kin.items()):
        if len(by) > 1:
            common += 1
            if len(set(by.values())) > 1:
                problems.append(f"KIN differs at tick {tick}: {by}")
                break
    print(f"convergence: {common} ticks seen by more than one client")
    return problems


def main() -> int:
    problems = check(Path(sys.argv[1]))
    for p in problems:
        print(p, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
