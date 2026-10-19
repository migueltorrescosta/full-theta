"""Read the file table of a Godot 4.7 pack (format 4), standalone or embedded in
an executable, so the release inspection can check what an export carries
(FT-ARC-022): its build_info.json commit and its prerendered clips.
"""

import struct
from pathlib import Path

MAGIC = b"GDPC"
PACK_FORMAT = 4
FLAG_ENCRYPTED = 1
FLAG_REL_FILEBASE = 2


class Pack:
    def __init__(self, data: bytes, start: int = 0):
        self.data = data
        self.start = start
        magic, version, _maj, _min, _patch, flags, base, dir_offset = struct.unpack_from(
            "<4sIIIIIQQ", data, start
        )
        if magic != MAGIC or version != PACK_FORMAT:
            raise ValueError(f"pck: not a format {PACK_FORMAT} pack (magic {magic!r}, v{version})")
        if flags & FLAG_ENCRYPTED:
            raise ValueError("pck: encrypted directory")
        if flags & FLAG_REL_FILEBASE:
            base += start
            dir_offset += start
        self.base = base
        self.files: dict[str, tuple[int, int]] = {}
        (count,) = struct.unpack_from("<I", data, dir_offset)
        pos = dir_offset + 4
        for _ in range(count):
            (length,) = struct.unpack_from("<I", data, pos)
            pos += 4
            path = data[pos : pos + length].rstrip(b"\0").decode("utf-8")
            pos += length
            offset, size = struct.unpack_from("<QQ", data, pos)
            pos += 16 + 16 + 4  # offset, size, md5, flags
            self.files[path.removeprefix("res://")] = (offset, size)

    def read(self, path: str) -> bytes:
        offset, size = self.files[path]
        return self.data[self.base + offset : self.base + offset + size]


def open_pack(data: bytes) -> Pack:
    """A standalone pck, or one embedded at the end of an executable (Godot
    appends the pack, its u64 size and the magic)."""
    if data[:4] == MAGIC:
        return Pack(data)
    if data[-4:] != MAGIC:
        raise ValueError("pck: no pack in this file")
    (size,) = struct.unpack_from("<Q", data, len(data) - 12)
    return Pack(data, len(data) - 12 - size)


def load(path: Path) -> Pack:
    return open_pack(path.read_bytes())
