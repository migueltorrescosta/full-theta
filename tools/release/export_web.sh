#!/usr/bin/env bash
# Exports the Web preset to DIR and finishes it for plain-http pages (web_patch.py).
#   tools/release/export_web.sh DIR [LOG]
# Uses the slim web template (tools/release/build_web_template.sh, D197) when
# $WEB_TEMPLATE_OUT/web_nothreads_release.zip exists (default ~/.cache/full-theta/web-template),
# else the stock one; FT_STOCK_WEB_TEMPLATE=1 forces the stock template. With
# FT_REQUIRE_SLIM_WEB_TEMPLATE=1 (release builds: tools/release/build.sh sets it) a missing
# slim template, or FT_STOCK_WEB_TEMPLATE=1, is an error instead of a silent stock export. The preset file is
# swapped for a copy that names the template while the export runs, and restored.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
dir=$1
log=${2:-/dev/null}
godot=$(tools/get-godot.sh --with-templates)
template=${WEB_TEMPLATE_OUT:-$HOME/.cache/full-theta/web-template}/web_nothreads_release.zip
if [[ -n ${FT_REQUIRE_SLIM_WEB_TEMPLATE:-} ]]; then
  [[ -z ${FT_STOCK_WEB_TEMPLATE:-} ]] \
    || { echo "export_web: release mode needs the slim template, but FT_STOCK_WEB_TEMPLATE is set" >&2; exit 1; }
  [[ -f $template ]] \
    || { echo "export_web: release mode needs the slim template $template; run tools/release/build_web_template.sh" >&2; exit 1; }
fi
mkdir -p "$dir"
presets=$(mktemp)
cp export_presets.cfg "$presets"
trap 'cp "$presets" export_presets.cfg; rm -f "$presets"' EXIT
if [[ -f $template && -z ${FT_STOCK_WEB_TEMPLATE:-} ]]; then
  echo "export_web: slim template $template"
  python3 - "$template" <<'PY'
import re, sys
text = open("export_presets.cfg").read()
head, sep, body = text.partition("[preset.5.options]\n")
assert sep, "Web preset not found"
open("export_presets.cfg", "w").write(head + sep + f'custom_template/release="{sys.argv[1]}"\n' + body)
PY
else
  echo "export_web: stock template"
fi
"$godot" --headless --path . --export-release Web "$dir/index.html" >"$log" 2>&1 \
  || { tail -20 "$log" >&2; exit 1; }
[[ -s $dir/index.html ]] || { echo "export_web: no $dir/index.html" >&2; exit 1; }
uv run --quiet --project tools python tools/release/web_patch.py "$dir"
