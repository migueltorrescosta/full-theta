#!/usr/bin/env bash
# L4 (T048, FT-TST-011, FT-TST-014): a server and 3 headless clients as separate
# processes, all pinned to 2 cores like the CI runner, driven by intent files.
#   tools/l4/run.sh [--out DIR] [SCENARIO...]     (default: every scenario, in order)
# Scenarios are tools/l4/scenarios/<name>.sh with their intent files in
# tools/l4/scenarios/<name>/. Logs go to build/l4/<run>/<scenario>/ (DIR replaces
# build/l4/<run>). Prints one line per scenario and exits non-zero if any failed or
# left a process behind. Env: L4_CPUS [0,1], L4_GRACE [8] (server --grace-s),
# L4_SCENARIO_S [90] (a scenario's time limit).
# The import (godot --import) is gate.sh's job; run it first when calling this alone.
set -uo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1
here=tools/l4
cpus=${L4_CPUS:-0,1}
grace=${L4_GRACE:-8}
limit=${L4_SCENARIO_S:-90}
run_dir=build/l4/$(date +%Y%m%d-%H%M%S)
names=()
while (($#)); do
  case $1 in
    --out) run_dir=$2; shift 2 ;;
    -*) echo "l4: unknown flag $1" >&2; exit 2 ;;
    *) names+=("$1"); shift ;;
  esac
done
if ((${#names[@]} == 0)); then
  for f in "$here"/scenarios/*.sh; do names+=("$(basename "$f" .sh)"); done
fi
godot=$(tools/get-godot.sh) || exit 1
run_dir=$(mkdir -p "$run_dir" && cd "$run_dir" && pwd)

# --- Helpers for scenario scripts (each scenario runs in its own subshell). ---

die() { echo "$*" >"$out/why"; exit 1; }

alive() { # pid: running and not a zombie
  local st
  st=$(sed 's/^.*) //' "/proc/$1/stat" 2>/dev/null | cut -d' ' -f1) || return 1
  [[ -n $st && $st != Z ]]
}

# why LOG: the reason a client gave on its last log line.
why() { tail -n 1 "$1" 2>/dev/null | grep -o '"why":"[^"]*"' | cut -c8- | tr -d '"'; }

# Fails the scenario as soon as a client exits non-zero or the server dies.
check() {
  local name rc
  for name in "${!pids[@]}"; do
    alive "${pids[$name]}" && continue
    wait "${pids[$name]}"; rc=$?
    unset "pids[$name]"
    ((rc == 0)) || die "$name exited $rc: $(why "$out/$name.${launches[$name]}.jsonl")"
  done
  if [[ -n ${server_pid:-} ]] && ! alive "$server_pid"; then die "server died"; fi
}

# server [flags]: the dedicated server on a free port; sets URL.
server() {
  taskset -c "$cpus" "$godot" --headless --path . -- --server --bind 127.0.0.1 --port 0 \
    --grace-s "$grace" --run-for $((limit + 30)) "$@" >"$out/server.out" 2>&1 &
  server_pid=$!
  local end=$((SECONDS + 30)) line
  until line=$(grep -m1 -o 'listening on [0-9.]*:[0-9]*' "$out/server.out"); do
    alive "$server_pid" || die "server exited at start: $(tail -n 3 "$out/server.out")"
    ((SECONDS < end)) || die "server not listening after 30 s"
    sleep 0.1
  done
  URL=ws://${line#listening on }
}

# client NAME INTENT [--url U] [--set K=V ...]: launches NAME (again) with its token file.
client() {
  local name=$1 intent=$2
  shift 2
  launches[$name]=$((${launches[$name]:-0} + 1))
  taskset -c "$cpus" "$godot" --headless --path . -s res://tools/l4/l4_client.gd -- \
    --url "${URL:-}" --name "$name" --intent "$sdir/$intent" --run-dir "$out" \
    --log "$out/$name.${launches[$name]}.jsonl" --token-file "$out/$name.tok" \
    --max-s "$limit" --set "GRACE=$grace" --set "PORT=${PORT:-0}" "$@" \
    >>"$out/clients.out" 2>>"$out/clients.err" &
  pids[$name]=$!
  echo "$EPOCHREALTIME launch $name ${launches[$name]} pid $!" >>"$out/events.txt"
}

# await NAME [S]: waits for sig.NAME, failing fast if a client fails.
await() {
  local end=$((SECONDS + ${2:-60}))
  until [[ -e $out/sig.$1 ]]; do
    check
    ((SECONDS < end)) || die "no sig.$1 after ${2:-60} s"
    sleep 0.1
  done
}

signal() { echo harness >"$out/sig.$1"; }

# kill9 NAME: SIGKILL (a crash), then reap it.
kill9() {
  local pid=${pids[$1]}
  kill -9 "$pid"
  wait "$pid" 2>/dev/null
  unset "pids[$1]"
  echo "$EPOCHREALTIME SIGKILL $1 pid $pid" >>"$out/events.txt"
}

# finish: waits until every client exits (each must exit 0).
finish() {
  local end=$((SECONDS + limit))
  while ((${#pids[@]})); do
    check
    ((SECONDS < end)) || die "clients still running: ${!pids[*]}"
    sleep 0.1
  done
}

# Kills what the harness started; anything else still naming the scenario's folder
# (a client, a host's server child) is a leftover: kill it and fail.
cleanup() {
  local pid left
  for pid in "${pids[@]}"; do kill -9 "$pid" 2>/dev/null; done
  [[ -n ${server_pid:-} ]] && kill -9 "$server_pid" 2>/dev/null
  wait 2>/dev/null
  left=$(pgrep -f -- "$out/" | tr '\n' ' ')
  if [[ -n $left ]]; then
    pkill -9 -f -- "$out/"
    echo "leftover processes: $left" >>"$out/why"
    return 1
  fi
}

run_scenario() {
  (
    declare -A pids=() launches=()
    server_pid=""
    trap 'cleanup || exit 1' EXIT
    # shellcheck disable=SC1090
    source "$here/scenarios/$scenario.sh"
    finish
    uv run --quiet --project tools python tools/l4/check.py "$out" >"$out/check.txt" 2>&1 \
      || die "check.py: $(tail -n 3 "$out/check.txt" | tr '\n' ' ')"
  ) 2>>"$out/harness.err"  # bash's "Killed" job notices; the reason is in $out/why
}

load=$(cut -d' ' -f1-3 /proc/loadavg)
echo "l4: run $run_dir, cpus $cpus, grace $grace s, load $load"
failed=0
: >"$run_dir/summary.tsv"
for scenario in "${names[@]}"; do
  [[ -f $here/scenarios/$scenario.sh ]] || { echo "l4: no scenario $scenario" >&2; exit 2; }
  out=$run_dir/$scenario
  sdir=$root/$here/scenarios/$scenario
  mkdir -p "$out"
  start=$EPOCHREALTIME
  if run_scenario; then r=pass; else r=FAIL; failed=1; fi
  secs=$(awk "BEGIN { printf \"%.1f\", $EPOCHREALTIME - $start }")
  why=$( [[ -f $out/why ]] && tr '\n' ' ' <"$out/why")
  printf '%s\t%s\t%s\t%s\n' "$scenario" "$r" "$secs" "$why" >>"$run_dir/summary.tsv"
  echo "l4: $scenario $r ${secs} s${why:+ ($why)}"
done
exit "$failed"
