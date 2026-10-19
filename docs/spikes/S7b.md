# S7b: runtime Piper on the host, clips streamed to one client

Run on fugaku (i7-11800H, 8 cores, 16 threads), 2026-10-19, Godot 4.7.2-stable, piper-tts 1.8.0 (onnxruntime 1.31.0), for T020, TECH-4 and TECH-5 (R8; FT-ARC-019, FT-AUD-015, FT-AUD-018, FT-AUD-019). Code in `spikes/s7b/` and `tools/tts/piper_stream.py`, unit tests in `tests/spikes/s7b/`.

## Result

| Criterion | Result |
|---|---|
| 1. Persistent Piper per voice, off the sim thread, one client | **Met.** The server starts one `piper_stream.py` process per voice (4 voices) and drives each from its own worker `Thread`. The sim thread only queues requests and collects finished parts, and each clip goes on the S4 voice lane of the target client. Over every run, the bystander client received 0 voice bytes |
| 2. Closed set at Start, numbers from prerendered fragments | **Met.** 46 names per language synthesise in 2.6–3.8 s per language on 2 CPUs, plus 45–75 ms to load the 1,008 prerendered fragments. A stitched line is audible 70 ms (p50) after its event, almost all of it transfer time |
| 3. Free text, 50 lines, p95 < 1 s; GPL note | **Met** with per-sentence streaming: p95 353 ms isolated and 422 ms under the S9 64-connection load (739 ms on a host loaded by a foreign job too). Whole-clip delivery gives p95 667 ms isolated but 0.87–1.2 s on a loaded host. GPL aggregation note added to `docs/provenance.md` |
| 4. Standalone Piper on Windows under Wine (TECH-4) | **Met.** `piper.exe` from rhasspy/piper `2023.11.14-2` synthesised a line under Wine 10.0, with no Python |
| TECH-5 combined run (S9 criterion) | **Not met** for bursts: 6 lines fired at once, with a rendering client and the S9 load, give p95 1.77 s on a moderately loaded host (2.59 s under heavier foreign load). The S7b sim tick stays at p99 3.7 ms; the S9 server tick p99 is 10.5 ms (details below) |

## Setup

The S7b server is the S4 server (snapshots, events, sessions, chunked two-lane queues) with three additions:

- **Sim load:** each 60 Hz tick also steps `S6WorldPacked` with 100 ships and 500 projectiles, so the thread that fires events is busy.
- **Piper:** one process per voice, started with `OS.execute_with_pipe` running the `tools/tts` venv's Python on `tools/tts/piper_stream.py`. The wrapper loads the voice once, sets `intra_op_num_threads` to 1, synthesises a warm-up line, then reads one JSON request per line on stdin. For each sentence it writes a length-prefixed frame (JSON header, 16-bit PCM) and flushes it. An empty frame marked `last` ends the clip. `S7bPiper` does the blocking writes and reads on a worker `Thread` and hands parts to the main loop through a mutex-guarded list. The main loop never touches the pipe.
- **Routing:** each part becomes one `var_to_bytes` message, pushed with `S4SendQueue.push(S4Chunker.STREAM_VOICE, …)` to the target client only. The voice lane sends one 16 KiB chunk per server frame behind the snapshots (S4).

Voices (provisional, from S7): en_GB-cori-medium (ship computer) and en_US-norman-medium (NPC) for English, it_IT-serena-medium for Italian, and pt_PT-tugão-medium for Portuguese (development only, an Unclear licence in S7).

Two headless clients join: `c0`, the target, and `c1`, a bystander. A headless client can't play audio, so **audible** means the moment `c0` has a whole part and wraps it in an `AudioStreamWAV`, ready for an `AudioStreamPlayer`. Latency runs from the server's sim event to that moment, both as unix µs on the same host. With per-sentence streaming the first sentence is audible while later ones synthesise. The **playback gap** column checks that every later part arrives before the earlier ones have finished playing.

The server, its Piper processes and both clients run pinned to CPUs 6 and 7 (`taskset -c 6,7`), as a stand-in for a 2-core laptop host. Piper runs 5 nice levels below the server (`--nice 5`, provisional), so the sim thread wins the CPU when both want it. fugaku was shared: an unrelated, unpinned 12-worker job and other spikes ran on all cores, including CPUs 14 and 15, the SMT siblings of 6 and 7. So each run records the host load average, and runs from `S7B_NICE=-10` on raise the run's own processes above unpinned foreign work on its CPUs. The siblings stay shared, so loaded runs are slower than a quiet host would be.

