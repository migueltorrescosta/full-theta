"""Fetch the pinned release inputs listed in tools/release/piper.json into a cache.

    uv run --project tools python tools/release/fetch.py [binaries|licences|sources]...

Each file is checked against its SHA-256 (FT-ARC-022, FT-LIC-008). The cache is
$FT_RELEASE_CACHE or ~/.cache/full-theta/release/. Prints the cached paths.
"""

import hashlib
import json
import os
import sys
import urllib.request
from pathlib import Path

MANIFEST = Path(__file__).with_name("piper.json")
GROUPS = ("binaries", "licences", "sources")


def manifest() -> dict:
    return json.loads(MANIFEST.read_text(encoding="utf-8"))


def cache_dir() -> Path:
    default = Path.home() / ".cache" / "full-theta" / "release"
    return Path(os.environ.get("FT_RELEASE_CACHE", default))


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def fetch_one(group: str, key: str) -> Path:
    """Download one pinned file (if missing or stale) and return its path."""
    meta = manifest()[group][key]
    name = key if group != "binaries" else Path(meta["url"]).name
    local = cache_dir() / group / name
    if local.exists() and sha256(local) == meta["sha256"]:
        return local
    local.parent.mkdir(parents=True, exist_ok=True)
    tmp = local.with_name(local.name + ".part")
    print(f"fetch: {meta['url']}", file=sys.stderr)
    urllib.request.urlretrieve(meta["url"], tmp)
    got = sha256(tmp)
    if got != meta["sha256"]:
        tmp.unlink()
        raise SystemExit(f"fetch: {meta['url']}: sha256 {got} != {meta['sha256']}")
    tmp.replace(local)
    return local


def fetch_group(group: str) -> dict[str, Path]:
    return {key: fetch_one(group, key) for key in manifest()[group]}


def main(argv: list[str]) -> int:
    for group in argv or GROUPS:
        if group not in GROUPS:
            raise SystemExit(f"fetch: unknown group {group} (use {', '.join(GROUPS)})")
        for path in fetch_group(group).values():
            print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
