#!/usr/bin/env bash
# One S4 run: the spike server plus N headless Godot clients, then the summary.
#   spikes/s4/run.sh OUT_DIR [--clients 8] [--run-for 60] [--port 47810]
#       [--kill NAME@S] [--stall NAME@S] [--voice NAME@S] [-- extra server flags]
# --kill sends SIGKILL to client NAME at S seconds and restarts it 1 s later
# with the same token file; --stall makes NAME stop polling for 2 s at S;
# --voice queues a 3 s clip and a full snapshot for NAME at S.
# Timestamps use bash EPOCHREALTIME: uutils date drops the leading zeros of %6N.
# Run it inside the loss namespace: spikes/s4/netns.sh exec spikes/s4/run.sh ...
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
out=$1
shift
clients=8 run_for=60 port=47810 kill_spec="" stall_spec="" voice_spec=""
extra=()
while (($#)); do
  case $1 in
    --clients) clients=$2; shift 2 ;;
    --run-for) run_for=$2; shift 2 ;;
    --port) port=$2; shift 2 ;;
    --kill) kill_spec=$2; shift 2 ;;
    --stall) stall_spec=$2; shift 2 ;;
    --voice) voice_spec=$2; shift 2 ;;
    --) shift; extra=("$@"); break ;;
    *) echo "run.sh: unknown flag $1" >&2; exit 2 ;;
  esac
done
godot=$(tools/get-godot.sh)
mkdir -p "$out"
rm -f "$out"/*.log "$out"/*.tok

server_args=(--port "$port" --run-for "$run_for" --log "$out/server.log")
if [[ -n $voice_spec ]]; then
  server_args+=(--voice-to "${voice_spec%@*}" --voice-at "${voice_spec#*@}")
fi
"$godot" --headless --path . -s res://spikes/s4/s4_server.gd -- "${server_args[@]}" "${extra[@]}" \
  >"$out/server.out" 2>&1 &
server_pid=$!
sleep 1

client() { # name log [extra client flags]
  local name=$1 log=$2
  shift 2
  "$godot" --headless --path . -s res://spikes/s4/s4_client.gd -- \
    --url "ws://127.0.0.1:$port" --name "$name" --token-file "$out/$name.tok" \
    --log "$log" --run-for $((run_for + 15)) "$@" >>"$out/clients.out" 2>&1 &
  pids[$name]=$!
}

declare -A pids
for ((i = 0; i < clients; i++)); do
  name=c$i
  flags=()
  if [[ -n $stall_spec && ${stall_spec%@*} == "$name" ]]; then
    flags+=(--stall-at "${stall_spec#*@}" --stall-for 2)
  fi
  client "$name" "$out/$name.log" "${flags[@]}"
done

if [[ -n $kill_spec ]]; then
  victim=${kill_spec%@*}
  sleep "${kill_spec#*@}"
  killed_us=${EPOCHREALTIME/./}
  kill -9 "${pids[$victim]}"
  echo "killed $victim at $killed_us" >>"$out/clients.out"
  sleep 1
  client "$victim" "$out/$victim.restart.log" --launched-us "${EPOCHREALTIME/./}"
fi

wait "$server_pid" || true
wait || true
python3 spikes/s4/aggregate.py "$out" | tee "$out/summary.md"
