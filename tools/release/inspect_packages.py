"""Inspect release packages before they are published (FT-ARC-022, FT-LIC-008).

    uv run --project tools python tools/release/inspect_packages.py \
        --version V --commit SHA DIR [--allow-stub-prerender]

Checks each package in DIR (package.py's output) for the game, the web export
built from the same commit (build_info.json inside both packs), the data files
the game reads (DATA_GLOBS) in both packs, the patched web
shell and index.js (D108), Piper with exactly the release voices and their model
cards, every release language's prerendered client clips in both packs and
host clips in the desktop pack only, the
GPL-3.0 text, the licence files, SOURCE.md naming the Piper and eSpeak NG
versions, and the release assets SOURCE.md promises. Prints one line per
package and exits 1 on any problem.
"""

import argparse
import hashlib
import json
import sys
import tarfile
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import fetch  # noqa: E402
import package  # noqa: E402
import pck  # noqa: E402
import web_patch  # noqa: E402

# Prerendered clips per language (D150-D154, tools/release/prerender.sh): the
# client pack goes in every pack, the host pack in desktop packs only; each
# language folder's index.json lists its files.
PRERENDER_DIR = "audio/prerendered"
PRERENDER_HOST_DIR = "audio/prerendered_host"
# Data files the game reads with FileAccess, which the export include filter
# (export_presets.cfg) must put in every pack: each file of the checkout that
# matches must be in the pack (D150-D152).
DATA_GLOBS = ("content/dialogue/*.json", "content/i18n/strings.json", "content/voices.json")
WEB_FILES = ("index.html", "index.js", "index.wasm", "index.pck", "keepawake.webm", "index.wasm.gz")
DESKTOP = {
    "linux": {
        "exe": "full-theta.x86_64",
        "piper": ["piper", "libespeak-ng.so.1", "libpiper_phonemize.so.1", "libonnxruntime.so.1.14.1"],
    },
    "windows": {
        "exe": "full-theta.exe",
        "piper": ["piper.exe", "espeak-ng.dll", "piper_phonemize.dll", "onnxruntime.dll"],
    },
}


class Archive:
    """Member names and contents of a tar.gz or zip, relative to `top`."""

    def __init__(self, path: Path, top: str):
        self.top = f"{top}/" if top else ""
        self.members: dict[str, object] = {}
        self.modes: dict[str, int] = {}
        if path.suffix == ".zip":
            self.zip = zipfile.ZipFile(path)
            for info in self.zip.infolist():
                self._add(info.filename, info, info.external_attr >> 16)
        else:
            self.zip = None
            self.tar = tarfile.open(path)
            for info in self.tar.getmembers():
                if info.isfile() or info.issym():
                    self._add(info.name, info, info.mode)

    def _add(self, name: str, info: object, mode: int) -> None:
        if name.startswith(self.top):
            rel = name[len(self.top) :]
            self.members[rel] = info
            self.modes[rel] = mode

    def has(self, rel: str) -> bool:
        return rel in self.members

    def executable(self, rel: str) -> bool:
        return bool(self.modes.get(rel, 0) & 0o111)

    def read(self, rel: str) -> bytes:
        info = self.members[rel]
        if self.zip:
            return self.zip.read(info)
        if info.issym():
            target = (Path(rel).parent / info.linkname).as_posix()
            return self.read(target)
        return self.tar.extractfile(info).read()

    def names_under(self, prefix: str) -> set[str]:
        return {m[len(prefix) :].split("/")[0] for m in self.members if m.startswith(prefix)}


