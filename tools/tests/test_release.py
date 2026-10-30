# FT: FT-ARC-022
"""Release tooling (tools/release/): the web patch, the pack reader, the release
voice list and its provenance, and the provenance review checks."""

import io
import json
import os
import re
import struct
import sys
import zipfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/release"))
import fetch  # noqa: E402
import package  # noqa: E402
import pck  # noqa: E402
import voice_pack  # noqa: E402
import web_patch  # noqa: E402


def template_zip() -> Path:
    version = (ROOT / "tools/godot-version").read_text().strip().replace("-", ".")
    data = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
    return data / "godot/export_templates" / version / "web_nothreads_release.zip"


# FT: FT-NET-030
def test_patch_guards_the_audio_worklet_call():
    js = "a;" + web_patch.UNGUARDED + ";b"
    out = web_patch.patch_index_js(js)
    assert web_patch.GUARDED in out and web_patch.UNGUARDED not in out
    for bad in ("a;b", js + js):
        with pytest.raises(ValueError):
            web_patch.patch_index_js(bad)


# FT: FT-NET-030
@pytest.mark.skipif(not template_zip().is_file(), reason="export templates not installed")
def test_pinned_engine_still_has_the_patched_pattern():
    """Fails when an engine upgrade changes the patched index.js pattern or
    the API the custom shell calls (D108; godotengine/godot#124636, #124637)."""
    js = zipfile.ZipFile(template_zip()).read("godot.js").decode()
    assert js.count(web_patch.UNGUARDED) == 1
    for api in ("getMissingFeatures", "startGame"):
        assert api in js


# FT: FT-NET-030
def test_shell_keeps_the_engine_placeholders_and_drops_only_the_secure_context_check():
    html = (ROOT / "app/web/shell.html").read_text()
    for placeholder in ("$GODOT_CONFIG", "$GODOT_URL", "$GODOT_THREADS_ENABLED", "$GODOT_HEAD_INCLUDE"):
        assert placeholder in html
    assert ".filter((m) => !m.startsWith('Secure Context'))" in html
    assert "124636" in html


def make_pack(files: dict[str, bytes]) -> bytes:
    """A format 4 pack with relative file base, as Godot 4.7 writes it."""
    header = 4 + 4 * 5 + 8 + 8 + 16 * 4
    blob = b"".join(files.values())
    table = struct.pack("<I", len(files))
    offset = 0
    for path, data in files.items():
        name = path.encode() + b"\0" * (4 - len(path) % 4)
        table += struct.pack("<I", len(name)) + name + struct.pack("<QQ", offset, len(data))
        table += b"\0" * 16 + struct.pack("<I", 0)
        offset += len(data)
    head = struct.pack("<4sIIIIIQQ", b"GDPC", 4, 4, 7, 2, pck.FLAG_REL_FILEBASE, header, header + len(blob))
    return head + b"\0" * (header - len(head)) + blob + table


def test_pack_reader_standalone_and_embedded():
    files = {"build_info.json": b'{"commit": "abc"}', "audio/prerendered/en/index.json": b"{}"}
    data = make_pack(files)
    p = pck.open_pack(data)
    assert set(p.files) == set(files)
    assert p.read("build_info.json") == files["build_info.json"]
    exe = b"\x7fELF" + b"x" * 100 + data + struct.pack("<Q", len(data)) + b"GDPC"
    assert pck.open_pack(exe).read("audio/prerendered/en/index.json") == b"{}"
    with pytest.raises(ValueError):
        pck.open_pack(b"not a pack")


# FT: FT-LIC-005
def test_release_voices_are_audited_and_listed():
    voices = json.loads((ROOT / "tools/tts/voices.json").read_text())
    release = package.release_voices()
    assert release and set(release) <= set(voices["voices"])
    for v in release:
        assert v.endswith("-medium"), "runtime voices are medium (D105)"
        assert "tugão" not in v, "tugão is development-only until #16 (D105)"
    assert package.release_languages() == sorted({v.split("_")[0] for v in release})
    package.voices_md()  # fails on a release voice with no provenance entry


# FT: FT-LIC-008
def test_source_offer_names_piper_and_espeak_versions_and_sources():
    m = fetch.manifest()
    text = package.source_md("v1.2.3", "c0ffee", "o/r")
    assert f"Piper {m['piper']['version']}" in text
    assert m["espeak_ng"]["version"] in text
    assert "https://github.com/o/r/tree/c0ffee" in text
    for name in m["sources"]:
        assert name in text
    for group in fetch.GROUPS:
        for meta in m[group].values():
            assert re.fullmatch(r"[0-9a-f]{64}", meta["sha256"])


# FT: FT-LIC-004
def test_provenance_record_matches_the_spec_table():
    """Provenance review: docs/provenance.md keeps spec §13.2's record."""

    def table(path: str) -> list[str]:
        lines = (ROOT / path).read_text().splitlines()
        start = next(i for i, line in enumerate(lines) if line.startswith("| EE mechanic"))
        rows = []
        for line in lines[start:]:
            if not line.startswith("|"):
                break
            rows.append(line)
        return rows

    assert table("docs/provenance.md") == table("docs/spec/13-licensing-and-provenance.md")


