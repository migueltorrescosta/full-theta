"""Finish the Web export for plain http:// LAN pages (D108, FT-NET-030).

    python tools/release/web_patch.py WEB_DIR

1. Guards the engine's AudioWorklet call in index.js. Godot 4.7.2 loads the
   sample-position AudioWorklet unconditionally, and AudioWorklet exists only
   in secure contexts, so on an http:// page the engine stops at start-up with
   "Cannot read properties of undefined (reading 'addModule')". Audio then mixes
   through the ScriptProcessorNode fallback. Upstream:
   https://github.com/godotengine/godot/issues/124637 (the shell's secure-context
   check is app/web/shell.html, godotengine/godot#124636). Fails when the
   pattern is missing, so an engine upgrade that changes it stops the build;
   tools/tests/test_release.py checks the pinned template too. Drop the patch
   once upstream is fixed (docs/release.md).
2. Copies the keep-awake videos (app/web/keepawake.webm and .mp4, FT-NET-046).
3. Puts a content hash in the names of the wasm, the pack and the audio worklets
   (index.wasm becomes index.<10 hex digits>.wasm) and in the page's "executable" and
   "fileSizes", so the static server can send them as immutable and a returning
   browser reuses its cached copy without asking (D197, StaticServer.cache_control).
   index.js and index.html keep their names and are revalidated.
4. Writes a voice pack per prerendered language (voice_pack.py, D294): the web
   pack carries no clips, so a browser station fetches only its session's.
5. Writes .gz and .br copies; the static server sends .br to clients that accept
   brotli (browsers offer it only over HTTPS), else .gz to those that accept gzip.
"""

import gzip
import hashlib
import re
import shutil
import sys
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import brotli

sys.path.insert(0, str(Path(__file__).resolve().parent))
import voice_pack  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
UNGUARDED = "GodotAudio.audioPositionWorkletPromise=ctx.audioWorklet.addModule(path)"
GUARDED = (
    "GodotAudio.audioPositionWorkletPromise=ctx.audioWorklet?"
    "ctx.audioWorklet.addModule(path):new Promise(function(){})"
)
# Compressed copies (.gz and .br) are written for these.
GZIP_SUFFIXES = (".html", ".js", ".wasm", ".pck", ".svg", ".json")
HASHED_SUFFIXES = (".wasm", ".pck", ".audio.worklet.js", ".audio.position.worklet.js")
KEEPAWAKE = ("keepawake.webm", "keepawake.mp4")


def patch_index_js(text: str) -> str:
    """The guarded index.js; raises ValueError unless the pattern occurs once."""
    if text.count(UNGUARDED) != 1:
        raise ValueError(f"web_patch: expected the audio init pattern once: {UNGUARDED}")
    return text.replace(UNGUARDED, GUARDED)


def hash_names(web: Path) -> str:
    """Renames the files in HASHED_SUFFIXES to index.<hash><suffix> and points index.html
    at them; returns the hash. The hash covers their bytes, so it changes with any."""
    present = [(suffix, web / f"index{suffix}") for suffix in HASHED_SUFFIXES]
    present = [(suffix, f) for suffix, f in present if f.is_file()]
    digest = hashlib.sha256()
    for suffix, f in present:
        digest.update(suffix.encode() + f.read_bytes())
    tag = digest.hexdigest()[:10]
    html_path = web / "index.html"
    html = html_path.read_text(encoding="utf-8")
    if html.count('"executable":"index"') != 1:
        raise ValueError('web_patch: expected "executable":"index" once in index.html')
    html = html.replace('"executable":"index"', f'"executable":"index.{tag}"')
    for suffix, f in present:
        f.rename(web / f"index.{tag}{suffix}")
        html = html.replace(f'"index{suffix}":', f'"index.{tag}{suffix}":')
    html_path.write_text(html, encoding="utf-8")
    return tag


def finish(web: Path, prerendered: Path = ROOT / "audio/prerendered") -> None:
    index_js = web / "index.js"
    index_js.write_text(patch_index_js(index_js.read_text(encoding="utf-8")), encoding="utf-8")
    for video in KEEPAWAKE:
        shutil.copy2(ROOT / "app/web" / video, web / video)
    hash_names(web)
    voice_pack.write_all(web, prerendered)
    files = [f for f in sorted(web.iterdir()) if f.suffix in GZIP_SUFFIXES]
    # The wasm's brotli copy takes about a minute; the files compress in parallel.
    with ProcessPoolExecutor() as pool:
        list(pool.map(compress, files))


def compress(f: Path) -> None:
    """Writes f.gz and f.br, both reproducible (mtime=0 in the gzip header)."""
    with f.open("rb") as src, gzip.GzipFile(f"{f}.gz", "wb", 9, mtime=0) as dst:
        shutil.copyfileobj(src, dst)
    # A 16 MiB window (lgwin 24, the most browsers accept) saves 0.1 MB on the wasm.
    Path(f"{f}.br").write_bytes(brotli.compress(f.read_bytes(), quality=11, lgwin=24))


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        raise SystemExit("usage: web_patch.py WEB_DIR")
    finish(Path(argv[0]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
