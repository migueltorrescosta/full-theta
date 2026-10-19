"""A fake tools/tts/piper_stream.py for PiperStreamSynth tests (test_piper_process.gd).

Speaks the wrapper's frame protocol at 1000 Hz: each request gets one 10-sample part at
level 1000 per sentence ("." splits) and an empty last frame. Texts that start with a
keyword misbehave: "crash" exits mid-request, "exit_idle" answers then exits, "hang"
never answers, "spam" floods stderr before answering.
"""

import json
import os
import struct
import sys
import time

TONE = struct.pack("<h", 1000) * 10


def frame(head, pcm=b""):
    b = json.dumps(head).encode()
    out = sys.stdout.buffer
    out.write(struct.pack("<I", len(b)) + b + struct.pack("<I", len(pcm)) + pcm)
    out.flush()


frame({"id": 0, "ready": True, "rate": 1000})
for line in sys.stdin:
    req = json.loads(line)
    text, rid = req["text"], req["id"]
    if text.startswith("crash"):
        os._exit(3)
    if text.startswith("hang"):
        time.sleep(1000)
    if text.startswith("spam"):
        sys.stderr.write("x" * 300000)
        sys.stderr.flush()
    for _ in [s for s in text.split(".") if s.strip()]:
        frame({"id": rid, "last": False, "rate": 1000}, TONE)
    frame({"id": rid, "last": True, "rate": 1000})
    if text.startswith("exit_idle"):
        os._exit(0)
