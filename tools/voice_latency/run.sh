#!/usr/bin/env bash
# One voice latency run (FT-AUD-015, the S7b method on the promoted code): the harness
# server (NetServer + VoiceService through VoiceSetup, Piper processes, S7b sim load)
# and two headless clients, c0 (target) and c1 (bystander), all pinned to VL_CPUS,
# then the summary (aggregate.py).
#   tools/voice_latency/run.sh OUT_DIR [--port 47850] [-- extra vl_server.gd flags]
# Env: VL_CPUS (6,7), VL_NICE (renice the run, e.g. -10; needs sudo), VL_LABEL (free
# text for the summary), FT_PIPER_BIN (use the release binary; FT_PIPER_DATA, else
# espeak-ng-data next to it), FT_PIPER_CACHE (voice models).
# Needs audio/prerendered_host (tools/tts/prerender.py) and the voices
# (tools/tts/fetch_voices.py). Timestamps use bash EPOCHREALTIME.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
out=$1
shift
port=47850
extra=()
while (($#)); do
  case $1 in
    --port) port=$2; shift 2 ;;
    --) shift; extra=("$@"); break ;;
    *) echo "run.sh: unknown flag $1" >&2; exit 2 ;;
  esac
done
cpus=${VL_CPUS:-6,7}
if [[ -n ${VL_NICE:-} ]]; then sudo -n renice -n "$VL_NICE" -p $$ >/dev/null; fi
[[ -d audio/prerendered_host ]] || { echo "run.sh: no audio/prerendered_host; run tools/tts/prerender.py" >&2; exit 1; }
godot=$(tools/get-godot.sh)
if [[ -z ${FT_PIPER_BIN:-} && -z ${FT_PIPER_PYTHON:-} ]]; then
  # Resolve the tools/tts venv once, so the server doesn't call uv.
  FT_PIPER_PYTHON=$(uv run --quiet --project tools/tts python -c 'import sys; print(sys.executable)')
  export FT_PIPER_PYTHON
fi
mkdir -p "$out"
rm -f "$out"/*.log "$out"/*.out "$out"/*.txt
adapter=${FT_PIPER_BIN:+binary $FT_PIPER_BIN}
echo "cpus=$cpus started_us=${EPOCHREALTIME/./} label=${VL_LABEL:-} nice=$(ps -o ni= -p $$ | tr -d ' ') adapter=${adapter:-piper_stream.py} args=${extra[*]}" >"$out/run.txt"
{ cat /proc/loadavg; ps -eo pid,psr,ni,pcpu,etime,comm --sort=-pcpu | head -8; } >"$out/load-before.txt"
taskset -c "$cpus" "$godot" --headless --path . -s res://tools/voice_latency/vl_server.gd -- \
  --port "$port" --log "$out/server.log" "${extra[@]}" >"$out/server.out" 2>&1 &
server_pid=$!
until grep -q '"ev":"listening"' "$out/server.log" 2>/dev/null; do
  kill -0 "$server_pid" 2>/dev/null || { echo "run.sh: server exited" >&2; cat "$out/server.out" >&2; exit 1; }
  sleep 0.2
done
for name in c0 c1; do
  taskset -c "$cpus" "$godot" --headless --path . -s res://tools/voice_latency/vl_client.gd -- \
    --url "ws://127.0.0.1:$port" --name "$name" --log "$out/$name.log" >>"$out/clients.out" 2>&1 &
done
wait "$server_pid" || true
{ cat /proc/loadavg; ps -eo pid,psr,ni,pcpu,etime,comm --sort=-pcpu | head -8; } >"$out/load-after.txt"
wait || true
python3 tools/voice_latency/aggregate.py "$out" | tee "$out/summary.md"