Lines: 50 free-text lines (`spikes/s7b/lines.json`), 10 per English voice and 15 each in it and pt. They run from 0.6 to 9.7 s of audio (mean 3.4 s) and 1 to 3 sentences, and include player-chosen names. One event fires every second. The 15 stitched lines (5 templates × 3 languages, `closed_set.json`) follow.

## Criterion 3: free-text event to audible

The S9 load is `spikes/s9/run.sh` in the `ft-s9` namespace: its server on CPUs 0 and 1, and 64 simulated stations on CPUs 8 and 9 (8 processes × 8 connections). The S7b run is its `--extra` command.

| Run | Host load (1 min) | Delivery | p50 ms | p95 ms | max ms | S7b sim tick mean / p99 / max ms |
|---|---|---|---|---|---|---|
| f-iso: isolated | 2.5 | per sentence | 223 | **353** | 512 | 2.5 / 4.8 / 7.2 |
| f-clip: isolated | 2.0 | whole clip | 316 | 667 | 892 | 3.1 / 4.9 / 9.4 |
| Q1: under S9 load | 3.9–7.7 | per sentence | 239 | **422** | 523 | 2.5 / 6.5 / 7.9 |
| L1: under S9 load, foreign job running | 10.7 | per sentence | 324 | **739** | 932 | 3.1 / 8.0 / 10.7 |

The S9 server's own tick frames in Q1 had a mean of 5.1 ms, a p99 of 17.1 ms and a max of 32.8 ms (L1: 5.4, 17.0, 20.7). S9's quiet-host figures are 3.3 ms mean and 6 ms p99. Snapshot age stayed at p99 22 ms.

Where the time goes (f-iso, first audible part, p50 / p95 ms): queueing for the voice 0 / 0, synthesis of the first sentence 168 / 265, collection by the main loop 5 / 8, then 10 / 17 to the client's first chunk and 49 / 84 to the whole part. Wrapping the part in an `AudioStreamWAV` takes under 1 ms. No line had a playback gap.

Earlier runs, with the foreign job running on all cores, show how much the result depends on host load:

| Runs | Delivery | p95 ms |
|---|---|---|
| 5 runs at load 5–17 | whole clip | 866–1,664 |
| 5 runs at load 5–17 | per sentence | 579–1,604 |
| 1 run, Piper 10 nice levels down and the run not raised above the foreign job | per sentence | 3,829 |
| 2 runs at load 16–19 (all 16 threads busy, SMT siblings loaded) | per sentence | 3,423–5,317, sim tick mean 8–10 ms |

On a quiet or moderately loaded host, per-sentence streaming keeps p95 well under 1 s. Whole clips are borderline, because the longest lines (7–10 s of audio) take 0.7–1.9 s to synthesise. When all cores are busy, the laptop's clock and SMT sharing slow the sim tick and Piper alike, and no setting holds 1 s.

## Criterion 2: closed set at Start

Start runs one language at a time, as a session has one language (FT-AUD-013). It sends every closed-set item to that language's voices (6 ship names, 20 callsigns and 20 NPC names), trims each clip's silence, then loads the language's prerendered fragments. `spikes/s7b/prerender.py` builds those at build time: the numbers 0–999 and 8 template words, rendered with the computer voice and trimmed.

| Language | Items | Synthesis s | Fragment load ms | Closed set MB | Cache MB | Start total s |
|---|---|---|---|---|---|---|
| en (2 voices) | 46 | 2.59 | 57 | 2.2 | 55.0 | 2.65 |
| it | 46 | 3.29 | 45 | 1.7 | 49.8 | 3.34 |
| pt | 46 | 2.83 | 50 | 1.5 | 53.1 | 2.89 |

That's run f-iso. Under load, Start took 3.2–7.6 s per language. Loading and warming the 4 voice processes in parallel took 3.1 s (1.8–2.8 s each), and 4.6–11 s on the loaded host. The fragment cache is large: 1,000 whole numbers average 1.1 s each, about 50 MB of 22.05 kHz PCM per language. Prerendering them took 280–340 s per language, with the three languages sharing 2 CPUs.

