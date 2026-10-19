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
2. Copies the keep-awake video (app/web/keepawake.webm, FT-NET-046).
3. Writes .gz copies the static server sends to clients that accept gzip.
"""

import gzip
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
UNGUARDED = "GodotAudio.audioPositionWorkletPromise=ctx.audioWorklet.addModule(path)"
GUARDED = (
    "GodotAudio.audioPositionWorkletPromise=ctx.audioWorklet?"
    "ctx.audioWorklet.addModule(path):new Promise(function(){})"
)
GZIP_SUFFIXES = (".html", ".js", ".wasm", ".pck", ".svg", ".json")


def patch_index_js(text: str) -> str:
    """The guarded index.js; raises ValueError unless the pattern occurs once."""
    if text.count(UNGUARDED) != 1:
        raise ValueError(f"web_patch: expected the audio init pattern once: {UNGUARDED}")
    return text.replace(UNGUARDED, GUARDED)


def finish(web: Path) -> None:
    index_js = web / "index.js"
    index_js.write_text(patch_index_js(index_js.read_text(encoding="utf-8")), encoding="utf-8")
    shutil.copy2(ROOT / "app/web/keepawake.webm", web / "keepawake.webm")
    for f in sorted(web.iterdir()):
        if f.suffix in GZIP_SUFFIXES:
            # mtime=0 keeps the .gz bytes reproducible.
            with f.open("rb") as src, gzip.GzipFile(f"{f}.gz", "wb", 9, mtime=0) as dst:
                shutil.copyfileobj(src, dst)


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        raise SystemExit("usage: web_patch.py WEB_DIR")
    finish(Path(argv[0]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
