"""Fetch the pinned Piper voices listed in voices.json into a cache outside the repo.

    uv run --project tools/tts python tools/tts/fetch_voices.py [VOICE...]

Files come from the rhasspy/piper-voices revision named in voices.json and are
checked against their SHA-256. The cache is $FT_PIPER_CACHE or
~/.cache/full-theta/piper/<voice>/. Voice models and generated audio are never
committed (FT-AUD-002); each voice's licence is audited in docs/spikes/S7.md
(FT-LIC-007). voices.json's "release" list names the voices release packages
ship (D141, tools/release/package.py).
"""

import hashlib
import json
import os
import sys
import urllib.parse
import urllib.request
from pathlib import Path

MANIFEST = Path(__file__).with_name("voices.json")


def cache_dir() -> Path:
    default = Path.home() / ".cache" / "full-theta" / "piper"
    return Path(os.environ.get("FT_PIPER_CACHE", default))


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def download(url: str, local: Path, expected: str) -> Path:
    """Download url to local unless it is already there with the expected
    SHA-256; fail on a mismatch. Shared with tools/release/fetch.py."""
    if local.exists() and sha256(local) == expected:
        return local
    local.parent.mkdir(parents=True, exist_ok=True)
    tmp = local.with_name(local.name + ".part")
    print(f"fetch: {url}", file=sys.stderr)
    urllib.request.urlretrieve(url, tmp)
    got = sha256(tmp)
    if got != expected:
        tmp.unlink()
        raise SystemExit(f"fetch: {url}: sha256 {got} != {expected}")
    tmp.replace(local)
    return local


def fetch(voice: str) -> Path:
    """Download one voice (if missing or stale) and return its directory."""
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if voice not in manifest["voices"]:
        raise SystemExit(f"fetch: unknown voice {voice}")
    dest = cache_dir() / voice
    for remote, meta in manifest["voices"][voice].items():
        url = "https://huggingface.co/{}/resolve/{}/{}".format(
            manifest["repo"], manifest["revision"], urllib.parse.quote(remote)
        )
        download(url, dest / Path(remote).name, meta["sha256"])
    return dest


def model_path(voice: str) -> Path:
    return fetch(voice) / f"{voice}.onnx"


def main(argv: list[str]) -> int:
    voices = argv or list(json.loads(MANIFEST.read_text(encoding="utf-8"))["voices"])
    for v in voices:
        print(model_path(v))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
