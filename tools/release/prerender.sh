#!/usr/bin/env bash
# Prerender step of the release build (D150-D154): clients load prerendered
# authored lines from their own export, and the host loads the number and
# name fragments it stitches. tools/tts/prerender_release.py renders each
# release language into two gitignored packs (generated audio is never
# committed, FT-AUD-002):
#   audio/prerendered/<lang>/       client pack, <line_id>.ogg, in every pack
#   audio/prerendered_host/<lang>/  host pack, {computer,npc}.{pcm,json},
#                                   desktop packs only (export_presets.cfg)
# Each folder has index.json, {"language": "en", "clips": [file, ...]}, which
# inspect_packages.py checks against each pack.
#   tools/release/prerender.sh LANG...
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
out=audio/prerendered
rm -rf "$out" audio/prerendered_host
mkdir -p "$out"
# The prerender voices ("prerender" in voices.json, not shipped) render the
# client clips; the runtime voices ("release") render the host pack.
mapfile -t voices < <(python3 -c 'import json; d = json.load(open("tools/tts/voices.json"))
print("\n".join(dict.fromkeys(d["prerender"] + d["release"])))')
uv run --quiet --project tools/tts python tools/tts/fetch_voices.py "${voices[@]}" >/dev/null
uv run --quiet --project tools/tts python tools/tts/prerender_release.py --out "$out" "$@"
