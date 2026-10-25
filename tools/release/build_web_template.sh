#!/usr/bin/env bash
# Builds the slim Godot web export template (D197, #9): the pinned engine version
# (tools/godot-version) compiled from source for the no-threads web build with the
# modules and servers the game doesn't use switched off. Output (and the recipe's
# record of size and time): ~/.cache/full-theta/web-template/ (WEB_TEMPLATE_OUT).
#   tools/release/build_web_template.sh [JOBS]
# Needs git, python3, uv; installs user-space tools it is missing: emsdk (EMSDK_VERSION,
# the version Godot's own CI uses for this release) in ~/opt/emsdk and SCons (uv tool).
# Source checkout: ~/opt/godot-<version> (GODOT_SRC). tools/release/export_web.sh uses
# the result when it exists; delete it to export with the stock template.
#
# Kept on (by what the game uses): 3D rendering (the Helm and Viewer scenes), gdscript,
# freetype and the fallback text server (Latin text only; it must be switched on by hand), brotli (the default font is a
# WOFF2: without it no text is drawn), websocket, regex, svg (the
# default theme's icons), webp/jpg (imported textures), ogg and vorbis (prerendered
# voice lines), mbedtls (Crypto), JavaScript eval (JavaScriptBridge).
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
version=$(tr -d '[:space:]' <"$root/tools/godot-version")   # 4.7.2-stable
src=${GODOT_SRC:-$HOME/opt/godot-${version%-stable}}
emsdk=${EMSDK_DIR:-$HOME/opt/emsdk}
em_version=${EMSDK_VERSION:-4.0.11}   # EM_VERSION in .github/workflows/web_builds.yml of the tag
out=${WEB_TEMPLATE_OUT:-$HOME/.cache/full-theta/web-template}
jobs=${1:-8}

if [[ ! -d $src ]]; then
  git clone --depth 1 --branch "$version" https://github.com/godotengine/godot.git "$src"
fi
if [[ ! -d $emsdk ]]; then
  git clone --depth 1 https://github.com/emscripten-core/emsdk.git "$emsdk"
fi
if [[ ! -d $emsdk/upstream/emscripten ]]; then
  "$emsdk/emsdk" install "$em_version"
  "$emsdk/emsdk" activate "$em_version"
fi
command -v scons >/dev/null || uv tool install scons
# shellcheck disable=SC1091
source "$emsdk/emsdk_env.sh" >/dev/null

disabled_modules=(
  astcenc basis_universal betsy bmp camera csg cvtt dds enet etcpak fbx gltf gridmap hdr
  interactive_music jolt_physics jsonrpc ktx lightmapper_rd meshoptimizer mobile_vr mp3
  msdfgen multiplayer navigation_2d navigation_3d noise objectdb_profiler openxr raycast
  text_server_adv theora tga tinyexr upnp vhacd visual_shader webrtc webxr xatlas_unwrap
  godot_physics_2d godot_physics_3d zip
)
args=(
  platform=web target=template_release arch=wasm32 threads=no dlink_enabled=no
  javascript_eval=yes optimize=size lto=full debug_symbols=no
  disable_physics_2d=yes disable_physics_3d=yes disable_navigation_2d=yes
  disable_navigation_3d=yes disable_xr=yes minizip=no vulkan=no accesskit=no
)
for m in "${disabled_modules[@]}"; do args+=("module_${m}_enabled=no"); done
# The advanced text server is off, and the fallback one is off by default: without one no
# text is drawn.
args+=(module_text_server_fb_enabled=yes)

cd "$src"
start=$SECONDS
scons -j"$jobs" "${args[@]}"
mkdir -p "$out"
zip=bin/godot.web.template_release.wasm32.nothreads.zip
cp "$zip" "$out/web_nothreads_release.zip"
{
  echo "godot $version, emscripten $em_version, $(date -u +%FT%TZ)"
  echo "scons ${args[*]}"
  echo "build time $((SECONDS - start)) s with -j$jobs"
  unzip -l "$out/web_nothreads_release.zip" | grep -E "wasm|\.js"
} | tee "$out/BUILD.txt"
