"""Persistent Piper synthesis process: one voice loaded once, requests on stdin, PCM on stdout.

    uv run --project tools/tts python tools/tts/piper_stream.py VOICE [--threads 1]

The host server starts one of these per voice and keeps it for the session
(FT-ARC-019, FT-AUD-019; spike S7b). VOICE is a voices.json name (fetched and
checked by fetch_voices.py) or a path to an .onnx model.

stdin: one JSON object per line, {"id": int, "text": str} plus optional
"length_scale", "noise_scale", "noise_w_scale" and "speaker".

stdout: binary frames, little endian: u32 header length, a UTF-8 JSON header,
u32 PCM length, then 16-bit mono PCM at the voice's rate. Each request gets one
frame per sentence, flushed as soon as the sentence is synthesised, with
{"id", "sentence", "last", "rate", "synth_us"}; the frame with "last": true
ends the clip (it may carry no PCM). On start the process writes one frame
{"id": 0, "ready": true, "rate", "load_us"} with no PCM. A failed request gets
{"id", "last": true, "error"}. EOF on stdin ends the process.
"""

import argparse
import json
import struct
import sys
import time
from pathlib import Path

import onnxruntime
from piper.config import PiperConfig, SynthesisConfig
from piper.voice import PiperVoice

sys.path.insert(0, str(Path(__file__).parent))
from fetch_voices import model_path  # noqa: E402


def load(voice: str, threads: int) -> PiperVoice:
    """Loads a voice with an explicit thread count: onnxruntime's default
    starts one thread per visible CPU, which oversubscribes a shared host."""
    onnx = Path(voice) if voice.endswith(".onnx") else model_path(voice)
    config = json.loads(Path(f"{onnx}.json").read_text(encoding="utf-8"))
    options = onnxruntime.SessionOptions()
    options.intra_op_num_threads = threads
    options.inter_op_num_threads = 1
    session = onnxruntime.InferenceSession(
        str(onnx), sess_options=options, providers=["CPUExecutionProvider"]
    )
    return PiperVoice(config=PiperConfig.from_dict(config), session=session)


def write_frame(out, header: dict, pcm: bytes = b"") -> None:
    head = json.dumps(header, separators=(",", ":")).encode("utf-8")
    out.write(struct.pack("<I", len(head)) + head + struct.pack("<I", len(pcm)) + pcm)
    out.flush()


def serve(voice: PiperVoice, inp, out) -> None:
    rate = voice.config.sample_rate
    for line in inp:
        line = line.strip()
        if not line:
            continue
        req_id = 0
        try:
            req = json.loads(line)
            req_id = int(req.get("id", 0))
            syn = SynthesisConfig(
                speaker_id=req.get("speaker"),
                length_scale=req.get("length_scale"),
                noise_scale=req.get("noise_scale"),
                noise_w_scale=req.get("noise_w_scale"),
            )
            start = time.perf_counter_ns()
            sentence = 0
            for chunk in voice.synthesize(str(req.get("text", "")), syn):
                elapsed = (time.perf_counter_ns() - start) // 1000
                head = {"id": req_id, "sentence": sentence, "last": False, "rate": rate}
                head["synth_us"] = elapsed
                write_frame(out, head, chunk.audio_int16_bytes)
                sentence += 1
            elapsed = (time.perf_counter_ns() - start) // 1000
            write_frame(
                out,
                {"id": req_id, "sentence": sentence, "last": True, "rate": rate, "synth_us": elapsed},
            )
        except Exception as e:  # noqa: BLE001 - one bad request must not end the process
            write_frame(out, {"id": req_id, "last": True, "error": repr(e)})


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("voice")
    parser.add_argument("--threads", type=int, default=1)
    args = parser.parse_args(argv)
    start = time.perf_counter_ns()
    voice = load(args.voice, args.threads)
    # Warm-up: the first inference allocates the session's buffers.
    for _ in voice.synthesize("Ready."):
        pass
    out = sys.stdout.buffer
    load_us = (time.perf_counter_ns() - start) // 1000
    write_frame(out, {"id": 0, "ready": True, "rate": voice.config.sample_rate, "load_us": load_us})
    serve(voice, sys.stdin, out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
