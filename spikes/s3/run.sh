#!/usr/bin/env bash
# S3 tick-delay run (FT-NET-039): the spike server with its tick log, then
# four phases, then the summary (aggregate.py).
#   spikes/s3/run.sh OUT_DIR [--phase-s 40] [-- extra server flags]
# Phases: idle (no clients); ws6 (6 headless Godot S4 clients); ws6+dl6 (the
# same plus 6 curl loops downloading the gzip export over and over); ws6+web6
# (6 headless Chromium pages join at once and play for 30 s; harness multi).
# Run spikes/s3/build.sh first. The server runs on CPUs S3_SERVER_CPUS (2,3),
# clients, curl and browsers on S3_CLIENT_CPUS (4,5,12,13).
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
out=$(realpath -m "$1")
shift
phase_s=40
extra=()
while (($#)); do
  case $1 in
    --phase-s) phase_s=$2; shift 2 ;;
    --) shift; extra=("$@"); break ;;
    *) echo "run.sh: unknown flag $1" >&2; exit 2 ;;
  esac
done
server_cpus=${S3_SERVER_CPUS:-2,3}
client_cpus=${S3_CLIENT_CPUS:-4,5,12,13}
godot=$(tools/get-godot.sh)
[[ -s build/s3/index.wasm ]] || { echo "run.sh: run spikes/s3/build.sh first" >&2; exit 1; }
mkdir -p "$out"
rm -f "$out"/*.log "$out"/*.csv "$out"/*.json "$out"/phases.txt "$out"/dl-*.txt
now_us() { echo "${EPOCHREALTIME/./}"; }
phase() { echo "$1 $2 $(now_us)" >>"$out/phases.txt"; }

taskset -c "$server_cpus" "$godot" --headless --path . -s res://spikes/s3/s3_server.gd -- \
  --run-for $((phase_s * 4 + 120)) --log "$out/server.log" --tick-log "$out/ticks.csv" \
  "${extra[@]}" >"$out/server.out" 2>&1 &
server_pid=$!
trap 'kill $server_pid ${client_pids[*]:-} 2>/dev/null || true' EXIT
sleep 3
# S3_RT=1 gives the server real-time priority (needs sudo), so other
# processes on its CPUs can't preempt it and the tick numbers show what HTTP
# itself costs.
if [[ ${S3_RT:-0} == 1 ]]; then
  sudo -n chrt -a -f -p 20 "$server_pid"
  echo "server pid $server_pid: SCHED_FIFO 20" >>"$out/server.out"
fi

phase idle start
sleep "$phase_s"
phase idle end

client_pids=()
for i in 0 1 2 3 4 5; do
  taskset -c "$client_cpus" "$godot" --headless --path . -s res://spikes/s4/s4_client.gd -- \
    --url ws://127.0.0.1:47821 --name "g$i" --log "$out/g$i.log" \
    --run-for $((phase_s * 3 + 90)) >>"$out/clients.out" 2>&1 &
  client_pids+=($!)
done
sleep 5
phase ws6 start
sleep "$phase_s"
phase ws6 end

files=(index.html index.js index.wasm index.pck)
download_loop() { # n: fetch the export with gzip until killed
  while :; do
    for f in "${files[@]}"; do
      curl -s -o /dev/null -H 'Accept-Encoding: gzip' -w '%{size_download} %{time_total}\n' \
        "http://127.0.0.1:47820/$f" >>"$out/dl-$1.txt"
    done
  done
}
dl_pids=()
phase ws6+dl6 start
for i in 0 1 2 3 4 5; do
  download_loop "$i" &
  dl_pids+=($!)
  taskset -cp "$client_cpus" "$!" >/dev/null
done
sleep "$phase_s"
kill "${dl_pids[@]}" 2>/dev/null || true
wait "${dl_pids[@]}" 2>/dev/null || true
phase ws6+dl6 end
sleep 3

phase ws6+web6 start
(cd spikes/s3/harness && taskset -c "$client_cpus" node harness.mjs multi --clients 6 \
  --fps-seconds 30 --out "$out/multi.json" >"$out/multi.out" 2>&1) || true
phase ws6+web6 end

kill "${client_pids[@]}" 2>/dev/null || true
kill "$server_pid" 2>/dev/null || true
wait 2>/dev/null || true
trap - EXIT
python3 -I spikes/s3/aggregate.py "$out" | tee "$out/summary.md"
