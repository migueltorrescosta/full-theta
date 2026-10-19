"""Assemble the Linux, Windows and macOS release packages (FT-ARC-022, FT-LIC-008).

    uv run --project tools python tools/release/package.py \
        --version V --commit SHA --exports DIR --out DIR [--repo OWNER/NAME]

DIR (exports) holds the Godot exports of one commit: linux/full-theta.x86_64,
windows/full-theta.exe, macos/full-theta.zip and web/ (finished by
web_patch.py). Each package gets the game, the web export, Piper with the
release voices (tools/tts/voices.json "release") and the licence material:
LICENSE (GPL-3.0), licenses/, SOURCE.md (source link and offer naming the
Piper and eSpeak NG versions) and BUILD.json. The third-party sources go next
to the packages as release assets, and SHA256SUMS lists every asset. Layout:
docs/release.md; inspection: inspect_packages.py.
"""

import argparse
import io
import json
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(ROOT / "tools/tts"))
import fetch  # noqa: E402
import fetch_voices  # noqa: E402

APP = "Full Theta.app"
MAC_LIBS = ("libespeak-ng.1.dylib", "libpiper_phonemize.1.dylib", "libonnxruntime.1.14.1.dylib")
DEFAULT_REPO = "migueltorrescosta/full-theta"


def release_voices() -> list[str]:
    return list(json.loads(fetch_voices.MANIFEST.read_text(encoding="utf-8"))["release"])


def release_languages() -> list[str]:
    """Languages with a release voice: "en" from en_GB-cori-medium."""
    return sorted({v.split("_")[0] for v in release_voices()})


def asset_names(version: str) -> dict[str, str]:
    base = f"full-theta-{version}"
    return {
        "linux": f"{base}-linux-x86_64.tar.gz",
        "windows": f"{base}-windows-x86_64.zip",
        "macos": f"{base}-macos.zip",
        "source": f"{base}-source.tar.gz",
    }


def source_md(version: str, commit: str, repo: str) -> str:
    m = fetch.manifest()
    url = f"https://github.com/{repo}"
    tag_page = f"{url}/releases/tag/{version}"
    srcs = "\n".join(f"  - `{name}` ({meta['url']})" for name, meta in m["sources"].items())
    return f"""# Source code

Full Theta {version} is free software under the GNU General Public License,
version 3 (`LICENSE`). This package was built from commit `{commit}`:

- Source: {url}/tree/{commit}
- Archive: `{asset_names(version)["source"]}` on the release page, {tag_page}

## Third-party programs in this package

- {m["piper"]["name"]} {m["piper"]["version"]} ({m["piper"]["licence"]}), the speech
  synthesiser the host runs as a separate program (`piper/`).
- {m["espeak_ng"]["name"]} {m["espeak_ng"]["version"]} ({m["espeak_ng"]["licence"]}),
  linked into Piper, with its data in `espeak-ng-data/`.
- {m["piper_phonemize"]["name"]} {m["piper_phonemize"]["version"]} ({m["piper_phonemize"]["licence"]}).
- {m["onnxruntime"]["name"]} {m["onnxruntime"]["version"]} ({m["onnxruntime"]["licence"]}).
- Godot Engine 4.7.2-stable (MIT), the engine in the game executable and the web export.
- Piper voices {", ".join(release_voices())}: see `licenses/VOICES.md`.

Licence texts are in `licenses/`.

## Source offer

The complete corresponding source of every GPL program in this package (Full
Theta, and eSpeak NG as built into Piper) is offered from the same place as this
package: the release page above carries, next to the packages, the game's source
archive and these exact upstream source archives:

{srcs}

They stay available there for as long as the release is offered. If a link
breaks, open an issue at {url}/issues and we will send the source.
"""


