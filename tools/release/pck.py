"""Read the file table of a Godot 4.7 pack (format 4), standalone or embedded in
an executable, so the release inspection can check what an export carries
(FT-ARC-022): its build_info.json commit and its prerendered clips. A
malformed pack raises ValueError.
"""

import struct
from pathlib import Path

MAGIC = b"GDPC"
PACK_FORMAT = 4
FLAG_ENCRYPTED = 1
FLAG_REL_FILEBASE = 2
HEADER = struct.Struct("<4sIIIIIQQ")


class Pack:
    def __init__(self, data: bytes, start: int = 0):
        try:
            self._parse(data, start)
        except (struct.error, UnicodeDecodeError, IndexError) as e:
            raise ValueError(f"pck: malformed pack: {e}") from e

    def _parse(self, data: bytes, start: int) -> None:
        self.data = data
        magic, version, _maj, _min, _patch, flags, base, dir_offset = HEADER.unpack_from(data, start)
        if magic != MAGIC or version != PACK_FORMAT:
            raise ValueError(f"pck: not a format {PACK_FORMAT} pack (magic {magic!r}, v{version})")
        if flags & FLAG_ENCRYPTED:
            raise ValueError("pck: encrypted directory")
        if flags & FLAG_REL_FILEBASE:
            base += start
            dir_offset += start
        if not start <= base <= len(data) or not start <= dir_offset < len(data):
            raise ValueError("pck: file base or directory outside the data")
        self.base = base
        self.files: dict[str, tuple[int, int]] = {}
        (count,) = struct.unpack_from("<I", data, dir_offset)
        pos = dir_offset + 4
        for _ in range(count):
            (length,) = struct.unpack_from("<I", data, pos)
            pos += 4
            if pos + length > len(data):
                raise ValueError("pck: file name outside the data")
            path = data[pos : pos + length].rstrip(b"\0").decode("utf-8")
            pos += length
            offset, size = struct.unpack_from("<QQ", data, pos)
            pos += 16 + 16 + 4  # offset, size, md5, flags
            if pos > len(data):
                raise ValueError("pck: directory entry outside the data")
            if base + offset + size > len(data):
                raise ValueError(f"pck: {path} extends past the data")
            self.files[path.removeprefix("res://")] = (offset, size)

    def read(self, path: str) -> bytes:
        offset, size = self.files[path]
        return self.data[self.base + offset : self.base + offset + size]


def open_pack(data: bytes) -> Pack:
    """A standalone pck, or one embedded at the end of an executable (Godot
    appends the pack, its u64 size and the magic)."""
    if data[:4] == MAGIC:
        return Pack(data)
    if len(data) < 12 or data[-4:] != MAGIC:
        raise ValueError("pck: no pack in this file")
    (size,) = struct.unpack_from("<Q", data, len(data) - 12)
    if size > len(data) - 12:
        raise ValueError("pck: embedded pack size exceeds the file")
    return Pack(data, len(data) - 12 - size)


def load(path: Path) -> Pack:
    return open_pack(path.read_bytes())
