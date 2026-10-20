# tools/

Scripts for the engine fetch, gates, lints, traceability and provenance checks. The Python tools (`tools/pyproject.toml`, `tools/tts/pyproject.toml`) need Python 3.12 or later (`requires-python`, set by numpy 2.5).

## L5 screenshots

`tools/gate.sh l5` renders the shots in `tests/visual/shots.json` under Xvfb with llvmpipe (`tools/l5.py`, `tools/l5_capture.gd`) and diffs them against `tests/visual/baselines/`; it needs the `xvfb` package and runs on fugaku only (FT-TST-003). A shot names a scene and, optionally, properties to set on its root before it enters the tree. `tools/gate.sh l5 --update-baselines` regenerates every baseline and `baselines/env.json`. `tools/l5.py --capture-only DIR [--shots FILE]` renders without comparing. The tolerance and the "baseline environment changed" check are described in the docstring of `tools/l5.py`. Any PR may regenerate baselines: say why in the PR body and compare the old and new images by eye (failing shots leave `build/l5/<name>.diff.png`).

## L4 multi-process network test

`tools/gate.sh l4` runs `tools/l4/run.sh`: a server and three headless client processes pinned to 2 cores (`taskset -c 0,1`), driven by intent files, with kills and relaunches (FT-TST-011, FT-TST-014). `tools/l4/repeat.sh N` runs it N times and writes `build/l4/repeat-summary.txt`. The scenarios, the intent format and the logs are in `tools/l4/README.md`.

## HTTP budget

`tools/static_server_profile.gd` times the search for a request head's end over a whole 8 KiB headerless request, the most one `StaticServer` poll searches, against the 400 µs per-frame budget (FT-NET-039, D108). It is wall-clock, so a manual check on an idle host, not a gate test: the L3 test counts the bytes searched instead. Run `taskset -c 0,1 godot --headless --path . -s res://tools/static_server_profile.gd` and record the load average with the result.

## Voice latency

`tools/voice_latency/` measures FT-AUD-015 (free-text event to audible, p95 under 1 s) and the Start time of FT-AUD-018 on the promoted voice code, by the S7b method (`docs/spikes/S7b.md`). It is a measuring tool, not a gate tier.

```bash
uv run --project tools/tts python tools/tts/fetch_voices.py
uv run --project tools/tts python tools/tts/prerender.py --dev  # writes audio/prerendered_host/ (pt_PT's voice is dev_only)
tools/voice_latency/run.sh /tmp/vl/dev                           # piper_stream.py
FT_PIPER_BIN=/path/to/piper/piper tools/voice_latency/run.sh /tmp/vl/bin   # release binary
```

`run.sh OUT_DIR [--port 47850] [-- server flags]` pins everything to `VL_CPUS` (default `6,7`). `vl_server.gd` composes the real `NetServer` and `VoiceService` through `ServerMain` and `VoiceSetup` (Piper runs `nice 5` with one ONNX thread there), steps the S7b sim load once per server tick, and waits for the headless clients `c0` (target) and `c1` (bystander, `vl_client.gd`). Then, per language, it calls `start_session()` with the S7b closed set (`spikes/s7b/closed_set.json`), sends that language's free-text lines from `spikes/s7b/lines.json` through `say_free()`, one a second, then 5 stitched lines through `say()` with closed-set names and numbers, every line to `c0`'s session only. pt_PT's dev-only voice is allowed. Audible is the moment `c0` wraps a line's first part in an `AudioStreamWAV`; latency runs from the server's unix µs stamp just before the call. `aggregate.py` writes `summary.md`: p50/p95/max per kind and language, playback gaps, Start per language, voice bytes per client, the sim load step and frame interval, and the host load average before and after.

Server flags: `--langs en,it,pt --line-every 1.0 --lines-at 2.0 --tail 3.0 --sim-ships 100 --sim-proj 500 --max-lang-s 300`. Environment: `VL_NICE` (renice the run, for example `-10`, with sudo, to rise above foreign load on a shared host), `VL_LABEL`, and `FT_PIPER_BIN`, `FT_PIPER_DATA`, `FT_PIPER_CACHE`, `FT_PIPER_PYTHON` as read by `app/voice_setup.gd`. Record the host load with each result: on a loaded host the numbers measure the host as much as the code.

The rhasspy/piper 2023.11.14-2 binary can't load `it_IT-serena-medium` (a piper 1.5 voice): it aborts with "Phonemes must be one codepoint (phoneme id map)" on the diphthong keys `aɪ aʊ ɔɪ eɪ oʊ`, so Italian is subtitles only with an unpatched voice. Release packages patch each bundled voice's `.onnx.json` at bundle time by dropping every multi-codepoint `phoneme_id_map` key (D144). To measure the binary in development, point `FT_PIPER_CACHE` at a copy of the voice cache patched by the same rule (synthesis then works; the sound is unreviewed).

## Release packaging and L6

`tools/release/build.sh VERSION OUT_DIR` builds, packages and inspects the Linux, Windows and macOS release packages (`fetch.py`, `prerender.sh`, `web_patch.py`, `package.py`, `inspect_packages.py`, `notes.py`; pins in `piper.json`). `.github/workflows/release.yml` runs it on version tags. `tools/gate.sh l6` runs it on the working tree and then runs the Linux and Windows packages (`tools/l6/run.sh`). See `docs/release.md`.
