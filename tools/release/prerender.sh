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
# Until tools/tts/prerender_release.py is on this branch, this writes stub
# indexes ("stub": true) that inspect_packages.py rejects unless
# --allow-stub-prerender (l6 and dry runs), so a tagged release fails.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
out=audio/prerendered
rm -rf "$out" audio/prerendered_host
mkdir -p "$out"
if [[ -f tools/tts/prerender_release.py ]]; then
  # The prerender voices ("prerender" in voices.json) render the clips but
  # don't ship in the packages.
  mapfile -t voices < <(python3 -c 'import json; print("\n".join(json.load(open("tools/tts/voices.json"))["prerender"]))')
  uv run --quiet --project tools/tts python tools/tts/fetch_voices.py "${voices[@]}" >/dev/null
  uv run --quiet --project tools/tts python tools/tts/prerender_release.py --out "$out" "$@"
  exit
fi
echo "prerender: no tools/tts/prerender_release.py yet; writing stub indexes" >&2
for lang in "$@"; do
  for dir in "$out" audio/prerendered_host; do
    mkdir -p "$dir/$lang"
    printf '{"language": "%s", "clips": [], "stub": true}\n' "$lang" >"$dir/$lang/index.json"
  done
done
