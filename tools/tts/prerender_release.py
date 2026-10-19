"""Release-build prerender hook (packaging strand, tools/release/prerender.sh).

    uv run --project tools/tts python tools/tts/prerender_release.py --out audio/prerendered LANG...

Runs prerender.py for the release languages and writes, per language, the index the
package inspection checks: OUT/<lang>/index.json {"language": lang, "clips": [file, ...]},
listing every file the client and host read (ClipLibrary: <role>.pcm and <role>.json).
Clips stay 16-bit PCM rather than Ogg: the host stitches slotted lines from the same
fragments sample by sample (D152). Generated audio is never committed (FT-AUD-002).
"""

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import prerender  # noqa: E402


def write_indexes(out: Path, langs: list[str]) -> None:
    for lang in langs:
        folder = out / lang
        clips = sorted(p.name for p in folder.iterdir() if p.is_file() and p.name != "index.json")
        index = {"language": lang, "clips": clips}
        (folder / "index.json").write_text(json.dumps(index, indent=1) + "\n", encoding="utf-8")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("langs", nargs="+", metavar="LANG")
    parser.add_argument("--out", type=Path, default=prerender.DEFAULT_OUT)
    parser.add_argument("--jobs", type=int, default=2)
    args = parser.parse_args(argv)
    if unknown := [lang for lang in args.langs if lang not in prerender.LANGS]:
        parser.error(f"unknown language {', '.join(unknown)}")
    out = args.out.resolve()
    prerender.prerender(prerender.ROOT, out, args.langs, jobs=args.jobs, threads=1)
    write_indexes(out, args.langs)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
