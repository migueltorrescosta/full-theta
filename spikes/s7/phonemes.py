"""Print the espeak phonemes Piper feeds a voice, for spot-checking pronunciation (S7)."""

import sys

from s7 import LINES, load

voice_name, lang = sys.argv[1], sys.argv[2]
espeak = sys.argv[3] if len(sys.argv) > 3 else None
voice = load(voice_name, 1, espeak)
for ln in LINES["lines"]:
    if ln["id"] in sys.argv[4:] or len(sys.argv) <= 4:
        print(ln["id"], " ".join("".join(s) for s in voice.phonemize(ln[lang])))