def voices_md() -> str:
    entries = {
        e["name"]: e
        for e in json.loads((ROOT / "content/provenance.json").read_text(encoding="utf-8"))[
            "entries"
        ]
    }
    lines = ["# Piper voices", ""]
    for v in release_voices():
        e = entries.get(f"Piper voice {v}")
        if e is None:
            raise SystemExit(f"package: no provenance entry 'Piper voice {v}' (FT-LIC-005)")
        lines += [
            f"## {v}",
            "",
            f"- Source: {e['source']}",
            f"- Licence: {e['licence']}",
            f"- Attribution: {e['attribution']}",
            f"- Model card: `piper/voices/{v}/MODEL_CARD`",
            "",
        ]
    return "\n".join(lines)


def common_files(version: str, commit: str, repo: str) -> dict[str, bytes]:
    """Package-relative path -> bytes, shared by every package."""
    files = {"LICENSE": (ROOT / "LICENSE").read_bytes()}
    for name, path in fetch.fetch_group("licences").items():
        files[f"licenses/{name}"] = path.read_bytes()
    files["licenses/VOICES.md"] = voices_md().encode()
    files["SOURCE.md"] = source_md(version, commit, repo).encode()
    m = fetch.manifest()
    info = {
        "version": version,
        "commit": commit,
        "voices": release_voices(),
        "languages": release_languages(),
        "piper": m["piper"]["version"],
        "espeak_ng": m["espeak_ng"]["version"],
    }
    files["BUILD.json"] = (json.dumps(info, indent=2) + "\n").encode()
    return files


def voice_files() -> dict[str, Path]:
    """voices/<voice>/<file> -> cached path for each release voice."""
    out = {}
    for v in release_voices():
        d = fetch_voices.fetch(v)
        for name in (f"{v}.onnx", f"{v}.onnx.json", "MODEL_CARD"):
            out[f"voices/{v}/{name}"] = d / name
    return out


def piper_tree(archive: Path, dest: Path) -> Path:
    """Extracts a Piper archive and returns its piper/ folder."""
    if archive.suffix == ".zip":
        with zipfile.ZipFile(archive) as z:
            z.extractall(dest)
    else:
        with tarfile.open(archive) as t:
            t.extractall(dest, filter="data")
    tree = dest / "piper"
    shutil.rmtree(tree / "pkgconfig", ignore_errors=True)
    for dsym in tree.glob("*.dSYM"):
        shutil.rmtree(dsym)
    return tree


class Writer:
    """Adds files to a tar.gz or zip under a top folder, keeping exec bits."""

    def __init__(self, path: Path, top: str):
        self.top = top
        self.zip = None
        self.tar = None
        if path.suffix == ".zip":
            self.zip = zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED, compresslevel=6)
        else:
            self.tar = tarfile.open(path, "w:gz", compresslevel=6)

    def _name(self, rel: str) -> str:
        return f"{self.top}/{rel}" if self.top else rel

    def add_bytes(self, rel: str, data: bytes, mode: int = 0o644) -> None:
        name = self._name(rel)
        if self.zip:
            info = zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0))
            info.external_attr = (0o100000 | mode) << 16
            info.create_system = 3
            info.compress_type = zipfile.ZIP_DEFLATED
            self.zip.writestr(info, data)
        else:
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = mode
            self.tar.addfile(info, io.BytesIO(data))

    def add_file(self, rel: str, path: Path) -> None:
        mode = 0o755 if path.stat().st_mode & 0o111 else 0o644
        if self.tar and path.is_symlink():
            info = tarfile.TarInfo(self._name(rel))
            info.type = tarfile.SYMTYPE
            info.linkname = path.readlink().as_posix()
            self.tar.addfile(info)
            return
        self.add_bytes(rel, path.read_bytes(), mode)

    def add_tree(self, rel: str, folder: Path) -> None:
        for p in sorted(folder.rglob("*")):
            if p.is_file() or p.is_symlink():
                self.add_file(f"{rel}/{p.relative_to(folder).as_posix()}", p)

    def add_common(self, files: dict[str, bytes]) -> None:
        for rel, data in files.items():
            self.add_bytes(rel, data)

    def close(self) -> None:
        (self.zip or self.tar).close()