# No prerendered clips: a checkout's own audio/prerendered/ would make finish() slow.
NO_CLIPS = ROOT / "tools/tests/no_such_dir"


def make_web(folder, wasm=b"\0asm" * 100):
    (folder / "index.js").write_text("x" + web_patch.UNGUARDED)
    (folder / "index.wasm").write_bytes(wasm)
    (folder / "index.pck").write_bytes(b"GDPC" * 10)
    (folder / "index.html").write_text(
        'const GODOT_CONFIG = {"executable":"index","fileSizes":{"index.pck":40,"index.wasm":400}};'
    )


# FT: FT-NET-030
def test_web_patch_gzip_is_reproducible_and_names_carry_a_content_hash(tmp_path):
    make_web(tmp_path)
    web_patch.finish(tmp_path, NO_CLIPS)
    found = [p.name for p in tmp_path.glob("index.*.wasm.gz")]
    tag = re.fullmatch(r"index\.([0-9a-f]{10})\.wasm\.gz", found[0]) if found else None
    assert tag, sorted(p.name for p in tmp_path.iterdir())
    name = f"index.{tag.group(1)}.wasm"
    first = (tmp_path / f"{name}.gz").read_bytes()
    assert (tmp_path / f"index.{tag.group(1)}.pck").is_file()
    assert not (tmp_path / "index.wasm").exists()
    html = (tmp_path / "index.html").read_text()
    assert f'"executable":"index.{tag.group(1)}"' in html
    assert f'"index.{tag.group(1)}.pck":40' in html and f'"{name}":400' in html
    other = tmp_path.parent / (tmp_path.name + "-2")
    other.mkdir()
    make_web(other)
    web_patch.finish(other, NO_CLIPS)
    assert (other / f"{name}.gz").read_bytes() == first
    changed = tmp_path.parent / (tmp_path.name + "-3")
    changed.mkdir()
    make_web(changed, wasm=b"\0asm" * 101)
    web_patch.finish(changed, NO_CLIPS)
    assert not (changed / name).exists()
    assert (tmp_path / "keepawake.webm").is_file() and (tmp_path / "keepawake.mp4").is_file()
    assert io.BytesIO(first).read(2) == b"\x1f\x8b"


def test_every_pack_includes_the_build_info_clips_and_data_files():
    import inspect_packages

    cfg = (ROOT / "export_presets.cfg").read_text()
    for name in ("Linux", "Windows", "macOS", "Web"):
        block = cfg[cfg.index(f'name="{name}"') :]
        include = block[block.index("include_filter=") :].split("\n")[0]
        for pattern in ("build_info.json", *inspect_packages.DATA_GLOBS):
            assert pattern in include, f"{name} preset doesn't include {pattern}"
        exclude = block[block.index("exclude_filter=") :].split("\n")[0]
        # The web pack carries no clips: voice-<lang>.pack files sit next to it (D294).
        for folder in (inspect_packages.PRERENDER_DIR, inspect_packages.PRERENDER_HOST_DIR):
            if name == "Web":
                assert f"{folder}/*" in exclude and f"{folder}/*" not in include
            else:
                assert f"{folder}/*" in include


# FT: FT-LIC-005
def test_voice_config_patch_drops_only_multi_codepoint_phonemes():
    config = {"phoneme_id_map": {"a": [1], "aɪ": [2], "ˈ": [3], "oʊ": [4]}, "audio": {"sample_rate": 22050}}
    data, dropped = package.patch_voice_config(json.dumps(config).encode())
    assert dropped == ["aɪ", "oʊ"]
    patched = json.loads(data)
    assert patched["phoneme_id_map"] == {"a": [1], "ˈ": [3]}
    assert patched["audio"] == config["audio"]
    same = json.dumps({"phoneme_id_map": {"a": [1]}}).encode()
    assert package.patch_voice_config(same) == (same, [])
    md = package.voices_md({"it_IT-serena-medium": ["aɪ"]})
    assert "Modified" in md and "aɪ" in md


def test_pack_reader_rejects_truncated_and_lying_packs():
    data = make_pack({"build_info.json": b"{}"})
    for bad in (data[:20], data[:-10], data[:4] + b"\xff" * 4 + data[8:]):
        with pytest.raises(ValueError):
            pck.open_pack(bad)
    lying = b"x" * 10 + struct.pack("<Q", 10**9) + b"GDPC"
    with pytest.raises(ValueError):
        pck.open_pack(lying)


# FT: FT-LIC-008
def test_assets_must_match_the_expected_set_and_sums(tmp_path):
    import inspect_packages

    insp = inspect_packages.Inspector("v1.0.0", "c0ffee")
    names = package.asset_names("v1.0.0")
    expected = [names[k] for k in ("linux", "windows", "macos", "source")]
    for n in expected:
        (tmp_path / n).write_bytes(n.encode())
    (tmp_path / "SHA256SUMS").write_text("")
    insp.assets(tmp_path)
    text = "\n".join(insp.errors)
    assert "SHA256SUMS lacks" in text and "missing or not the pinned archive" in text

    insp = inspect_packages.Inspector("v1.0.0", "c0ffee")
    (tmp_path / "stray.tar.gz").write_bytes(b"x")
    (tmp_path / "SHA256SUMS").write_text("not a line\n")
    insp.assets(tmp_path)
    text = "\n".join(insp.errors)
    assert "stray.tar.gz" in text and "malformed" in text


