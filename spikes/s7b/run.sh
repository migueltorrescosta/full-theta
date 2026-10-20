#!/usr/bin/env bash
# One S7b run: the spike server (with its Piper processes) and two headless
# clients, c0 (the target that plays every clip) and c1 (a bystander that must
# receive none), all pinned to S7B_CPUS (default 6,7), then the summary.
#   spikes/s7b/run.sh OUT_DIR [--port 47840] [-- extra server flags]
# Needs the prerendered fragments (spikes/s7b/prerender.py) and the voices
# (tools/tts/fetch_voices.py). To measure under another load, start that load
# first, then run this unchanged; the summary records the CPU set and label.
# Env: S7B_CPUS (6,7), S7B_NICE (none), S7B_RENDER (set: c0 renders under
# Xvfb with llvmpipe and plays the clips), S7B_LABEL (free text for the summary), S7B_DUMP (a
# directory: c0 saves every clip part there as WAV, for listening).
# Timestamps use bash EPOCHREALTIME: uutils date drops the leading zeros of %6N.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
out=$1
shift
port=47840
extra=()
while (($#)); do
  case $1 in
    --port) port=$2; shift 2 ;;
    --) shift; extra=("$@"); break ;;
    *) echo "run.sh: unknown flag $1" >&2; exit 2 ;;
  esac
done
cpus=${S7B_CPUS:-6,7}
# On a shared host, S7B_NICE (e.g. -10, needs sudo) raises this run above
# unpinned foreign jobs that wander onto its CPUs; the children inherit it.
if [[ -n ${S7B_NICE:-} ]]; then sudo -n renice -n "$S7B_NICE" -p $$ >/dev/null; fi
godot=$(tools/get-godot.sh)
python=$(uv run --quiet --project tools/tts python -c 'import sys; print(sys.executable)')
mkdir -p "$out"
rm -f "$out"/*.log "$out"/*.out

echo "cpus=$cpus started_us=${EPOCHREALTIME/./} label=${S7B_LABEL:-isolated} nice=$(ps -o ni= -p $$ | tr -d ' ') args=${extra[*]}" >"$out/run.txt"
# Busiest processes on the host before the run, to spot foreign load.
{ cat /proc/loadavg; ps -eo pid,psr,pcpu,etime,comm --sort=-pcpu | head -8; } >"$out/load-before.txt"
taskset -c "$cpus" "$godot" --headless --path . -s res://spikes/s7b/s7b_server.gd -- \
  --port "$port" --python "$python" --log "$out/server.log" "${extra[@]}" \
  >"$out/server.out" 2>&1 &
server_pid=$!

# Clients join once the server listens (after Start).
until grep -q ' listening ' "$out/server.log" 2>/dev/null; do
  kill -0 "$server_pid" 2>/dev/null || { echo "run.sh: server exited" >&2; cat "$out/server.out" >&2; exit 1; }
  sleep 0.2
done
for name in c0 c1; do
  dump=()
  if [[ -n ${S7B_DUMP:-} && $name == c0 ]]; then mkdir -p "$S7B_DUMP"; dump=(--dump "$S7B_DUMP"); fi
  mode=(--headless)
  if [[ -n ${S7B_RENDER:-} && $name == c0 ]]; then
    # A rendering client: Xvfb with llvmpipe (software GL), as in gate L5.
    mode=(--rendering-driver opengl3 --resolution 1280x720)
    dump+=(--render 1)
    LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe taskset -c "$cpus" xvfb-run -a \
      --server-args="-screen 0 1280x720x24" "$godot" "${mode[@]}" --path . \
      -s res://spikes/s7b/s7b_client.gd -- --url "ws://127.0.0.1:$port" --name "$name" \
      --log "$out/$name.log" "${dump[@]}" >>"$out/clients.out" 2>&1 &
    continue
  fi
  taskset -c "$cpus" "$godot" --headless --path . -s res://spikes/s7b/s7b_client.gd -- \
    --url "ws://127.0.0.1:$port" --name "$name" --log "$out/$name.log" "${dump[@]}" \
    >>"$out/clients.out" 2>&1 &
done

wait "$server_pid" || true
{ cat /proc/loadavg; ps -eo pid,psr,pcpu,etime,comm --sort=-pcpu | head -8; } >"$out/load-after.txt"
wait || true
python3 spikes/s7b/aggregate.py "$out" | tee "$out/summary.md"
