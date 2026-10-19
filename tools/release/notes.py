"""Fill the release notes template (.github/release-notes.md) for a build.

    uv run --project tools python tools/release/notes.py --version V --commit SHA OUT_DIR

Prints the notes: version, commit, voices, the Piper and eSpeak NG versions, and
the assets in OUT_DIR/SHA256SUMS with their sizes (docs/release.md).
"""

import argparse
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import fetch  # noqa: E402
import package  # noqa: E402

TEMPLATE = HERE.parents[1] / ".github/release-notes.md"


def notes(version: str, commit: str, out: Path) -> str:
    m = fetch.manifest()
    assets = []
    for line in (out / "SHA256SUMS").read_text().splitlines():
        digest, name = line.split("  ", 1)
        mib = (out / name).stat().st_size / (1 << 20)
        assets.append(f"- `{name}` ({mib:.1f} MiB, SHA-256 `{digest}`)")
    values = {
        "VERSION": version,
        "COMMIT": commit,
        "ASSETS": "\n".join(assets),
        "PIPER": m["piper"]["version"],
        "ESPEAK_NG": m["espeak_ng"]["version"],
        "VOICES": ", ".join(package.release_voices()),
        "LANGUAGES": ", ".join(package.release_languages()),
    }
    text = TEMPLATE.read_text(encoding="utf-8")
    text = text[text.index("-->") + 4 :]  # drop the template's own comment
    for key, value in values.items():
        text = text.replace("{{" + key + "}}", value)
    return text


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--version", required=True)
    ap.add_argument("--commit", required=True)
    ap.add_argument("out", type=Path)
    a = ap.parse_args(argv)
    sys.stdout.write(notes(a.version, a.commit, a.out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
