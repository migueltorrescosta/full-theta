#!/usr/bin/env bash
# Load gate (#11; FT-GEN-003, FT-NET-014, FT-NET-040, FT-TST-011, FT-TST-014; D160-D162):
# the dedicated server with 6 crewable ships (--load-ships, dev and test only) pinned to
# 2 cores, 64 connections from 8 client processes of 8 NetClients on other physical
# cores (36 crew, 6 Captains, 22 viewers: LoadSeats), then a 65th connection that must
# be refused with session_full. The server's LoadProbe measures a window once every seat
# holds its pick and a ship started; tools/l4/load_check.py checks the budgets and
# writes summary.md.
#   tools/l4/load.sh [--out DIR] [--world N] [--warmup S] [--window S] [--report-only]
# --world is the total ship count [12: 6 crew + 6 raiders; 100 is the stress run];
# --report-only prints the numbers without failing on the budgets (the stress run).
# Env: L4_CPUS [0,1] (server), L4_LOAD_CLIENT_CPUS [4,5,12,13], L4_LOAD_PROCS [8].
# Host load average, CPU clocks of the server's cores and loopback counters are
# sampled every second into host.tsv (they matter: docs/spikes/S9.md); sim_profile.txt
# holds the sim's cost alone on the same cores just before the run.
# The import (godot --import) is gate.sh's job; run it first when calling this alone.
set -uo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1
cpus=${L4_CPUS:-0,1}
ccpus=${L4_LOAD_CLIENT_CPUS:-4,5,12,13}
procs=${L4_LOAD_PROCS:-8}
out=build/l4load/$(date +%Y%m%d-%H%M%S)
world=12
warmup=3
window=60
check_args=()
while (($#)); do
  case $1 in
    --out) out=$2; shift 2 ;;
    --world) world=$2; shift 2 ;;
    --warmup) warmup=$2; shift 2 ;;
    --window) window=$2; shift 2 ;;
    --report-only) check_args+=(--report-only); shift ;;
    *) echo "l4load: unknown argument $1" >&2; exit 2 ;;
  esac
done
per=$((64 / procs))
((per * procs == 64)) || { echo "l4load: L4_LOAD_PROCS must divide 64" >&2; exit 2; }
godot=$(tools/get-godot.sh) || exit 1
out=$(mkdir -p "$out" && cd "$out" && pwd)
# Joining 64 clients on a loaded host takes a while; then warmup and window.
limit=$((120 + ${warmup%.*} + ${window%.*}))
pids=()

