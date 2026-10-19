"""Check every file under assets/ and addons/ against content/provenance.json.

Fails on a file no manifest entry covers (entries match by path prefix, so
"addons/gdUnit4/" covers the whole addon), on an entry missing name, source,
licence or attribution (FT-LIC-005), and on art or sound that isn't CC0
(FT-LIC-006).

Voices (FT-AUD-014, D105): every voice content/voices.json names needs a "voice"
entry; a language that ships needs status "accept" for each of its voices, and a
dev_only language (pt_PT until #16) may use "dev-only" ones. No speech-recognition
package may appear among the dependencies (FT-GEN-008), and no audio file may be
tracked outside assets/: generated voice audio is never committed (FT-AUD-002).
"""

import json
import re
import subprocess
import sys
from pathlib import Path

REQUIRED = ("name", "source", "licence", "attribution")
CC0_KINDS = ("art", "sound")
OWN = {"addons/VERSIONS.md"}  # our own pin record, not third-party
VOICE_STATUSES = ("accept", "dev-only")
# Speech-recognition engines and bindings (FT-GEN-008), matched between non-alphanumerics.
STT = re.compile(
    r"(?<![a-z0-9])(vosk|(?:openai-|faster-)?whisper(?:\.cpp)?|speech_?recognition|pocketsphinx|deepspeech"
    r"|coqui-stt|kaldi|wav2vec2?|silero|picovoice|porcupine|nemo[-_]asr)(?![a-z0-9])"
)
MANIFESTS = (
    "tools/pyproject.toml",
    "tools/uv.lock",
    "tools/tts/pyproject.toml",
    "tools/tts/uv.lock",
    "package.json",
    "content/provenance.json",
)
AUDIO = (".wav", ".pcm", ".ogg", ".mp3", ".flac", ".opus")


def run(root: Path) -> list[str]:
    entries = json.loads((root / "content/provenance.json").read_text())["entries"]
    errors = []
    for e in entries:
        missing = [k for k in REQUIRED if not e.get(k)]
        if missing:
            errors.append(f"{e.get('name', e)}: missing {', '.join(missing)}")
        if e.get("kind") in CC0_KINDS and e.get("licence") != "CC0-1.0":
            errors.append(f"{e.get('name')}: {e['kind']} must be CC0-1.0, not {e.get('licence')}")
    prefixes = [e["path"] for e in entries if e.get("path")]
    for base in ("assets", "addons"):
        for f in sorted((root / base).rglob("*")):
            rel = f.relative_to(root).as_posix()
            if f.is_file() and rel not in OWN and not any(rel.startswith(p) for p in prefixes):
                errors.append(f"{rel}: not listed in content/provenance.json")
    errors += check_voices(root, entries)
    errors += check_no_speech_recognition(root)
    errors += check_no_tracked_audio(root)
    return errors


def check_voices(root: Path, entries: list[dict]) -> list[str]:
    path = root / "content/voices.json"
    if not path.exists():
        return []
    errors, by_voice = [], {}
    for e in entries:
        if e.get("kind") == "voice" and e.get("voice"):
            if e["voice"] in by_voice:
                errors.append(f"{e['voice']}: listed twice in content/provenance.json")
            by_voice.setdefault(e["voice"], e)
    for e in by_voice.values():
        if e.get("status") not in VOICE_STATUSES:
            errors.append(f"{e['voice']}: voice status must be one of {VOICE_STATUSES}")
    for lang, spec in json.loads(path.read_text(encoding="utf-8"))["languages"].items():
        for role in ("computer", "npc"):
            for use in ("runtime", "prerender"):
                name = spec[role][use]
                entry = by_voice.get(name)
                if entry is None:
                    errors.append(f"{name}: voice ({lang} {role}) not listed in content/provenance.json")
                elif entry.get("status") != "accept" and not spec.get("dev_only"):
                    errors.append(f"{name}: {lang} ships, so its voice must have status accept")
    return sorted(set(errors))


def check_no_speech_recognition(root: Path) -> list[str]:
    errors = []
    for rel in MANIFESTS:
        f = root / rel
        if f.exists():
            for m in STT.finditer(f.read_text(encoding="utf-8").lower()):
                errors.append(f"{rel}: speech recognition dependency '{m.group(1)}' (FT-GEN-008)")
    addons = root / "addons"
    for d in sorted(addons.iterdir()) if addons.is_dir() else []:
        if STT.search(d.name.lower()):
            errors.append(f"addons/{d.name}: speech recognition addon (FT-GEN-008)")
    return sorted(set(errors))


def check_no_tracked_audio(root: Path) -> list[str]:
    if not (root / ".git").exists():
        return []
    files = subprocess.run(
        ["git", "-C", str(root), "ls-files"], capture_output=True, text=True, check=True
    ).stdout.splitlines()
    return [
        f"{f}: audio must not be committed outside assets/ (FT-AUD-002)"
        for f in files
        if f.lower().endswith(AUDIO) and not f.startswith("assets/")
    ]


def main() -> int:
    errors = run(Path(__file__).resolve().parent.parent)
    for e in errors:
        print(f"licences: {e}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
