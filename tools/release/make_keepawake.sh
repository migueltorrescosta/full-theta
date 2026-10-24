#!/usr/bin/env bash
# Regenerates app/web/keepawake.webm (VP9) and app/web/keepawake.mp4 (H.264, for Safari),
# the muted looping video that keeps a browser tablet awake over plain http://
# (FT-NET-046, D108; app/web/keep_awake.gd, KeepAwake). Run it only to change the video;
# the release build copies the committed files.
# The WebM needs an ffmpeg with libvpx-vp9: FFMPEG, else ffmpeg on PATH, else the one
# Playwright installs in ~/.cache/ms-playwright (it decodes only MJPEG, so Godot writes
# JPEG frames). The MP4 needs libx264: FFMPEG_X264, else the static ffmpeg of the
# imageio-ffmpeg wheel, fetched by uv into its cache (a dev tool, not shipped).
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
# Safari plays H.264 in an MP4 with the index at the front (faststart) and yuv420p.
x264=${FFMPEG_X264:-}
if [[ -z $x264 ]]; then
  x264=$(uv run --quiet --with imageio-ffmpeg python -c \
    'import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())')
fi
"$x264" -y -hide_banner -loglevel error -f image2pipe -c:v mjpeg -framerate 5 -i "$frames" \
  -c:v libx264 -profile:v baseline -level 3.0 -preset veryslow -crf 40 -pix_fmt yuv420p \
  -movflags +faststart -fflags +bitexact -flags:v +bitexact -map_metadata -1 -an \
  app/web/keepawake.mp4
ls -l app/web/keepawake.webm app/web/keepawake.mp4