class Inspector:
    def __init__(self, version: str, commit: str, allow_stub: bool):
        self.version = version
        self.commit = commit
        self.allow_stub = allow_stub
        self.errors: list[str] = []
        self.voices = package.release_voices()
        self.languages = package.release_languages()
        self.manifest = fetch.manifest()

    def check(self, ok: bool, where: str, what: str) -> None:
        if not ok:
            self.errors.append(f"{where}: {what}")

    def pack(self, where: str, data: bytes, desktop: bool) -> None:
        """build_info.json, data files and prerendered clips inside one pack."""
        try:
            p = pck.open_pack(data)
        except ValueError as e:
            self.check(False, where, str(e))
            return
        info = json.loads(p.read("build_info.json")) if "build_info.json" in p.files else {}
        self.check(info.get("commit") == self.commit, where, f"pack commit {info.get('commit')}")
        self.check(info.get("version") == self.version, where, f"pack version {info.get('version')}")
        for pattern in DATA_GLOBS:
            for f in sorted(package.ROOT.glob(pattern)):
                rel = f.relative_to(package.ROOT).as_posix()
                self.check(rel in p.files, where, f"no {rel} in the pack")
        self.clips(p, where, PRERENDER_DIR)
        if desktop:
            self.clips(p, where, PRERENDER_HOST_DIR)
        else:
            leaked = [f for f in p.files if f.startswith(f"{PRERENDER_HOST_DIR}/")]
            self.check(not leaked, where, f"host pack in a web pack: {leaked[:3]}")

    def clips(self, p: "pck.Pack", where: str, folder: str) -> None:
        for lang in self.languages:
            index = f"{folder}/{lang}/index.json"
            if index not in p.files:
                self.check(False, where, f"no {index}")
                continue
            clips = json.loads(p.read(index))
            if clips.get("stub"):
                self.check(self.allow_stub, where, f"{index} is a stub")
                continue
            if not clips.get("clips"):
                self.check(False, where, f"{index} lists no clips")
            for clip in clips.get("clips", []):
                # Imported audio sits in the pack as <clip>.import plus .godot/imported/.
                path = f"{folder}/{lang}/{clip}"
                ok = path in p.files or f"{path}.import" in p.files
                self.check(ok, where, f"missing {path}")

    def web(self, a: Archive, rel: str, where: str) -> None:
        for f in WEB_FILES:
            self.check(a.has(f"{rel}/{f}"), where, f"no {rel}/{f}")
        if not a.has(f"{rel}/index.js"):
            return
        js = a.read(f"{rel}/index.js").decode("utf-8", "replace")
        self.check(web_patch.GUARDED in js and web_patch.UNGUARDED not in js, where, "index.js unpatched")
        html = a.read(f"{rel}/index.html").decode("utf-8", "replace")
        self.check("startsWith('Secure Context')" in html, where, "index.html is not the custom shell")
        self.pack(f"{where} web pack", a.read(f"{rel}/index.pck"), desktop=False)

    def voices_in(self, a: Archive, rel: str, where: str) -> None:
        found = a.names_under(f"{rel}/")
        self.check(found == set(self.voices), where, f"voices {sorted(found)} != {self.voices}")
        for v in self.voices:
            for f in (f"{v}.onnx", f"{v}.onnx.json", "MODEL_CARD"):
                self.check(a.has(f"{rel}/{v}/{f}"), where, f"no {rel}/{v}/{f}")
            config = f"{rel}/{v}/{v}.onnx.json"
            if a.has(config):
                # The bundled Piper accepts only one-codepoint phonemes (D144).
                ids = json.loads(a.read(config)).get("phoneme_id_map", {})
                bad = [k for k in ids if len(k) != 1]
                self.check(not bad, where, f"{config} has multi-codepoint phonemes {bad}")

    def licences(self, a: Archive, where: str) -> None:
        text = a.read("LICENSE").decode() if a.has("LICENSE") else ""
        self.check(
            "GNU GENERAL PUBLIC LICENSE" in text and "Version 3, 29 June 2007" in text,
            where,
            "LICENSE is not the GPL-3.0 text",
        )
        for name in [*self.manifest["licences"], "VOICES.md"]:
            self.check(a.has(f"licenses/{name}"), where, f"no licenses/{name}")
        src = a.read("SOURCE.md").decode() if a.has("SOURCE.md") else ""
        must = [
            self.commit,
            f"Piper {self.manifest['piper']['version']}",
            self.manifest["espeak_ng"]["version"],
            package.asset_names(self.version)["source"],
            *self.manifest["sources"],
        ]
        for m in must:
            self.check(m in src, where, f"SOURCE.md doesn't name {m}")
        info = json.loads(a.read("BUILD.json")) if a.has("BUILD.json") else {}
        self.check(info.get("commit") == self.commit, where, "BUILD.json commit")

    def desktop(self, kind: str, path: Path) -> None:
        where = path.name
        top = path.name.removesuffix(".tar.gz").removesuffix(".zip")
        a = Archive(path, top)
        spec = DESKTOP[kind]
        self.check(a.has(spec["exe"]), where, f"no {spec['exe']}")
        if kind == "linux":
            self.check(a.executable(spec["exe"]), where, "game not executable")
            self.check(a.executable("piper/piper"), where, "piper not executable")
        if a.has(spec["exe"]):
            self.pack(f"{where} game pack", a.read(spec["exe"]), desktop=True)
        for f in spec["piper"]:
            self.check(a.has(f"piper/{f}"), where, f"no piper/{f}")
        self.check(a.has("piper/espeak-ng-data/phontab"), where, "no espeak-ng-data")
        self.voices_in(a, "piper/voices", where)
        self.web(a, "web", where)
        self.licences(a, where)

    def macos(self, path: Path) -> None:
        where = path.name
        a = Archive(path, "")
        c = f"{package.APP}/Contents"
        self.check(a.executable(f"{c}/MacOS/Full Theta"), where, "no executable game")
        packfile = f"{c}/Resources/Full Theta.pck"
        if a.has(packfile):
            self.pack(f"{where} game pack", a.read(packfile), desktop=True)
        else:
            self.check(False, where, f"no {packfile}")
        self.check(a.executable(f"{c}/Helpers/piper/piper"), where, "no executable Piper helper")
        for lib in package.MAC_LIBS:
            self.check(a.has(f"{c}/Helpers/piper/{lib}"), where, f"no Helpers/piper/{lib}")
        self.check(a.has(f"{c}/Resources/piper/espeak-ng-data/phontab"), where, "no espeak-ng-data")
        self.voices_in(a, f"{c}/Resources/piper/voices", where)
        self.web(a, f"{c}/Resources/web", where)
        self.licences(a, where)

    def assets(self, out: Path) -> None:
        names = package.asset_names(self.version)
        self.check((out / names["source"]).is_file(), "assets", f"no {names['source']}")
        for name, meta in self.manifest["sources"].items():
            p = out / name
            ok = p.is_file() and fetch.sha256(p) == meta["sha256"]
            self.check(ok, "assets", f"{name} missing or not the pinned archive")
        sums = out / "SHA256SUMS"
        if not sums.is_file():
            self.check(False, "assets", "no SHA256SUMS")
            return
        for line in sums.read_text().splitlines():
            digest, name = line.split("  ", 1)
            h = hashlib.sha256((out / name).read_bytes()).hexdigest()
            self.check(h == digest, "assets", f"SHA256SUMS mismatch for {name}")

    def run(self, out: Path) -> list[str]:
        names = package.asset_names(self.version)
        for kind in ("linux", "windows", "macos"):
            path = out / names[kind]
            if not path.is_file():
                self.check(False, path.name, "missing")
                continue
            before = len(self.errors)
            self.macos(path) if kind == "macos" else self.desktop(kind, path)
            status = "ok" if len(self.errors) == before else "FAIL"
            print(f"inspect: {path.name} {status} ({path.stat().st_size} bytes)")
        self.assets(out)
        return self.errors


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--version", required=True)
    ap.add_argument("--commit", required=True)
    ap.add_argument("--allow-stub-prerender", action="store_true")
    ap.add_argument("out", type=Path)
    a = ap.parse_args(argv)
    errors = Inspector(a.version, a.commit, a.allow_stub_prerender).run(a.out)
    for e in errors:
        print(f"inspect: {e}", file=sys.stderr)
    print(f"inspect: {'FAIL' if errors else 'pass'}, {len(errors)} problems")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
