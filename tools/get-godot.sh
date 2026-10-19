#!/usr/bin/env bash
# Fetch the pinned Godot (tools/godot-version) into a cache and verify it
# against tools/godot.sha512 (FT-ARC-001). Prints the binary path.
#   tools/get-godot.sh                   # editor binary only (runs --headless)
#   tools/get-godot.sh --with-templates  # also install export templates
# GODOT_CACHE overrides the cache dir; GODOT_SHA512 the checksum file.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
version=$(cat "$root/tools/godot-version")
sums=${GODOT_SHA512:-$root/tools/godot.sha512}
cache=${GODOT_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/full-theta/godot/$version}
base="https://github.com/godotengine/godot/releases/download/$version"
binary_zip="Godot_v${version}_linux.x86_64.zip"
templates="Godot_v${version}_export_templates.tpz"
binary="$cache/Godot_v${version}_linux.x86_64"

with_templates=0
for arg in "$@"; do
  case $arg in
    --with-templates) with_templates=1 ;;
    *) echo "get-godot.sh: unknown argument $arg" >&2; exit 2 ;;
  esac
done

mkdir -p "$cache"

# Download $1 unless it is cached, then verify it against the pinned sum.
fetch() {
  local name=$1 expected
  expected=$(awk -v n="$name" '$2 == n { print $1 }' "$sums")
  if [[ -z $expected ]]; then
    echo "get-godot.sh: no checksum for $name in $sums" >&2
    exit 1
  fi
  if [[ ! -f $cache/$name ]]; then
    curl -fsSL --retry 3 -o "$cache/$name.part" "$base/$name" >&2
    mv "$cache/$name.part" "$cache/$name"
  fi
  if [[ $(sha512sum "$cache/$name" | cut -d' ' -f1) != "$expected" ]]; then
    echo "get-godot.sh: checksum mismatch for $name" >&2
    exit 1
  fi
}

fetch "$binary_zip"
if [[ ! -x $binary ]]; then
  unzip -qo "$cache/$binary_zip" -d "$cache"
fi

if (( with_templates )); then
  fetch "$templates"
  # Godot looks for templates under <data dir>/export_templates/<x.y.z.status>.
  dest=${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/${version/-/.}
  if [[ ! -f $dest/version.txt ]]; then
    tmp=$(mktemp -d)
    unzip -qo "$cache/$templates" -d "$tmp"
    mkdir -p "$dest"
    cp -r "$tmp"/templates/. "$dest"/
    rm -rf "$tmp"
  fi
fi

echo "$binary"
