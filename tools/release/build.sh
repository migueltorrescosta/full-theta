#!/usr/bin/env bash
# Builds the release packages for one commit (FT-ARC-022, FT-GEN-012, FT-LIC-008):
#   tools/release/build.sh VERSION OUT_DIR [--allow-dirty]
# 1. writes build_info.json (version, commit), which every export carries;
# 2. prerenders each release language's clips (prerender.sh);
# 3. exports Linux, Windows, macOS and Web (export_presets.cfg) into OUT_DIR/exports;
# 4. patches the web export for http:// pages (web_patch.py, D108);
# 5. packages the three desktop builds with the web export, Piper, the release
#    voices and the licence material, plus the source archives (package.py);
# 6. inspects the result (inspect_packages.py) and fails on any problem.
# The release workflow (.github/workflows/release.yml) and `gate.sh l6` run it;
# docs/release.md describes the artefacts. VERSION is a tag name such as v1.2.3
# or v1.2.3-rc.1. OUT_DIR must be new, empty or an earlier build's output.
# --allow-dirty builds an uncommitted tree (the commit gets a -dirty suffix).
set -euo pipefail
usage="usage: build.sh VERSION OUT_DIR [--allow-dirty]"
version=${1:?$usage}
out=$(realpath -m -- "${2:?$usage}")
shift 2
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
allow_dirty=0
for arg in "$@"; do
  case $arg in
    --allow-dirty) allow_dirty=1 ;;
    *) echo "build.sh: unknown argument $arg" >&2; exit 2 ;;
  esac
done
if ! [[ $version =~ ^v[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.]+)?$ ]]; then
  echo "build.sh: VERSION $version is not a version tag like v1.2.3 or v1.2.3-rc.1" >&2
  exit 2
fi
marker=.ft-release-build  # inspect_packages.MARKER
if [[ -e $out ]] && [[ -n $(ls -A "$out") ]] && [[ ! -f $out/$marker ]]; then
  echo "build.sh: $out is not empty and not an earlier build's output; refusing to replace it" >&2
  exit 1
fi

commit=$(git rev-parse HEAD)
if [[ -n $(git status --porcelain) ]]; then
  ((allow_dirty)) || { echo "build.sh: uncommitted changes (use --allow-dirty)" >&2; exit 1; }
  commit="$commit-dirty"
fi
py() { uv run --quiet --project tools python "$@"; }

godot=$(tools/get-godot.sh --with-templates)
rm -rf "$out"
mkdir -p "$out"/exports/{linux,windows,macos,web}
# The marker lets a later run replace this folder; .gdignore keeps Godot from
# importing (and exporting) its files when OUT_DIR is inside the project.
touch "$out/$marker" "$out/.gdignore"
trap 'rm -f "$root/build_info.json"' EXIT
printf '{"commit": "%s", "version": "%s"}\n' "$commit" "$version" >build_info.json

mapfile -t langs < <(py -c 'import sys; sys.path.insert(0, "tools/release")
import package; print("\n".join(package.release_languages()))')
echo "build: prerender ${langs[*]}"
tools/release/prerender.sh "${langs[@]}"
# Importing the fresh clips crashed Godot 4.7.2 once on fugaku (a segfault that
# didn't recur), so one retry; a second failure stops the build.
"$godot" --headless --path . --import >"$out/exports/import.log" 2>&1 || {
  echo "build: import failed ($?), retrying once" >&2
  "$godot" --headless --path . --import >"$out/exports/import.log" 2>&1
}

export_preset() { # preset, path
  echo "build: export $1"
  "$godot" --headless --path . --export-release "$1" "$2" >"$out/exports/$1.log" 2>&1 \
    || { tail -20 "$out/exports/$1.log" >&2; return 1; }
  [[ -s $2 ]] || { echo "build: $1 export wrote no $2" >&2; return 1; }
}
export_preset Linux "$out/exports/linux/full-theta.x86_64"
export_preset Windows "$out/exports/windows/full-theta.exe"
export_preset macOS "$out/exports/macos/full-theta.zip"
export_preset Web "$out/exports/web/index.html"
py tools/release/web_patch.py "$out/exports/web"

echo "build: package"
git archive --format=tar.gz --prefix="full-theta-$version/" \
  -o "$out/full-theta-$version-source.tar.gz" HEAD
py tools/release/package.py --version "$version" --commit "$commit" \
  --exports "$out/exports" --out "$out" --repo "${GITHUB_REPOSITORY:-migueltorrescosta/full-theta}"

echo "build: inspect"
py tools/release/inspect_packages.py --version "$version" --commit "$commit" "$out"