Stitched lines (for example "Contact | Viper Three | bearing | 342 | range | 18 | kilometres") are built on the sim thread in under 1 ms. They are audible after 70 ms p50, 124 ms p95 and 135 ms max (f-iso), which is the voice lane's one chunk per frame for clips of 1.4–5.8 s.

## Criterion 4: standalone Piper on Windows (TECH-4)

`piper_windows_amd64.zip` from https://github.com/rhasspy/piper/releases/download/2023.11.14-2/piper_windows_amd64.zip (22,477,236 bytes, SHA-256 `f3c58906402b24f3a96d92145f58acba6d86c9b5db896d207f78dc80811efcea`) holds `piper.exe`, `onnxruntime.dll` and `espeak-ng.dll` with its data. It needs no Python. Under Wine 10.0 (Ubuntu packages `wine`, `wine64`, `libwine` and `wine-common` 10.0~repack-12ubuntu1, a fresh 64-bit prefix), pinned to CPUs 14 and 15:

- `echo "Contact bearing three four two. Shields holding." | wine piper.exe --model en_GB-cori-medium.onnx --output_file line.wav` wrote a 22.05 kHz WAV of 3.4–3.7 s. The voice loaded in 0.61–0.67 s and synthesis ran at RTF 0.34–0.37. The process took 2.1 s in total warm, or 5.7 s including Wine's first prefix setup.
- With `--output-raw`, one process synthesised three lines read from stdin in turn (RTF 0.33–0.35), so it can also run as a persistent process. Like `python -m piper`, though, it marks no clip end.
- The 2023 onnxruntime pins its 8 threads with `SetThreadAffinityMask`, which fails under Wine and taskset with logged errors and no other effect. That release has no thread-count option, which explains part of the RTF gap against the native 0.04–0.07. The S7 voices' `.onnx` files work with it unchanged.

The sample is in the artefacts folder. The macOS archives from the same release weren't tested (no Mac).

## TECH-5 combined run (the S9 criterion)

What ran: the S9 load with 63 simulated stations (`--procs 9 --conns 7`) on CPUs 0, 1, 8 and 9, and the S7b server on CPUs 6 and 7, with the S6 sim load and 4 Piper voices. Its target client `c0` is a rendering Godot client on the same CPUs: not headless, under `xvfb-run` with llvmpipe (software GL, as in gate L5), drawing a lit, shadowed, spinning torus and playing each part on an `AudioStreamPlayer`. That client is the 64th connection on the host, though it connects to the S7b server rather than to S9. Events fire in **bursts of 6 lines at once, every 6 s** (9 bursts: 50 free-text lines, then the stitched lines).

| | Q2 (host load 5) | L2 (load 5–11, foreign job) |
|---|---|---|
| Free text audible, p50 / p95 / max ms | 929 / **1,768** / 2,322 | 1,365 / **2,588** / 3,185 |
| Burst positions 1–4 (one per voice), p50 / p95 ms | 547 / 1,311 | 800 / 1,952 |
| Burst positions 5–6 (queued behind a busy voice), p50 / p95 ms | 1,577 / 2,130 | 1,889 / 3,022 |
| S7b sim tick, mean / p99 / max ms | 1.5 / 3.7 / 8.0 | 2.1 / 6.0 / 17.7 |
| S9 server tick frames, mean / p99 / max ms | 4.5 / 10.5 / 12.5 | 3.5 / 8.5 / 16.7 |
| Rendering client frame time, p50 / p99 / max ms | 16.7 / 33.9 / 65.9 | 19.0 / 51.3 / 89.6 |

The S7b sim tick holds the 8 ms budget during bursts (worst single tick 8.0 ms in Q2). The S9 server's p99 misses 8 ms in both runs, as it did in Q1 without bursts, while S9 reports 6 ms on a quiet host. That process runs on other cores, so the excess comes from the shared host (load, clock and SMT siblings), not from Piper. The owner accepted S9's quiet-host tick as the pass.

The line criterion is missed. A burst of 6 lines needs about 2 CPU-seconds of synthesis (6 × 3.4 s of audio at RTF ~0.1), and 2 cores shared with the server and a rendering client can't do that within 1 s. Lines 5 and 6 also wait for a voice that is already busy. Fallbacks, in order of preference (provisional):

