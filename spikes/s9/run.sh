#!/usr/bin/env bash
# One S9 load run: the server (pinned to the 2 server cores) plus the simulated
# stations (several WebSocket connections per headless Godot process, pinned
# to the client cores, standing in for remote devices), then the summary.
#   spikes/s9/run.sh OUT_DIR [--run-for 60] [--port 47830] [--procs 8]
#       [--conns 8] [--decode 1] [--server-cpus 0,1] [--client-cpus 8,9]
#       [--extra CMD] [--extra-conns N] [-- extra server flags]
# --run-for is the measured window; it starts 3 s after every expected
# client has joined. --extra runs CMD (through bash -c) once the load is up,
# with S9_URL and S9_OUT set, for an extra client such as a rendering client
# (TECH-5, S7b); --extra-conns is how many connections it opens, so the server
# waits for them too. --decode N makes the first N stations of each process
# decode every snapshot (default 1).
# Run it inside the ft-s9 namespace (spikes/s9/netns.sh) to get wire bytes.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
out=$1
shift
run_for=60 port=47830 procs=8 conns=8 decode=1 server_cpus=0,1 client_cpus=8,9
extra_cmd="" extra_conns=0
server_extra=()
while (($#)); do
  case $1 in
    --run-for) run_for=$2; shift 2 ;;
    --port) port=$2; shift 2 ;;
    --procs) procs=$2; shift 2 ;;
    --conns) conns=$2; shift 2 ;;
    --decode) decode=$2; shift 2 ;;
    --server-cpus) server_cpus=$2; shift 2 ;;
    --client-cpus) client_cpus=$2; shift 2 ;;
    --extra) extra_cmd=$2; shift 2 ;;
    --extra-conns) extra_conns=$2; shift 2 ;;
    --) shift; server_extra=("$@"); break ;;
    *) echo "run.sh: unknown flag $1" >&2; exit 2 ;;
  esac
done
godot=$(tools/get-godot.sh)
mkdir -p "$out"
rm -f "$out"/*.log "$out"/*.out
expect=$((procs * conns + extra_conns))

taskset -c "$server_cpus" "$godot" --headless --path . -s res://spikes/s9/s9_server.gd -- \
  --port "$port" --run-for "$run_for" --expect "$expect" --log "$out/server.log" \
  "${server_extra[@]}" >"$out/server.out" 2>&1 &
server_pid=$!
sleep 1

for ((p = 0; p < procs; p++)); do
  taskset -c "$client_cpus" "$godot" --headless --path . -s res://spikes/s9/s9_load_client.gd -- \
    --url "ws://127.0.0.1:$port" --first $((p * conns)) --conns "$conns" --decode "$decode" \
    --log "$out/p$p.log" --run-for $((${run_for%.*} + 60)) >>"$out/clients.out" 2>&1 &
done

if [[ -n $extra_cmd ]]; then
  S9_URL="ws://127.0.0.1:$port" S9_OUT="$out" bash -c "$extra_cmd" >"$out/extra.out" 2>&1 &
fi

wait "$server_pid" || true
wait || true
python3 spikes/s9/aggregate.py "$out" | tee "$out/summary.md"
