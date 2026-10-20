"""Release-build prerender hook (packaging strand, tools/release/prerender.sh).

    uv run --project tools/tts python tools/tts/prerender_release.py --out audio/prerendered LANG...

Runs prerender.py for the release languages: the client pack (Ogg lines) goes to
OUT/<lang>/ and the host pack (PCM blobs) to OUT/../prerendered_host/<lang>/, each
with index.json {"language", "clips": [file, ...]} (D154). Generated audio is never
committed (FT-AUD-002).
"""

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import prerender  # noqa: E402


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("langs", nargs="+", metavar="LANG")
    parser.add_argument("--out", type=Path, default=prerender.DEFAULT_OUT)
    parser.add_argument("--jobs", type=int, default=2)
    args = parser.parse_args(argv)
    return prerender.main([*args.langs, "--out", str(args.out), "--jobs", str(args.jobs)])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
