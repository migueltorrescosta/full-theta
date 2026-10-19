#!/usr/bin/env bash
# Regenerates app/web/keepawake.webm, the muted looping video that keeps a
# browser tablet awake over plain http:// (FT-NET-046, D108; net/keep_awake.gd).
# Run it only to change the video; the release build copies the committed file.
# Needs an ffmpeg with libvpx-vp9: FFMPEG, else ffmpeg on PATH, else the one
# Playwright installs in ~/.cache/ms-playwright (it decodes only MJPEG, so
# Godot writes JPEG frames).
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
godot=$(tools/get-godot.sh)
ffmpeg=${FFMPEG:-$(command -v ffmpeg || true)}
if [[ -z $ffmpeg ]]; then
  ffmpeg=$(find "$HOME/.cache/ms-playwright" -name ffmpeg-linux 2>/dev/null | sort | tail -1)
fi
[[ -n $ffmpeg ]] || { echo "make_keepawake.sh: no ffmpeg" >&2; exit 1; }
frames=$(mktemp)
trap 'rm -f "$frames"' EXIT
"$godot" --headless --path . -s res://tools/release/keepawake_frames.gd -- "$frames" 10 64 \
  >/dev/null 2>&1
"$ffmpeg" -y -hide_banner -loglevel error -f image2pipe -c:v mjpeg -framerate 5 -i "$frames" \
  -c:v libvpx-vp9 -b:v 20k -pix_fmt yuv420p -fflags +bitexact -map_metadata -1 \
  app/web/keepawake.webm
ls -l app/web/keepawake.webm