1. Keep free text rare. D101 already moves names and numbers to the Start cache (70 ms), so a burst of 6 free-text lines is unlikely. Have the voice bus (E10) treat a stale free-text line by its `max_age` like any other line, and always show the subtitle at once.
2. Synthesise first sentences first. Queue per voice by sentence, not by line, so every line's first sentence is ready before any second sentence. This lowers the queued lines' start time at no CPU cost.
3. Run two processes for the busiest voice (+60 MB of memory each). This helps only if a core is free.

## Notes for E10 and #6

- Stream per sentence. It halves p95 for long lines, and every later sentence arrived in time for gapless playback. The client needs a small part queue (a playlist or an `AudioStreamGenerator` feeder). The spike's rendering client plays each part on arrival, which is fine for one-sentence lines only.
- Keep the wrapper protocol (one JSON line in, length-prefixed PCM frames out with an explicit end) and one thread per voice. A failed or ended process shows up as an EOF frame; T0xx should restart it.
- Set `intra_op_num_threads` (1 here) and run Piper below the server's priority. Measure Piper on the target laptop class during S9-type load, since a fully loaded 16-thread host tripled the tick time and broke 1 s.
- The fragment cache is 50 MB per language as raw PCM. Ogg Vorbis (tech.md §4.3) or compositional number fragments (units, tens, hundreds, with per-language agreement such as pt "dois"/"duas") would cut it to a few MB; prerender time drops by the same factor.
- espeak-ng reads digits per language ("342" becomes "trezentos e quarenta e dois"), so number fragments need no authored text.
- `uv run` adds start-up time and a parent process. The spike resolves the venv's Python once and starts it directly. A release would start a bundled standalone Piper instead (TECH-4).

## How to run

```bash
godot=$(tools/get-godot.sh); $godot --headless --path . --import
uv run --project tools/tts python tools/tts/fetch_voices.py
for l in en it pt; do taskset -c 14,15 uv run --project tools/tts python spikes/s7b/prerender.py $l & done; wait
S7B_NICE=-10 spikes/s7b/run.sh /tmp/s7b/iso                    # criterion 3, isolated
spikes/s9/netns.sh up                                          # criterion 3 under the S9 load
spikes/s9/netns.sh exec spikes/s9/run.sh /tmp/s9/L1 --run-for 130 \
  --extra 'S7B_NICE=-10 S7B_LABEL="under S9 load" spikes/s7b/run.sh /tmp/s7b/L1'
spikes/s9/netns.sh exec spikes/s9/run.sh /tmp/s9/L2 --run-for 130 --procs 9 --conns 7 \
  --extra 'S7B_NICE=-10 S7B_RENDER=1 spikes/s7b/run.sh /tmp/s7b/L2 -- --burst 6 --line-every 6'
spikes/s9/netns.sh down
```

`run.sh OUT_DIR [--port 47840] [-- server flags]` starts the server pinned to `S7B_CPUS` (default `6,7`). Once the server listens (after Start), it starts `c0` and `c1`, then writes `server.log`, `c0.log`, `c1.log` and `summary.md` (`aggregate.py`). The environment variables are `S7B_NICE` (renice the run, needs sudo), `S7B_RENDER` (`c0` renders under Xvfb), `S7B_DUMP=DIR` (`c0` saves each part as WAV) and `S7B_LABEL`. Server flags, with defaults: `--stream sentence|clip [sentence] --nice 5 --threads 1 --burst 1 --line-every 1.0 --lines-at 2 --free all --langs en,it,pt --sim-ships 100 --sim-proj 500 --target c0 --tail 3`.

## Provisional decisions

These decisions are provisional, pending the owner:

- Clips stream per sentence. Audible means the first sentence is handed to the audio layer.
- There is one process per voice, which is FT-AUD-019's "one persistent Piper process" read as one per voice (R8). A session loads its language's voices only.
- Piper runs 5 nice levels below the server, with one ONNX thread per process.
- The closed set is spoken by its role's voice (ship names and callsigns by the computer voice, NPC names by the NPC voice), and numbers and template words by the computer voice.
- The TECH-5 run's rendering client connects to the S7b server rather than to S9, and S9 runs 63 stations.
