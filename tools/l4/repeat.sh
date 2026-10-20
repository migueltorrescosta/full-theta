#!/usr/bin/env bash
# Runs the L4 tier N times in a row (the issue asks for 10 passes on fugaku) and writes
# build/l4/repeat-summary.txt: per run the host load average at its start, result,
# duration and per-scenario timings, then the totals.
#   tools/l4/repeat.sh N [SCENARIO...]
set -uo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1
n=${1:?usage: tools/l4/repeat.sh N [SCENARIO...]}
shift
godot=$(tools/get-godot.sh) || exit 1
"$godot" --headless --path . --import >/dev/null 2>&1 || { echo "l4: import failed" >&2; exit 1; }
base=build/l4/repeat-$(date +%Y%m%d-%H%M%S)
summary=build/l4/repeat-summary.txt
mkdir -p "$base"
{
  echo "L4 repeat: $n runs, commit $(git rev-parse --short HEAD)$([[ -z $(git status --porcelain) ]] || echo ' (dirty)'), $(nproc) threads, cpus ${L4_CPUS:-0,1}, logs $base"
  echo "run  result  seconds  load(1/5/15)    scenarios (name result seconds)"
} >"$summary"
passed=0
for ((i = 1; i <= n; i++)); do
  load=$(cut -d' ' -f1-3 /proc/loadavg)
  start=$EPOCHREALTIME
  if tools/l4/run.sh --out "$base/$i" "$@"; then r=pass; passed=$((passed + 1)); else r=FAIL; fi
  secs=$(awk "BEGIN { printf \"%.1f\", $EPOCHREALTIME - $start }")
  scen=$(awk -F'\t' '{ printf "%s %s %s; ", $1, $2, $3 }' "$base/$i/summary.tsv" 2>/dev/null)
  printf '%-4s %-7s %-8s %-15s %s\n' "$i" "$r" "$secs" "$load" "$scen" >>"$summary"
done
echo "passed $passed of $n" >>"$summary"
cat "$summary"
((passed == n))
