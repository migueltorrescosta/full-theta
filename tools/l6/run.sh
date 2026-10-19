#!/usr/bin/env bash
# L6 export tier (FT-TST-019, FT-GEN-012, FT-ARC-022), run by `tools/gate.sh l6`:
# builds the release packages of the working tree (tools/release/build.sh, which
# also inspects them), then for the Linux package natively and the Windows
# package under Wine:
#   1. the exported game synthesises one line with each bundled voice through
#      its bundled Piper (`--tts-smoke`, ReleaseSmoke) and prints its build line;
#   2. the exported game serves its bundled web export (--http-root) and
#      headless Chromium loads it from a non-secure host name until the page
#      prints the same build line (web_load.mjs): same commit, engine started;
#   3. a headless server smoke run.
# The macOS package is built and inspected but not run (no Mac; #13).
# Logs and the WAVs in build/l6/run/. Needs wine, node and the Playwright
# Chromium headless shell (npm ci in tools/l6 the first time).
set -uo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1
out=build/l6
version=l6
line="Contact bearing three four two. Shields holding."
export WINEPREFIX=${WINEPREFIX:-$HOME/.cache/full-theta/l6-wineprefix} WINEDEBUG=-all

tools/release/build.sh "$version" "$out" --allow-dirty --allow-stub-prerender || exit 1
commit=$(git rev-parse HEAD)
[[ -z $(git status --porcelain) ]] || commit="$commit-dirty"
expected="build: $version $commit"
[[ -d tools/l6/node_modules ]] || (cd tools/l6 && npm ci --silent) || exit 1

run=$out/run
rm -rf "$run"
mkdir -p "$run"
tar -xzf "$out/full-theta-$version-linux-x86_64.tar.gz" -C "$run"
unzip -q "$out/full-theta-$version-windows-x86_64.zip" -d "$run"
failed=0

check() { # kind, port, path prefix for the game's own paths, launcher...
  local kind=$1 port=$2 prefix=$3
  shift 3
  # The game resolves relative paths against res://, so it gets absolute ones
  # (with a drive letter under Wine).
  local dir=$prefix$root/$run/$kind log=$root/$run/$kind
  mkdir -p "$log"
  echo "l6: $kind: tts smoke"
  # Wine passes the Windows build's CRLF line ends through.
  "$@" --headless -- --tts-smoke "$line" --out "$prefix$log/line.wav" 2>&1 | tr -d '\r' \
    >"$log/tts.log"
  local code=${PIPESTATUS[0]}
  grep -E "^(build|tts-smoke):" "$log/tts.log" | sed "s/^/l6: $kind: /"
  # One WAV per bundled voice (line.<voice>.wav): every voice loads (D144).
  local voices wavs=0
  voices=$(sed -n 's/^tts-smoke: bundled voices //p' "$log/tts.log" | tr ',' '\n' | grep -c .)
  for f in "$log"/line.*.wav; do
    [[ $(head -c 4 "$f" 2>/dev/null) == RIFF ]] && ((wavs++))
  done
  if ((code != 0)) || ! grep -qxF "$expected" "$log/tts.log" || ((voices == 0 || wavs != voices)); then
    echo "l6: $kind: tts smoke FAILED (exit $code, $log/tts.log)" >&2
    failed=1
  fi

  echo "l6: $kind: serve and load the web export"
  "$@" --headless -- --server --bind 127.0.0.1 --port "$port" --http-root "$dir/web" \
    --no-beacon --run-for 120 >"$log/server.log" 2>&1 &
  local pid=$!
  local waited=0
  until grep -q "server: listening" "$log/server.log" || ((waited >= 90)); do
    sleep 1
    ((waited++))
  done
  if ! node tools/l6/web_load.mjs "http://ft-l6.lan:$((port - 1))/" "$expected" 90 \
    | tee "$log/web.log" | sed "s/^/l6: $kind: /"; then
    failed=1
  fi
  grep -q "web_load: .* ok after" "$log/web.log" || failed=1
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null

  echo "l6: $kind: headless server smoke run"
  timeout 120 "$@" --headless -- --server --bind 127.0.0.1 --port 0 --no-beacon --run-for 2 \
    >"$log/smoke.log" 2>&1 || { echo "l6: $kind: server smoke FAILED" >&2; failed=1; }
}

check "full-theta-$version-linux-x86_64" 47911 "" "$run/full-theta-$version-linux-x86_64/full-theta.x86_64"
check "full-theta-$version-windows-x86_64" 47921 Z: wine "$run/full-theta-$version-windows-x86_64/full-theta.exe"
exit "$failed"
