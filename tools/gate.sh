#!/usr/bin/env bash
# Local gate (FT-TST-002, FT-TST-005): imports the project, then runs tiers.
#   tools/gate.sh [l0|l1|l2|l3|l4|l4load|l5|l6|ci|all]... [--update-baselines]   (default: ci)
# ci = the tiers CI runs (l0 l1; l1 runs every test, tests/net included); all = every
# implemented tier (l0 l1 l4 l4load l5 l6). l3 runs only the in-process network tests
# (tests/net), pinned to 2 cores like a CI runner. l4 runs a server and 3 client processes
# on 2 cores (tools/l4/run.sh). l4load is the 64-connection load gate, fugaku only: the
# server on 2 cores, 64 clients on other cores (tools/l4/load.sh, about 2-3 minutes). l6
# builds the release packages and runs them (tools/l6/run.sh).
# --update-baselines makes l5 regenerate tests/visual/baselines/ instead of diffing.
# Prints the commit and per-tier results as a block for the PR body.
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root" || exit 1

tiers=()
l5_args=()
for arg in "$@"; do
  case $arg in
    l0 | l1 | l3 | l4 | l4load | l5 | l6) tiers+=("$arg") ;;
    ci) tiers+=(l0 l1) ;;
    all) tiers+=(l0 l1 l4 l4load l5 l6) ;;
    --update-baselines) l5_args+=(--update-baselines) ;;
    l2) echo "gate: tier $arg is not implemented yet" >&2; exit 2 ;;
    *) echo "gate: unknown tier $arg (use l0..l6, ci or all)" >&2; exit 2 ;;
  esac
done
(( ${#tiers[@]} )) || tiers=(l0 l1)
if (( ${#l5_args[@]} )) && [[ " ${tiers[*]} " != *" l5 "* ]]; then
  echo "gate: --update-baselines needs the l5 tier" >&2; exit 2
fi

godot=$(tools/get-godot.sh) || exit 1

l0() { tools/l0.sh; }

# gdUnit4 over a test directory ($1), JUnit XML in build/reports/report_1/results.xml;
# the rest of the arguments prefix the command (a CPU pin). --remote-debug to a closed
# port keeps a script error from opening the interactive debugger (as in
# addons/gdUnit4/runtest.sh).
gdunit() {
  local dir=$1
  shift
  rm -rf build/reports
  "$@" "$godot" --headless --path . -s -d --remote-debug tcp://127.0.0.1:0 \
    res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
    --add "$dir" --report-directory build/reports --ignoreHeadlessMode
}

# L1: every test.
l1() { gdunit res://tests; }

# L3: server and clients over loopback WebSocket in one process (tests/net), on 2 cores.
l3() { gdunit res://tests/net taskset -c 0,1; }

# L4: a server and 3 headless client processes on 2 cores, driven by intent files;
# logs in build/l4/<run>/ (tools/l4/run.sh); then the browser station on the same 2 cores
# (tools/l4/web.sh, headless Chromium, logs in build/l4web/).
l4() { tools/l4/run.sh && tools/l4/web.sh; }

# L4 load gate (#11): 6 ships, 64 connections, connection 65 refused; budgets checked by
# tools/l4/load_check.py; logs and summary.md in build/l4load/<run>/.
l4load() { tools/l4/load.sh; }

# L5: screenshots under Xvfb with llvmpipe, diffed against tests/visual/baselines/
# (tools/l5.py; fugaku only, needs xvfb).
l5() { uv run --quiet --project tools python tools/l5.py "${l5_args[@]}"; }

# L6: build, inspect and run the release packages: each exported Linux and Windows
# build synthesises a line with its bundled Piper and serves its bundled web export
# to headless Chromium (tools/l6/run.sh; fugaku only, needs wine and node).
l6() { tools/l6/run.sh; }

echo "gate: import"
"$godot" --headless --path . --import >/dev/null 2>&1 || { echo "gate: import failed" >&2; exit 1; }

results=()
failed=0
for t in "${tiers[@]}"; do
  echo "gate: $t"
  start=$SECONDS
  if "$t"; then r=pass; else r=FAIL; failed=1; fi
  results+=("$t $r $((SECONDS - start)) s")
done

commit=$(git rev-parse HEAD)
[[ -z $(git status --porcelain) ]] || commit="$commit (dirty)"
echo
echo "gate results, commit $commit:"
printf -- '- %s\n' "${results[@]}"
exit "$failed"
