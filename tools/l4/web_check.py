"""Checks the session log the browser station run left (tools/l4/web.sh): the browser
joined and rejoined with its token, its commands reached the server, and its snapshot
ages were logged (D199)."""

import json
import sys

lines = [json.loads(x) for x in open(sys.argv[1], encoding="utf-8") if x.strip()]
joins = [x for x in lines if x["kind"] == "join"]
summary = next((x for x in reversed(lines) if x["kind"] == "summary"), None)
problems = []
if not any(j["client"] == "web" and not j["resumed"] for j in joins):
    problems.append("no first join by a web client")
if not any(j["client"] == "web" and j["resumed"] for j in joins):
    problems.append("no resumed join after the wake")
if summary is None:
    problems.append("no summary line (the server did not quit cleanly)")
else:
    if summary["counters"].get("commands", 0) < 2:
        problems.append(f"commands {summary['counters'].get('commands', 0)} < 2")
    ages = summary["snapshot_age"]["pooled"]
    if ages["n"] < 30 or ages["age_p99_ms"] < 0:
        problems.append(f"too few snapshot ages from the browser: {ages}")
    elif ages["age_p99_ms"] > 2000:
        problems.append(f"snapshot age p99 {ages['age_p99_ms']} ms")
    else:
        print(f"web_check: snapshot age p50 {ages['age_p50_ms']} ms, p99 {ages['age_p99_ms']} ms,"
              f" gap p99 {ages['gap_p99_ms']} ms over {ages['n']} snapshots")
for p in problems:
    print(f"web_check: FAIL {p}")
if not problems:
    print(f"web_check: ok ({len(joins)} joins)")
sys.exit(1 if problems else 0)
