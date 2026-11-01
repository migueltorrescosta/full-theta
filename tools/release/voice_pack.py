"""Per-language voice packs for the web export (D294, load fix 9).

The web pack (index.<hash>.pck) carries no prerendered clips; each language's
client clips (audio/prerendered/<lang>/, tools/release/prerender.sh) go into one
file next to the page, voice-<lang>.pack, which a browser station fetches once it
knows the session language (WebSession, audio/voice_pack.gd reads it). Format:

    "FTVP", u32 version (1), u32 header length N, N bytes of UTF-8 JSON
    {"language": "en", "clips": {"<line id>": [offset, size], ...}},
    then the Ogg files back to back; offsets count from the end of the header.

All integers little-endian. The clips are stored as they are; the pack still
compresses by a third (gzip or brotli, web_patch.py), as every clip repeats the
voice's Vorbis setup header.
"""

import json
import struct
from pathlib import Path

MAGIC = b"FTVP"
VERSION = 1
HEAD = struct.Struct("<4sII")


def name(lang: str) -> str:
    """The pack's file name in the web export."""
    return f"voice-{lang}.pack"


def build(lang: str, folder: Path) -> bytes:
    """The pack of the clips folder's index.json lists, in that order."""
    index = json.loads((folder / "index.json").read_text(encoding="utf-8"))
    clips: dict[str, list[int]] = {}
    data = bytearray()
    for file in index["clips"]:
        blob = (folder / file).read_bytes()
        clips[file.removesuffix(".ogg")] = [len(data), len(blob)]
        data += blob
    header = json.dumps({"language": lang, "clips": clips}, separators=(",", ":")).encode()
    return HEAD.pack(MAGIC, VERSION, len(header)) + header + bytes(data)


def read(data: bytes) -> tuple[str, dict[str, bytes]]:
    """(language, {line id: Ogg bytes}); raises ValueError on a malformed pack."""
    if len(data) < HEAD.size:
        raise ValueError("voice pack: too short")
    magic, version, size = HEAD.unpack_from(data)
    if magic != MAGIC or version != VERSION:
        raise ValueError(f"voice pack: not a version {VERSION} pack")
    start = HEAD.size + size
    try:
        header = json.loads(data[HEAD.size : start].decode("utf-8"))
        clips = {}
        for line, (offset, length) in header["clips"].items():
            if offset < 0 or length <= 0 or start + offset + length > len(data):
                raise ValueError(f"voice pack: {line} outside the data")
            clips[line] = data[start + offset : start + offset + length]
        return str(header["language"]), clips
    except (UnicodeDecodeError, json.JSONDecodeError, KeyError, TypeError) as e:
        raise ValueError(f"voice pack: bad header: {e}") from e


def write_all(web: Path, prerendered: Path) -> list[str]:
    """Writes a pack per language folder under `prerendered` that has an index.json
    into `web`; returns the file names (none when nothing was prerendered)."""
    written = []
    if not prerendered.is_dir():
        return written
    for folder in sorted(p for p in prerendered.iterdir() if (p / "index.json").is_file()):
        (web / name(folder.name)).write_bytes(build(folder.name, folder))
        written.append(name(folder.name))
    return written
