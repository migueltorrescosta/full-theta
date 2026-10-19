"""Inspect release packages before they are published (FT-ARC-022, FT-LIC-008).

    uv run --project tools python tools/release/inspect_packages.py \
        --version V --commit SHA DIR

DIR is build.sh's output: the assets, plus exports/ (the Godot exports the
packages were made from). For each package the inspection checks:

- its file list exactly: the game and web export as exported, Piper as the
  pinned upstream archive has it, exactly the release voices, the licence
  files, and nothing else (no member outside the package's top folder);
- the web export and the game pack carry build_info.json of this commit, the
  data files the game reads (DATA_GLOBS), and every release language's
  prerendered clips (client pack in both, host pack in the game pack only);
- the patched web shell and index.js (D108), voice configs the bundled Piper
  accepts (D144), the macOS helper's rpath (D140);
- the GPL-3.0 text, SOURCE.md naming the Piper and eSpeak NG versions, BUILD.json.

Then it checks that DIR holds exactly the expected assets, each listed in
SHA256SUMS with its digest. Prints one line per package and exits 1 on any
problem.
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
COMMON_TOP = {"LICENSE", "licenses", "SOURCE.md", "BUILD.json"}
EXES = {"linux": "full-theta.x86_64", "windows": "full-theta.exe"}
# Written by build.sh into its output folder; not assets.
MARKER = ".ft-release-build"
NOT_ASSETS = ("SHA256SUMS", MARKER, ".gdignore")


class Archive:
    """Files of a tar.gz or zip, relative to `top`; `outside` lists members
    that aren't under it (or aren't plain files, links or folders)."""

    def __init__(self, path: Path, top: str):
        self.top = f"{top}/" if top else ""
        self.members: dict[str, object] = {}
        self.modes: dict[str, int] = {}
        self.outside: list[str] = []
        if path.suffix == ".zip":
            self.zip = zipfile.ZipFile(path)
            for info in self.zip.infolist():
                if not info.is_dir():
                    self._add(info.filename, info, info.external_attr >> 16)
        else:
            self.zip = None
            self.tar = tarfile.open(path)
            for info in self.tar.getmembers():
                if info.isfile() or info.issym():
                    self._add(info.name, info, info.mode)
                elif not info.isdir():
                    self.outside.append(info.name)

    def _add(self, name: str, info: object, mode: int) -> None:
        if name.startswith(self.top) and ".." not in name.split("/"):
            rel = name[len(self.top) :]
            self.members[rel] = info
            self.modes[rel] = mode
        else:
            self.outside.append(name)

    def has(self, rel: str) -> bool:
        return rel in self.members

    def executable(self, rel: str) -> bool:
        return bool(self.modes.get(rel, 0) & 0o111)

    def read(self, rel: str) -> bytes:
        info = self.members[rel]
        if self.zip:
            return self.zip.read(info)
        if info.issym():
            return self.read((Path(rel).parent / info.linkname).as_posix())
        return self.tar.extractfile(info).read()

    def files_under(self, prefix: str) -> set[str]:
        return {m[len(prefix) :] for m in self.members if m.startswith(prefix)}

    def top_level(self) -> set[str]:
        return {m.split("/")[0] for m in self.members}


def tree(folder: Path) -> set[str]:
    return {p.relative_to(folder).as_posix() for p in folder.rglob("*") if p.is_file()}


class Inspector:
    def __init__(self, version: str, commit: str):
        self.version = version
        self.commit = commit
        self.errors: list[str] = []
        self.voices = package.release_voices()
        self.languages = package.release_languages()
        self.manifest = fetch.manifest()
        self.voice_files = {
            f"{v}/{f}" for v in self.voices for f in (f"{v}.onnx", f"{v}.onnx.json", "MODEL_CARD")
        }
        self.licence_files = {*self.manifest["licences"], "VOICES.md"}

    def check(self, ok: bool, where: str, what: str) -> None:
        if not ok:
            self.errors.append(f"{where}: {what}")

    def same(self, where: str, what: str, got: set[str], expected: set[str]) -> None:
        """Exactly the expected files: names what is missing and what is extra."""
        for word, names in (("lacks", expected - got), ("has unexpected", got - expected)):
            listed = sorted(names)
            more = " ..." if len(listed) > 5 else ""
            self.check(not listed, where, f"{what} {word} {listed[:5]}{more}")

    def json(self, where: str, data: bytes, what: str) -> dict:
        try:
            value = json.loads(data)
        except (ValueError, UnicodeDecodeError) as e:
            self.check(False, where, f"{what} is not JSON: {e}")
            return {}
        if not isinstance(value, dict):
            self.check(False, where, f"{what} is not a JSON object")
            return {}
        return value

    def pack(self, where: str, data: bytes, desktop: bool) -> None:
        """build_info.json, data files and prerendered clips inside one pack."""
        try:
            p = pck.open_pack(data)
        except ValueError as e:
            self.check(False, where, str(e))
            return
        info = {}
        if "build_info.json" in p.files:
            info = self.json(where, p.read("build_info.json"), "build_info.json")
        self.check(info.get("commit") == self.commit, where, f"pack commit {info.get('commit')}")
        self.check(info.get("version") == self.version, where, f"pack version {info.get('version')}")
        leaked = sorted(f for f in p.files if f.split("/")[0] in ("build", "tests", "tools"))
        self.check(not leaked, where, f"build or test files in the pack: {leaked[:3]}")
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
            clips = self.json(where, p.read(index), index)
            listed = clips.get("clips")
            if not isinstance(listed, list) or not listed:
                self.check(False, where, f"{index} lists no clips")
                continue
            for clip in listed:
                # Imported audio sits in the pack as <clip>.import plus .godot/imported/.
                path = f"{folder}/{lang}/{clip}"
                ok = path in p.files or f"{path}.import" in p.files
                self.check(ok, where, f"missing {path}")

    def web(self, a: Archive, rel: str, where: str, exported: set[str]) -> None:
        self.same(where, f"{rel}/", a.files_under(f"{rel}/"), exported)
        if not a.has(f"{rel}/index.js") or not a.has(f"{rel}/index.html"):
            return
        js = a.read(f"{rel}/index.js").decode("utf-8", "replace")
        patched = web_patch.GUARDED in js and web_patch.UNGUARDED not in js
        self.check(patched, where, "index.js unpatched")
        html = a.read(f"{rel}/index.html").decode("utf-8", "replace")
        self.check("startsWith('Secure Context')" in html, where, "index.html is not the custom shell")
        if a.has(f"{rel}/index.pck"):
            self.pack(f"{where} web pack", a.read(f"{rel}/index.pck"), desktop=False)

    def voices_in(self, a: Archive, rel: str, where: str) -> None:
        self.same(where, f"{rel}/", a.files_under(f"{rel}/"), self.voice_files)
        for v in self.voices:
            config = f"{rel}/{v}/{v}.onnx.json"
            if a.has(config):
                # The bundled Piper accepts only one-codepoint phonemes (D144).
                ids = self.json(where, a.read(config), config).get("phoneme_id_map", {})
                bad = [k for k in ids if len(k) != 1]
                self.check(not bad, where, f"{config} has multi-codepoint phonemes {bad}")

    def licences(self, a: Archive, where: str) -> None:
        self.same(where, "licenses/", a.files_under("licenses/"), self.licence_files)
        text = a.read("LICENSE").decode("utf-8", "replace") if a.has("LICENSE") else ""
        self.check(
            "GNU GENERAL PUBLIC LICENSE" in text and "Version 3, 29 June 2007" in text,
            where,
            "LICENSE is not the GPL-3.0 text",
        )
        src = a.read("SOURCE.md").decode("utf-8", "replace") if a.has("SOURCE.md") else ""
        must = [
            self.commit,
            f"Piper {self.manifest['piper']['version']}",
            self.manifest["espeak_ng"]["version"],
            package.asset_names(self.version)["source"],
            *self.manifest["sources"],
        ]
        for m in must:
            self.check(m in src, where, f"SOURCE.md doesn't name {m}")
        info = self.json(where, a.read("BUILD.json"), "BUILD.json") if a.has("BUILD.json") else {}
        self.check(info.get("commit") == self.commit, where, "BUILD.json commit")

    def desktop(self, kind: str, path: Path, exports: Path) -> None:
        where = path.name
        a = Archive(path, path.name.removesuffix(".tar.gz").removesuffix(".zip"))
        exe = EXES[kind]
        self.check(not a.outside, where, f"members outside the top folder: {a.outside[:3]}")
        self.same(where, "top level", a.top_level(), {exe, "web", "piper", *COMMON_TOP})
        if kind == "linux":
            self.check(a.executable(exe), where, "game not executable")
            self.check(a.executable("piper/piper"), where, "piper not executable")
        if a.has(exe):
            self.pack(f"{where} game pack", a.read(exe), desktop=True)
        piper = {f for f in a.files_under("piper/") if not f.startswith("voices/")}
        self.same(where, "piper/", piper, package.upstream_files(kind))
        self.voices_in(a, "piper/voices", where)
        self.web(a, "web", where, tree(exports / "web"))
        self.licences(a, where)

    def macos(self, path: Path, exports: Path) -> None:
        where = path.name
        a = Archive(path, "")
        self.check(not a.outside, where, f"members outside the package: {a.outside[:3]}")
        self.same(where, "top level", a.top_level(), {package.APP, *COMMON_TOP})
        c = f"{package.APP}/Contents"
        with zipfile.ZipFile(exports / "macos/full-theta.zip") as z:
            exported = {i.filename for i in z.infolist() if not i.is_dir()}
        espeak = {f for f in package.upstream_files("macos") if f.startswith("espeak-ng-data/")}
        expected = (
            exported
            | {f"{c}/Helpers/piper/{f}" for f in ("piper", *package.MAC_LIBS)}
            | {f"{c}/Resources/piper/{f}" for f in espeak}
            | {f"{c}/Resources/piper/voices/{f}" for f in self.voice_files}
            | {f"{c}/Resources/web/{f}" for f in tree(exports / "web")}
        )
        app = {m for m in a.members if m.startswith(f"{package.APP}/")}
        self.same(where, f"{package.APP}/", app, expected)
        self.check(a.executable(f"{c}/MacOS/Full Theta"), where, "game not executable")
        packfile = f"{c}/Resources/Full Theta.pck"
        if a.has(packfile):
            self.pack(f"{where} game pack", a.read(packfile), desktop=True)
        helper = f"{c}/Helpers/piper/piper"
        self.check(a.executable(helper), where, "Piper helper not executable")
        if a.has(helper):
            # D140: the helper finds its dylibs through an @executable_path rpath.
            self.check(b"@executable_path" in a.read(helper), where, "Piper helper has no rpath")
        self.voices_in(a, f"{c}/Resources/piper/voices", where)
        self.web(a, f"{c}/Resources/web", where, tree(exports / "web"))
        self.licences(a, where)

    def assets(self, out: Path) -> None:
        names = package.asset_names(self.version)
        expected = {names[k] for k in ("linux", "windows", "macos", "source")}
        expected |= set(self.manifest["sources"])
        files = {p.name for p in out.iterdir() if p.is_file() and p.name not in NOT_ASSETS}
        self.same("assets", str(out), files, expected)
        for name, meta in self.manifest["sources"].items():
            p = out / name
            ok = p.is_file() and fetch.sha256(p) == meta["sha256"]
            self.check(ok, "assets", f"{name} missing or not the pinned archive")
        sums = out / "SHA256SUMS"
        if not sums.is_file():
            self.check(False, "assets", "no SHA256SUMS")
            return
        listed: dict[str, str] = {}
        lines = sums.read_text(encoding="utf-8", errors="replace").splitlines()
        for n, line in enumerate(lines, 1):
            digest, sep, name = line.partition("  ")
            if not sep or len(digest) != 64 or "/" in name or name in listed:
                self.check(False, "assets", f"SHA256SUMS line {n} is malformed: {line[:80]!r}")
                continue
            listed[name] = digest
        self.same("assets", "SHA256SUMS", set(listed), expected)
        for name, digest in listed.items():
            p = out / name
            if p.is_file():
                ok = hashlib.sha256(p.read_bytes()).hexdigest() == digest
                self.check(ok, "assets", f"SHA256SUMS mismatch for {name}")

    def run(self, out: Path) -> list[str]:
        names = package.asset_names(self.version)
        exports = out / "exports"
        if not exports.is_dir():
            self.check(False, str(out), "no exports/ (build.sh's export folder)")
            return self.errors
        for kind in ("linux", "windows", "macos"):
            path = out / names[kind]
            if not path.is_file():
                self.check(False, path.name, "missing")
                continue
            before = len(self.errors)
            try:
                if kind == "macos":
                    self.macos(path, exports)
                else:
                    self.desktop(kind, path, exports)
            except (OSError, tarfile.TarError, zipfile.BadZipFile, KeyError) as e:
                self.check(False, path.name, f"unreadable: {e!r}")
            status = "ok" if len(self.errors) == before else "FAIL"
            print(f"inspect: {path.name} {status} ({path.stat().st_size} bytes)")
        self.assets(out)
        return self.errors


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--version", required=True)
    ap.add_argument("--commit", required=True)
    ap.add_argument("out", type=Path)
    a = ap.parse_args(argv)
    errors = Inspector(a.version, a.commit).run(a.out)
    for e in errors:
        print(f"inspect: {e}", file=sys.stderr)
    print(f"inspect: {'FAIL' if errors else 'pass'}, {len(errors)} problems")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
