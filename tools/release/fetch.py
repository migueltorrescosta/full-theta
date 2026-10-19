"""Fetch the pinned release inputs listed in tools/release/piper.json into a cache.

    uv run --project tools python tools/release/fetch.py [binaries|licences|sources]...

Each file is checked against its SHA-256 (FT-ARC-022, FT-LIC-008). The cache is
$FT_RELEASE_CACHE or ~/.cache/full-theta/release/. Prints the cached paths.
"""

import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tts"))
from fetch_voices import download, sha256  # noqa: E402, F401 (sha256 re-exported)

MANIFEST = Path(__file__).with_name("piper.json")
GROUPS = ("binaries", "licences", "sources")


def manifest() -> dict:
    return json.loads(MANIFEST.read_text(encoding="utf-8"))


def cache_dir() -> Path:
    default = Path.home() / ".cache" / "full-theta" / "release"
    return Path(os.environ.get("FT_RELEASE_CACHE", default))


def fetch_one(group: str, key: str) -> Path:
    """Download one pinned file (if missing or stale) and return its path."""
    meta = manifest()[group][key]
    name = key if group != "binaries" else Path(meta["url"]).name
    return download(meta["url"], cache_dir() / group / name, meta["sha256"])


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
