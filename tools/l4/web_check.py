"""Checks the session log the browser station run left (tools/l4/web.sh): the browser
joined and rejoined with its token, its commands reached the server, and its snapshot
ages were logged (D199)."""

import json
import sys

lines = [json.loads(x) for x in open(sys.argv[1], encoding="utf-8") if x.strip()]
joins = [x for x in lines if x["kind"] == "join"]
ages_lines = [x for x in lines if x["kind"] == "snapshot_age"]
counters = next((x["counters"] for x in reversed(lines) if x["kind"] in ("counters", "summary")), {})
problems = []
if not any(j["client"] == "web" and not j["resumed"] for j in joins):
    problems.append("no first join by a web client")
if not any(j["client"] == "web" and j["resumed"] for j in joins):
    problems.append("no resumed join after the wake")
if counters.get("commands", 0) < 2:
    problems.append(f"commands {counters.get('commands', 0)} < 2")
# The browser's own lines (the two bots report too): windows of 10 s, summed.
web = [c for x in ages_lines for c in x["clients"] if c["client"] == "web"]
n = sum(c["n"] for c in web)
if n < 30:
    problems.append(f"too few snapshot ages from the browser: {n}")
else:
    p50 = sorted(c["age_p50_ms"] for c in web)[len(web) // 2]
    p99 = max(c["age_p99_ms"] for c in web)
    gap = max(c["gap_p99_ms"] for c in web)
    print(f"web_check: browser snapshot age p50 {p50} ms, worst-window p99 {p99} ms, gap p99 {gap} ms"
          f" over {n} snapshots (software rendering on 2 shared cores: not a Wi-Fi figure)")
    if p99 > 5000:
        problems.append(f"snapshot age p99 {p99} ms")
for p in problems:
    print(f"web_check: FAIL {p}")
if not problems:
    print(f"web_check: ok ({len(joins)} joins)")
sys.exit(1 if problems else 0)
