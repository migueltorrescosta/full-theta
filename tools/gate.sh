#!/usr/bin/env bash
# Local gate (FT-TST-002, FT-TST-005): imports the project, then runs tiers.
#   tools/gate.sh [l0|l1|l2|l3|l4|l5|l6|ci|all]...   (default: ci)
# ci = the tiers CI runs (l0 l1); all = every implemented tier (l0 l1 l6).
# Prints the commit and per-tier results as a block for the PR body.
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root" || exit 1

tiers=()
for arg in "${@:-ci}"; do
  case $arg in
    l0 | l1 | l6) tiers+=("$arg") ;;
    ci) tiers+=(l0 l1) ;;
    all) tiers+=(l0 l1 l6) ;;
    l2 | l3 | l4 | l5) echo "gate: tier $arg is not implemented yet" >&2; exit 2 ;;
    *) echo "gate: unknown tier $arg (use l0..l6, ci or all)" >&2; exit 2 ;;
  esac
done

godot=$(tools/get-godot.sh) || exit 1

l0() { tools/l0.sh; }

# L1: gdUnit4 over tests/, JUnit XML in build/reports/report_1/results.xml.
l1() {
  rm -rf build/reports
  # --remote-debug to a closed port keeps a script error from opening the
  # interactive debugger (as in addons/gdUnit4/runtest.sh).
  "$godot" --headless --path . -s -d --remote-debug tcp://127.0.0.1:0 \
    res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
    --add res://tests --report-directory build/reports --ignoreHeadlessMode
}

# L6: export Linux and Windows (export_presets.cfg), smoke-run Linux headless.
l6() {
  tools/get-godot.sh --with-templates >/dev/null || return 1
  mkdir -p build/linux build/windows
  "$godot" --headless --path . --export-release Linux || return 1
  "$godot" --headless --path . --export-release Windows || return 1
  [[ -s build/windows/full-theta.exe ]] || { echo "l6: no Windows build" >&2; return 1; }
  timeout 5 build/linux/full-theta.x86_64 --headless -- --server
}

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
