#!/usr/bin/env bash
# Builds the S3 web export into build/s3/: the no-threads Web preset
# "S3 Engineering web", the keep-awake video, and .gz copies the server sends
# to clients that accept gzip. Prints raw and gzip sizes.
#   spikes/s3/build.sh [ARTEFACT_DIR]   # also copies the build there
# The video needs an ffmpeg with libvpx-vp9: FFMPEG, else ffmpeg on PATH,
# else the one Playwright installs in ~/.cache/ms-playwright.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
out=build/s3
godot=$(tools/get-godot.sh)
rm -rf "$out"
mkdir -p "$out"
"$godot" --headless --path . --export-release "S3 Engineering web" "$out/index.html" \
  >"$root/build/s3-export.log" 2>&1 || { cat "$root/build/s3-export.log" >&2; exit 1; }

# Godot 4.7.2's web audio init loads the sample-position AudioWorklet
# unconditionally, and AudioWorklet exists only in secure contexts, so on an
# http:// LAN page the engine stops at start-up with "Cannot read properties
# of undefined (reading 'addModule')". Guard that one call; the panel plays
# audio as a stream, mixed by the ScriptProcessorNode fallback.
# Upstream: https://github.com/godotengine/godot/issues/124637; on an engine
# upgrade, check it and drop this patch once fixed.
unguarded='GodotAudio.audioPositionWorkletPromise=ctx.audioWorklet.addModule(path)'
guarded='GodotAudio.audioPositionWorkletPromise=ctx.audioWorklet?ctx.audioWorklet.addModule(path):new Promise(function(){})'
grep -qF "$unguarded" "$out/index.js" || { echo "build.sh: audio init pattern not found" >&2; exit 1; }
sed -i "s|${unguarded//./\\.}|$guarded|" "$out/index.js"
grep -qF "$guarded" "$out/index.js" || { echo "build.sh: audio init patch failed" >&2; exit 1; }

ffmpeg=${FFMPEG:-$(command -v ffmpeg || true)}
if [[ -z $ffmpeg ]]; then
  ffmpeg=$(find "$HOME/.cache/ms-playwright" -name ffmpeg-linux 2>/dev/null | sort | tail -1)
fi
if [[ -n $ffmpeg ]]; then
  # Playwright's ffmpeg decodes only MJPEG, so Godot writes JPEG frames.
  frames=$root/build/s3-frames.bin
  "$godot" --headless --path . -s res://spikes/s3/s3_keepawake_frames.gd -- "$frames" 10 64 \
    >/dev/null 2>&1
  "$ffmpeg" -hide_banner -loglevel error -f image2pipe -c:v mjpeg -framerate 5 -i "$frames" \
    -c:v libvpx-vp9 -b:v 20k -pix_fmt yuv420p "$out/keepawake.webm"
  rm -f "$frames"
else
  echo "build.sh: no ffmpeg, so no keepawake.webm" >&2
fi

for f in "$out"/*; do
  case $f in
    *.html | *.js | *.wasm | *.pck | *.svg | *.json) gzip -9 -k -n "$f" ;;
  esac
done

echo "| File | Raw bytes | Gzip bytes |"
echo "|---|---|---|"
raw_total=0 gz_total=0
for f in "$out"/*; do
  [[ $f == *.gz ]] && continue
  raw=$(stat -c %s "$f")
  gz=$raw
  [[ -f $f.gz ]] && gz=$(stat -c %s "$f.gz")
  raw_total=$((raw_total + raw)) gz_total=$((gz_total + gz))
  echo "| $(basename "$f") | $raw | $gz |"
done
echo "| total | $raw_total | $gz_total |"

if (($#)); then
  mkdir -p "$1"
  rm -rf "$1/build"
  cp -r "$out" "$1/build"
  echo "copied to $1/build"
fi
