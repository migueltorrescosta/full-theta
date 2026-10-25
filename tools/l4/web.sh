#!/usr/bin/env bash
# L4 browser station (FT-TST-021, FT-NET-013, FT-NET-046, FT-AUD-017; #9): exports the
# web build, serves it from a dedicated server on 2 cores, and drives it with headless
# Chromium (tools/l4/web_station.mjs, one worker, also pinned to the same 2 cores), with two
# headless clients holding Systems and Ops: the page joins by itself, plays the Tactical station, unlocks audio after a tap, is
# woken after a suspension, and a screenshot must not be blank. Afterwards the server's
# session log must show the join, the resumed join, commands, and snapshot ages from the
# browser. Logs and shot.png in build/l4web/.
#   tools/l4/web.sh        Env: L4_CPUS [0,1]
set -uo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1
cpus=${L4_CPUS:-0,1}
port=47941
out=$root/build/l4web
godot=$(tools/get-godot.sh --with-templates) || exit 1
[[ -d tools/l6/node_modules ]] || (cd tools/l6 && npm ci --silent) || exit 1
rm -rf "$out"
mkdir -p "$out"
echo "l4web: export"
tools/release/export_web.sh "$out/site" "$out/export.log" || exit 1
echo "l4web: serve and browse"
taskset -c "$cpus" "$godot" --headless --path . -- --server --bind 127.0.0.1 --port "$port" \
  --http-root "$out/site" --dev-all-stations --no-beacon --grace-s 15 --run-for 240 \
  --session-log "$out/session.jsonl" >"$out/server.log" 2>&1 &
server=$!
bots=()
trap 'kill "$server" "${bots[@]}" 2>/dev/null' EXIT
waited=0
until grep -q "server: listening" "$out/server.log" || ((waited >= 60)); do
  sleep 1
  ((waited++))
done
failed=0
# Two headless clients take Systems and Ops, so the browser's Tactical pick covers the crew.
for bot in systems ops; do
  taskset -c "$cpus" "$godot" --headless --path . -s res://tools/l4/l4_client.gd -- \
    --url "ws://127.0.0.1:$port" --name "$bot" --intent "tools/l4/web/$bot.intent" \
    --run-dir "$out" --log "$out/$bot.jsonl" --max-s 200 >>"$out/bots.out" 2>&1 &
  bots+=($!)
done
waited=0
until [[ -e $out/sig.systems_picked && -e $out/sig.ops_picked ]] || ((waited >= 60)); do
  sleep 1
  ((waited++))
done
taskset -c "$cpus" node tools/l4/web_station.mjs "http://ft-l4web.lan:$((port - 1))/" "$out" 150 \
  | tee "$out/web.log" || failed=1
# The server writes its snapshot-age line every 10 s: let the last window land.
sleep 11
touch "$out/sig.web_done"
wait "${bots[@]}" 2>/dev/null
kill "$server" 2>/dev/null
wait "$server" 2>/dev/null
python3 tools/l4/web_check.py "$out/session.jsonl" || failed=1
exit "$failed"