cpu_list() { # expands 0,1 or 4-7 into "0 1" / "4 5 6 7"
  local part
  for part in ${1//,/ }; do
    if [[ $part == *-* ]]; then seq "${part%-*}" "${part#*-}"; else echo "$part"; fi
  done | tr '\n' ' '
}
read -ra server_cpus <<<"$(cpu_list "$cpus")"

lo_counters() { awk '$1 == "lo:" { print $2, $3 }' /proc/net/dev; }

sample_host() {
  local c f
  while true; do
    f=""
    for c in "${server_cpus[@]}"; do
      f+=" $(cat "/sys/devices/system/cpu/cpu$c/cpufreq/scaling_cur_freq" 2>/dev/null || echo 0)"
    done
    echo "${EPOCHREALTIME/./} $(cut -d' ' -f1 /proc/loadavg)$f $(lo_counters)" >>"$out/host.tsv"
    sleep 1
  done
}

cleanup() {
  local pid
  for pid in "${pids[@]}"; do kill -9 "$pid" 2>/dev/null; done
  [[ -n ${server_pid:-} ]] && kill -9 "$server_pid" 2>/dev/null
  [[ -n ${sampler_pid:-} ]] && kill "$sampler_pid" 2>/dev/null
  wait 2>/dev/null
  # Godot processes still naming the run folder are leftovers (not this script).
  left=$(pgrep -f -- "godot.*$out/" | grep -vx "$$" | tr '\n' ' ')
  if [[ -n $left ]]; then
    # shellcheck disable=SC2086  # a list of pids
    kill -9 $left 2>/dev/null
    echo "l4load: killed leftover processes $left" >&2
  fi
}
trap cleanup EXIT

die() { echo "l4load: $*" | tee "$out/why" >&2; exit 1; }

{
  echo "commit $(git rev-parse --short HEAD)$([[ -z $(git status --porcelain) ]] || echo ' (dirty)')"
  echo "date $(date -Is)"
  echo "server_cpus $cpus"
  echo "client_cpus $ccpus"
  echo "procs $procs x $per"
  echo "world $world"
  echo "loadavg $(cut -d' ' -f1-3 /proc/loadavg)"
  echo "governor $(cat /sys/devices/system/cpu/cpu"${server_cpus[0]}"/cpufreq/scaling_governor 2>/dev/null)"
  echo "epp $(cat /sys/devices/system/cpu/cpu"${server_cpus[0]}"/cpufreq/energy_performance_preference 2>/dev/null)"
  echo "no_turbo $(cat /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null)"
  echo "netns $(ip netns identify $$ 2>/dev/null)"
} >"$out/host.txt"
echo "l4load: out $out, world $world, server cpus $cpus, clients $procs x $per on $ccpus, load $(cut -d' ' -f1-3 /proc/loadavg)"
sample_host &
sampler_pid=$!

# The sim alone on the same cores and world, for comparison with its cost in the server
# (fewer ticks for the stress world, which takes about 0.2 s a tick).
pticks=$((world > 20 ? 120 : 1200))
{
  echo "\$ taskset -c $cpus godot -s res://tools/l4/sim_profile.gd -- --world $world --ticks $pticks --every $pticks ($(date -Is))"
  timeout 300 taskset -c "$cpus" "$godot" --headless --path . -s res://tools/l4/sim_profile.gd -- \
    --world "$world" --ticks "$pticks" --every "$pticks" 2>&1 | grep -v '^Godot Engine\|^$'
} >"$out/sim_profile.txt"

taskset -c "$cpus" "$godot" --headless --path . -- --server --bind 127.0.0.1 --port 0 \
  --no-beacon --grace-s 10 --load-ships 6 --load-world "$world" \
  --probe-out "$out/probe.json" --probe-warmup "$warmup" --probe-window "$window" \
  --run-for "$limit" >"$out/server.out" 2>&1 &
server_pid=$!
end=$((SECONDS + 60))
until line=$(grep -m1 -o 'listening on [0-9.]*:[0-9]*' "$out/server.out"); do
  kill -0 "$server_pid" 2>/dev/null || die "server exited at start: $(tail -n 3 "$out/server.out")"
  ((SECONDS < end)) || die "server not listening after 60 s"
  sleep 0.2
done
url=ws://${line#listening on }

for ((p = 0; p < procs; p++)); do
  taskset -c "$ccpus" "$godot" --headless --path . -s res://tools/l4/load_client.gd -- \
    --url "$url" --first $((p * per)) --count "$per" --log "$out/p$p.json" --max-s "$limit" \
    >>"$out/clients.out" 2>&1 &
  pids+=($!)
done

end=$((SECONDS + limit))
until grep -q '^probe: [0-9]* picks' "$out/server.out"; do
  kill -0 "$server_pid" 2>/dev/null || die "server exited before every seat picked"
  ((SECONDS < end)) || die "not every seat picked and every ship started within $limit s"
  sleep 0.5
done
# Connection 65 (FT-NET-014): all 64 are in.
taskset -c "$ccpus" "$godot" --headless --path . -s res://tools/l4/load_client.gd -- \
  --url "$url" --full-probe --log "$out/p65.json" >>"$out/clients.out" 2>&1 &
pids+=($!)

while kill -0 "$server_pid" 2>/dev/null; do
  ((SECONDS < end)) || die "server still running after $limit s"
  sleep 0.5
done
wait "$server_pid" || die "server exited $?: $(tail -n 3 "$out/server.out")"
server_pid=""
failed=0
for pid in "${pids[@]}"; do
  wait "$pid" || failed=1
done
pids=()
kill "$sampler_pid" 2>/dev/null
sampler_pid=""
((failed == 0)) || echo "l4load: a client process failed (clients.out, p*.json)" >&2
uv run --quiet --project tools python tools/l4/load_check.py "$out" "${check_args[@]}" \
  | tee "$out/summary.md"
rc=${PIPESTATUS[0]}
((rc == 0 && failed == 0))
