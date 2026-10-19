# tools/

Scripts for the engine fetch, gates, lints, traceability and provenance checks.

## L5 screenshots

`tools/gate.sh l5` renders the shots in `tests/visual/shots.json` under Xvfb with llvmpipe (`tools/l5.py`, `tools/l5_capture.gd`) and diffs them against `tests/visual/baselines/`; it needs the `xvfb` package and runs on fugaku only (FT-TST-003). A shot names a scene and, optionally, properties to set on its root before it enters the tree. `tools/gate.sh l5 --update-baselines` regenerates every baseline and `baselines/env.json`. `tools/l5.py --capture-only DIR [--shots FILE]` renders without comparing. The tolerance and the "baseline environment changed" check are described in the docstring of `tools/l5.py`. Any PR may regenerate baselines: say why in the PR body and compare the old and new images by eye (failing shots leave `build/l5/<name>.diff.png`).

## L4 multi-process network test

`tools/gate.sh l4` runs `tools/l4/run.sh`: a server and three headless client processes pinned to 2 cores (`taskset -c 0,1`), driven by intent files, with kills and relaunches (FT-TST-011, FT-TST-014). `tools/l4/repeat.sh N` runs it N times and writes `build/l4/repeat-summary.txt`. The scenarios, the intent format and the logs are in `tools/l4/README.md`.

## Voice latency

`tools/voice_latency/` measures FT-AUD-015 (free-text event to audible, p95 under 1 s) and the Start time of FT-AUD-018 on the promoted voice code, by the S7b method (`docs/spikes/S7b.md`). It is a measuring tool, not a gate tier.

```bash
uv run --project tools/tts python tools/tts/fetch_voices.py
uv run --project tools/tts python tools/tts/prerender.py        # writes audio/prerendered_host/
tools/voice_latency/run.sh /tmp/vl/dev                           # piper_stream.py
FT_PIPER_BIN=/path/to/piper/piper tools/voice_latency/run.sh /tmp/vl/bin   # release binary
```

`run.sh OUT_DIR [--port 47850] [-- server flags]` pins everything to `VL_CPUS` (default `6,7`). `vl_server.gd` composes the real `NetServer` and `VoiceService` through `ServerMain` and `VoiceSetup` (Piper runs `nice 5` with one ONNX thread there), steps the S7b sim load once per server tick, and waits for the headless clients `c0` (target) and `c1` (bystander, `vl_client.gd`). Then, per language, it calls `start_session()` with the S7b closed set (`spikes/s7b/closed_set.json`), sends that language's free-text lines from `spikes/s7b/lines.json` through `say_free()`, one a second, then 5 stitched lines through `say()` with closed-set names and numbers, every line to `c0`'s session only. pt_PT's dev-only voice is allowed. Audible is the moment `c0` wraps a line's first part in an `AudioStreamWAV`; latency runs from the server's unix µs stamp just before the call. `aggregate.py` writes `summary.md`: p50/p95/max per kind and language, playback gaps, Start per language, voice bytes per client, the sim load step and frame interval, and the host load average before and after.

Server flags: `--langs en,it,pt --line-every 1.0 --lines-at 2.0 --tail 3.0 --sim-ships 100 --sim-proj 500 --max-lang-s 300`. Environment: `VL_NICE` (renice the run, for example `-10`, with sudo, to rise above foreign load on a shared host), `VL_LABEL`, and `FT_PIPER_BIN`, `FT_PIPER_DATA`, `FT_PIPER_CACHE`, `FT_PIPER_PYTHON` as read by `app/voice_setup.gd`. Record the host load with each result: on a loaded host the numbers measure the host as much as the code.