def add_voices(w: Writer, rel: str) -> None:
    for name, path in voice_files().items():
        w.add_file(f"{rel}/{name}", path)


def package_desktop(kind: str, exe: Path, web: Path, common: dict, out: Path, tmp: Path) -> Path:
    path = out / asset_names(common["_version"])[kind]
    w = Writer(path, path.name.removesuffix(".tar.gz").removesuffix(".zip"))
    w.add_file(exe.name, exe)
    w.add_tree("web", web)
    archive = fetch.fetch_group("binaries")[kind]
    w.add_tree("piper", piper_tree(archive, tmp / kind))
    add_voices(w, "piper")
    w.add_common(common["files"])
    w.close()
    return path


def mac_helper(tmp: Path) -> tuple[Path, Path]:
    """rhasspy's macOS Piper plus piper-phonemize's dylibs, with an rpath so the
    program finds them beside itself (it ships with none; D140)."""
    bins = fetch.fetch_group("binaries")
    tree = piper_tree(bins["macos"], tmp / "macos")
    with tarfile.open(bins["macos_libs"]) as t:
        t.extractall(tmp / "macos_libs", filter="data")
    libs = tmp / "macos_libs/piper-phonemize/lib"
    helper = tmp / "helper"
    helper.mkdir()
    shutil.copy2(tree / "piper", helper / "piper")
    for name in MAC_LIBS:
        shutil.copyfile(libs / name, helper / name)  # follows the version symlinks
    tool = shutil.which("llvm-install-name-tool") or shutil.which("install_name_tool")
    if tool is None:
        raise SystemExit("package: needs llvm-install-name-tool (apt install llvm)")
    subprocess.run([tool, "-add_rpath", "@executable_path", str(helper / "piper")], check=True)
    (helper / "piper").chmod(0o755)
    return helper, tree / "espeak-ng-data"


def package_macos(godot_zip: Path, web: Path, common: dict, out: Path, tmp: Path) -> Path:
    path = out / asset_names(common["_version"])["macos"]
    w = Writer(path, "")
    with zipfile.ZipFile(godot_zip) as z:
        for info in z.infolist():
            if not info.is_dir():
                w.zip.writestr(info, z.read(info))
    contents = f"{APP}/Contents"
    helper, espeak = mac_helper(tmp)
    w.add_tree(f"{contents}/Helpers/piper", helper)
    w.add_tree(f"{contents}/Resources/piper/espeak-ng-data", espeak)
    add_voices(w, f"{contents}/Resources/piper")
    w.add_tree(f"{contents}/Resources/web", web)
    w.add_common(common["files"])
    w.close()
    return path


def write_sums(out: Path) -> None:
    lines = [
        f"{fetch.sha256(p)}  {p.name}"
        for p in sorted(out.iterdir())
        if p.is_file() and p.name != "SHA256SUMS"
    ]
    (out / "SHA256SUMS").write_text("\n".join(lines) + "\n")


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--version", required=True)
    ap.add_argument("--commit", required=True)
    ap.add_argument("--exports", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--repo", default=DEFAULT_REPO)
    a = ap.parse_args(argv)
    a.out.mkdir(parents=True, exist_ok=True)
    common = {"_version": a.version, "files": common_files(a.version, a.commit, a.repo)}
    web = a.exports / "web"
    with tempfile.TemporaryDirectory() as t:
        tmp = Path(t)
        for kind, exe in (("linux", "full-theta.x86_64"), ("windows", "full-theta.exe")):
            print(package_desktop(kind, a.exports / kind / exe, web, common, a.out, tmp))
        print(package_macos(a.exports / "macos/full-theta.zip", web, common, a.out, tmp))
    for name, path in fetch.fetch_group("sources").items():
        shutil.copyfile(path, a.out / name)
    write_sums(a.out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