# FT: FT-LIC-005
def test_modified_voice_needs_a_provenance_entry_citing_d144():
    with pytest.raises(SystemExit):
        package.voices_md({"en_GB-cori-medium": ["aɪ"]})


# FT: FT-ARC-022
def test_release_lists_agree_with_the_game_voice_table():
    """tools/tts/voices.json's release and prerender lists must match
    content/voices.json's languages that aren't dev_only (D141, D153)."""
    table = json.loads((ROOT / "content/voices.json").read_text())["languages"]
    shipped = {lang: roles for lang, roles in table.items() if not roles.get("dev_only")}
    pins = json.loads((ROOT / "tools/tts/voices.json").read_text())

    def voices(kind: str) -> set[str]:
        return {r[kind] for roles in shipped.values() for k, r in roles.items() if isinstance(r, dict)}

    assert set(pins["release"]) == voices("runtime")
    assert set(pins["prerender"]) == voices("prerender")
    assert package.release_languages() == sorted(shipped)


def make_clips(folder: Path, lang: str, clips: dict[str, bytes]) -> Path:
    d = folder / lang
    d.mkdir(parents=True)
    for name, data in clips.items():
        (d / name).write_bytes(data)
    (d / "index.json").write_text(json.dumps({"language": lang, "clips": list(clips)}))
    return d


# FT: FT-AUD-002, FT-AUD-013
def test_voice_pack_round_trip_and_malformed_packs(tmp_path):
    d = make_clips(tmp_path, "it", {"npc.hail.ogg": b"OggS-1", "computer.jump_ready.ogg": b"OggS-22"})
    data = voice_pack.build("it", d)
    lang, clips = voice_pack.read(data)
    assert lang == "it"
    assert clips == {"npc.hail": b"OggS-1", "computer.jump_ready": b"OggS-22"}
    assert data[:4] == b"FTVP" and struct.unpack_from("<I", data, 4)[0] == 1
    for bad in (b"", data[:8], b"XTVP" + data[4:], data[:-1]):
        with pytest.raises(ValueError):
            voice_pack.read(bad)


# FT: FT-NET-030, FT-AUD-002
def test_web_patch_writes_voice_packs_and_brotli_copies(tmp_path):
    import brotli

    web = tmp_path / "web"
    web.mkdir()
    make_web(web)
    pre = tmp_path / "prerendered"
    make_clips(pre, "en", {"npc.hail.ogg": b"OggS-en"})
    make_clips(pre, "it", {"npc.hail.ogg": b"OggS-it"})
    (pre / "scratch").mkdir()  # no index.json: not a language
    web_patch.finish(web, pre)
    assert voice_pack.read((web / "voice-en.pack").read_bytes()) == ("en", {"npc.hail": b"OggS-en"})
    assert voice_pack.read((web / "voice-it.pack").read_bytes())[0] == "it"
    assert not (web / "voice-scratch.pack").exists()
    assert (web / "voice-en.pack.gz").is_file() and (web / "voice-en.pack.br").is_file()
    for f in web.iterdir():
        if f.suffix in web_patch.GZIP_SUFFIXES:
            assert brotli.decompress(Path(f"{f}.br").read_bytes()) == f.read_bytes(), f.name
    nothing = tmp_path / "web-2"
    nothing.mkdir()
    make_web(nothing)
    web_patch.finish(nothing, tmp_path / "none")
    assert not list(nothing.glob("voice-*"))


# FT: FT-ARC-022
def test_inspection_checks_each_languages_voice_pack(tmp_path):
    import inspect_packages

    class Folder:
        def __init__(self, files):
            self.files = files

        def has(self, rel):
            return rel in self.files

        def read(self, rel):
            return self.files[rel]

    en = voice_pack.build("en", make_clips(tmp_path, "en", {"npc.hail.ogg": b"OggS-a"}))
    it = voice_pack.build("it", make_clips(tmp_path, "it", {"npc.hail.ogg": b"OggS-b"}))
    insp = inspect_packages.Inspector("v0.0.0", "abc")
    insp.languages = ["en", "it"]
    insp.client_clips = {"en": {"npc.hail.ogg"}, "it": {"npc.hail.ogg", "npc.bye.ogg"}}
    insp.voice_packs(Folder({"web/voice-en.pack": en, "web/voice-it.pack": it}), "web", "pkg")
    assert insp.errors == ["pkg: web/voice-it.pack lacks ['npc.bye']"]
    insp.errors = []
    insp.voice_packs(Folder({"web/voice-en.pack": it}), "web", "pkg")
    assert insp.errors == ["pkg: web/voice-en.pack is for it", "pkg: no web/voice-it.pack"]
