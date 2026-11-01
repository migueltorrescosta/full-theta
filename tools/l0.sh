#!/usr/bin/env bash
# L0 static checks (FT-TST-001): formatting and lint, architecture lint,
# definitions, traceability, dialogue and translations, licences, and the tools' own fixture tests.
# The checks run in parallel (L0_JOBS processes, default the CPUs this shell may use); each
# one's output goes to build/l0/<check>.log and is printed when it fails.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
godot=$(tools/get-godot.sh)
run() { uv run --quiet --project tools "$@"; }
jobs=${L0_JOBS:-$(nproc)}
logs=build/l0
rm -rf "$logs"
mkdir -p "$logs"

# Our GDScript: everything tracked except vendored addons and lint fixtures.
mapfile -t scripts < <(git ls-files --cached --others --exclude-standard '*.gd' \
  | grep -vE '^(addons/|tools/tests/fixtures/)')
printf 'res://%s\n' "${scripts[@]}" >"$logs/scripts.txt"
bin=$(run python -c 'import os, sys; print(os.path.dirname(sys.executable))')

# gdtoolkit over the scripts in $jobs chunks at once.
chunked() { printf '%s\0' "${scripts[@]}" | xargs -0 -P "$jobs" -n $(((${#scripts[@]} + jobs - 1) / jobs)) "$@"; }

checks=(tool-tests gdlint gdformat check-only definitions scenarios architecture traceability dialogue
  palette licences)
check() {
  case $1 in
    gdlint) chunked "$bin/gdlint" ;;
    gdformat) chunked "$bin/gdformat" --check ;;
    # Every script compiles: one Godot process loads them all (tools/check_scripts.gd).
    check-only) "$godot" --headless --path . -s res://tools/check_scripts.gd -- "$logs/scripts.txt" ;;
    definitions) "$godot" --headless --path . -s res://tools/check_defs.gd ;; # FT-DAT-002
    scenarios) "$godot" --headless --path . -s res://tools/check_scenarios.gd ;; # FT-DAT-008, FT-MIS-041
    architecture) run python tools/lint_arch.py ;;
    traceability) run python tools/traceability.py --check ;;
    dialogue) run python tools/check_dialogue.py ;; # FT-DAT-003, FT-DAT-004, FT-DAT-011
    palette) run python tools/check_palette.py ;; # FT-STN-006
    licences) run python tools/check_licences.py ;;
    tool-tests) run pytest -q -p no:cacheprovider tools/tests ;;
  esac
}

# Runs a check and records its seconds in $logs/<check>.time.
timed() {
  local start=$SECONDS rc=0
  check "$1" || rc=$?
  echo $((SECONDS - start)) >"$logs/$1.time"
  return "$rc"
}

# The slow checks start first; at most $jobs run at once.
pids=()
for c in "${checks[@]}"; do
  while (($(jobs -rp | wc -l) >= jobs)); do wait -n || true; done
  timed "$c" >"$logs/$c.log" 2>&1 &
  pids+=($!)
done
failed=0
for i in "${!checks[@]}"; do
  if wait "${pids[$i]}"; then
    echo "l0: ${checks[$i]} ok ($(<"$logs/${checks[$i]}.time") s)"
  else
    cat "$logs/${checks[$i]}.log" >&2
    echo "l0: ${checks[$i]} failed ($logs/${checks[$i]}.log)" >&2
    failed=1
  fi
done
exit "$failed"
