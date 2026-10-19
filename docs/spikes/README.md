# M0 spikes: summary

Results of the M0 spikes (spec §2.4, #2 for S0 and S1, #3 for S2–S9), run on fugaku (i7-11800H, 16 threads, no GPU used) on 2026-10-19 with Godot 4.7.2-stable. Each spike's report has the method, commands and full numbers; this page gives pass or fail per criterion and, where the owner approved an outcome or a fallback in #4, the decision. Spike code is in `spikes/`, throwaway except the parts listed under "Promote".

From S2 onwards, an unrelated, unpinned 12-worker job loaded fugaku (load average 4–16, some swapping), so timings in S3, S9, S7b and the S8 shots are pessimistic; each report says which runs were affected.

Spike tests carry no `# FT:` tags, so the ids the spikes exercise stay pending in `docs/traceability.md` until the M1 issue that promotes the code; only the L5 gate's tests (FT-TST-003, FT-TST-020) count now.

## Results

| Spike | Criterion | Result | Numbers |
|---|---|---|---|
| S0 ([S0.md](S0.md)) | Pinned versions run on fugaku | pass | Godot 4.7.2, gdUnit4 6.2.2, gdtoolkit 4.5.0 verified by checksum (#2); Piper pinned in S7 |
| S1 ([S1.md](S1.md)) | Green from a clean checkout | pass | Cold import 3.5 s; Linux and Windows exports in 13 s (#2) |
| S6 ([S6.md](S6.md)) | 100 ships, 500 swept projectiles at 60 Hz on 1 core, < 4 ms (mean and p99, D104) | pass | Packed layout: mean 1.13–1.38 ms, p99 1.39–1.91 ms; object layout 1.40–1.74 / 1.75–2.30 ms |
| S6 | Intercept $10^8$ m out with site-local positions equals the one at the origin (R16) | pass | Bit-identical end state; naive global float32 errs by 1,058 m and the shot hits its own shooter |
| S5 ([S5.md](S5.md)) | Prototype: assist and decoupled, face, KB/M and controller | pass | `spikes/s5/helm_prototype.tscn`, 18 headless tests |
| S5 | NAV-3: compass, disc radar with stems, ship-frame chips, one mark, all-stop, approach | pass | All in the prototype; owner keeps the control defaults until the #4 playtest |
| S5 | Headless: assisted autopilot intercepts within 60 s; all-stop and approach stop within 1 km of a mark | pass | Intercept in 35.4–37.0 s from 3 starts; all-stop from 185 m/s in 17.6 s, then at rest 500 m from the mark at 59.6 s |
| S5 | Linux export for the owner playtest | owner (#4) | Build in the #4 artefacts |
| S2 ([S2.md](S2.md)) | `gate.sh l5` renders under Xvfb/llvmpipe and diffs with a tolerance; `--update-baselines` | pass | Channel threshold 8, at most $10^{-4}$ of pixels |
| S2 | Baselines record Mesa and llvmpipe; "baseline environment changed" (FT-TST-020) | pass | Also records the engine version; `tools/tests/test_l5.py` |
| S2 | 10 repeats stable, < 30 s per shot | pass | 0 differing pixels in every repeat; toon shots 0.07–1.2 s, v2 ship 1.4–17.6 s under load |
| S8 ([S8.md](S8.md)) | Procedural ship from 3 angles through S2, Compatibility only | pass, style approved | v1 toon (two palettes), then v2 semi-realistic with baked fake AO; the owner chose v2 worn (D107, T016) |
| S7 ([S7.md](S7.md)) | Piper pinned with a uv lock; 20 lines × 3 languages × 2 voices, robotic ship computer, stitched numbers and names | pass, with a gap | pt_PT has no voice with a clean licence (fallback below) |
| S7 | Licence audit from each MODEL_CARD; RTF per voice | pass | 47 voices audited (D105); RTF on one core 0.04–0.07 (medium), 0.58–0.66 (high) |
| S7 | Samples to #4, never committed | owner (#4) | 295 WAV files in the #4 artefacts |
| S4 ([S4.md](S4.md)) | 8 clients, 30 Hz, 2 % loss, 2 cores: p99 snapshot age < 150 ms (pooled, D106) | pass | p50 9.6 ms, p99 48.7 ms, max 749 ms; 4 of 32 client runs had their own p99 over 150 ms |
| S4 | Killed client resumes with its token within 2 s | pass | 195 and 202 ms from relaunch to first full snapshot |
| S4 | Stalled reader: no deltas, recovers within one full snapshot, no lost event | pass | Detected after about 530 ms; recovered 50 ms after resuming with exactly one full snapshot carrying 8 held events |
| S4 | Snapshot and voice clip above the chunk size arrive whole, voice behind snapshots; defaults recorded | pass | 16 KiB chunks; `WebSocketPeer` buffers 65,535 B, 4,096 queued packets |
| S3 ([S3.md](S3.md)) | No-thread web Engineering panel over plain HTTP, connects over WS | pass, with a workaround | Godot 4.7.2 needs a custom shell and an AudioWorklet guard on `http://` (D108; upstream godotengine/godot#124636, #124637) |
| S3 | Headless Chromium joins < 10 s and plays; audio after a tap; SwiftShader fps | pass | Join 1.3–1.8 s; audio after the tap; 28–40 fps (indicative) |
| S3 | Refresh-to-rejoin over 10 refreshes; keep-awake holds a 10 min idle | pass | Drop to resume mean 2.1–3.1 s, max 3.7 s, so the grace stays 10 s (D108); 10 min idle stayed connected |
| S3 | 6 simultaneous joins, gzip size, no tick delayed > 1 ms by HTTP | pass | 40.1 MB raw, 10.4 MB gzip; HTTP's share of a frame at most 0.77 ms during 6 parallel downloads |
| S9 ([S9.md](S9.md)) | 64 connections over 6 ships, 2 cores: tick < 8 ms, p99 snapshot age < 150 ms | **fail**, fallback approved (D111) | Load 4–6: tick mean 3.3 ms, p99 5.8–6.5 ms; foreign load: p99 10.7–23 ms; idle host at low clocks: p99 10.4–11 ms; snapshot age p99 16–28 ms |
| S9 | One encode per view key; ≤ 10 Mbit/s at 64 connections | pass | 42 keys for 64 connections; 3.0 Mbit/s payload, 6.4–7.2 Mbit/s on the wire |
| S9 | Server, a rendering client and a burst of 6 synthesised lines: tick < 8 ms, p95 line audible < 1 s | **fail**, fallback approved (D110) | Ticks fine (S7b sim p99 3.7 ms); a burst of 6 lines at once is audible at p95 1.77 s (load 5), 2.59 s (load 5–11) |
| S7b ([S7b.md](S7b.md)) | One persistent Piper process per voice, fed off the sim thread, clip streamed to one client | pass | 4 voice processes behind worker threads (`OS.execute_with_pipe`, `tools/tts/piper_stream.py`); the bystander client got 0 voice bytes |
| S7b | Closed set synthesised and cached at Start, numbers from fragments; Start time | pass | 46 names per language in 2.6–3.3 s plus 45–57 ms for 1,008 number fragments (quiet host; 3.2–7.6 s loaded); stitched lines audible at p95 124 ms |
| S7b | Free-text event-to-audible p95 < 1 s over 50 lines under the S9 load; GPL note | pass | Streamed per sentence: p95 353 ms isolated, 422 ms under the S9 load (739 ms with a foreign 12-worker job too); GPL aggregation note in `docs/provenance.md` |
| S7b | Standalone Piper on Windows x86_64 under Wine | pass | rhasspy/piper `2023.11.14-2` `piper.exe` under Wine 10.0, no Python; RTF 0.34–0.37 |

## Gaps and fallbacks

- **pt_PT voice (S7).** The only pt_PT Piper voice, tugão, is fine-tuned from lessac, whose data is research-only, so it counts as unclear and doesn't ship (FT-LIC-007). Approved fallback (D105): fine-tune a clean pt_PT voice from a from-scratch checkpoint on the CC0 tugão dataset (#16); tugão is development-only until then. Trade-off: training time on fugaku's CPU or a rented GPU, against a native voice with a clean licence.
- **Plain HTTP in the browser (S3).** Not a failed criterion, but a change to the plan: Godot 4.7.2's web export doesn't start on `http://` without a patched shell and a guarded audio call, and audio then uses the deprecated `ScriptProcessorNode` path. Approved (D108): keep both patches in the export pipeline with a test (#12) and drop them once upstream fixes land. Trade-off: a small patch to recheck on each engine upgrade, against self-signed HTTPS (warnings on tablets) or no browser stations.
- **Server tick under host contention (S9).** With other busy threads on the server's cores, the 64-connection tick p99 reaches 10.7–23 ms. D111 replaces D109's acceptance (below).
- **Burst of synthesised lines (S9 TECH-5, S7b).** Six free-text lines fired at once need about 2 CPU-seconds of synthesis, so lines 5 and 6 wait for a busy voice and the p95 reaches 1.8–2.6 s. Approved fallback (D110, FT-AUD-015): beyond 4 queued free-text lines, further lines show subtitles only; E10 (#10) builds it. Trade-off: a rare burst loses voice for its later lines, against more host CPU and RAM for extra Piper processes.
- **Server tick and CPU clock (S9).** On an idle fugaku the 64-connection tick p99 is 10.4–11 ms with no preemption: a 60 Hz loop that sleeps between frames runs at 0.8–1.8 GHz under the `powersave` governor, so the sim alone takes 2.9–3.7 ms instead of 1.1 ms. The owner treats the criterion as not met (D111, amending D109). Approved fallback: T041 (#6) encodes and sends snapshots on a worker thread from a copy of the state, so the sim tick holds only the sim. Trade-off: a state copy per snapshot and thread-safety work in T041.
- **Per-client snapshot age (S4).** Pooled p99 passes; 4 of 32 client runs had their own p99 above 150 ms because of TCP retransmission timeouts under 2 % loss. The per-device check is on the owner's Wi-Fi in #4 (D106).

## Owner steps in #4

The S5 playtest build, the S7 samples, the S8 screenshots (v1 and v2), the S3 web build with its serving README, the S7b clips and Wine sample, and the two upstream Godot issue drafts are in `ft-artifacts/issue-3/` on fugaku. Real-device checks (Wi-Fi snapshot age, tablet idle and refresh, the novice navigation drill, the voice choice per language) are #4's.

## Promote

| From | What | Into |
|---|---|---|
| S6 | Packed structure-of-arrays layout, grid broadphase keyed per site (the spike key kept only 4 site bits), swept projectiles relative to each ship; positions as site id plus three 64-bit floats (D104) | T025, T029 (#5) |
| S5 | Pure integrator ($x \mathrel{+}= v\,\Delta t + \tfrac12 a\,\Delta t^2$, exact rotation update), assist, all-stop, approach, callouts; widgets | T027, T028, T034 (#5); T050 (#7) |
| S4 | `S4Chunker`, `S4SendQueue`, `S4Resync`, `S4EventInbox`, `S4Sessions` | T045 (#6) |
| S9 | `S9Codec` (fixed point, integer dead reckoning, smallest-three quaternions), per-key message cache; encode and send on a worker thread from a state copy (D111) | T040–T042 (#6) |
| S3 | `S3StaticServer` (budgeted poll, gzip, ETag), `S3KeepAwake`, the shell and audio guard | #6, #12 |
| S7b | Persistent Piper wrapper (`tools/tts/`), closed-set cache at Start | E10 |
| S2 | `gate.sh l5` is already the real L5 tier | — |
| S8 | The approved ship generator, moved to `presentation/procedural_ship.gd` (`ProceduralShip`); v1 deleted | #7, E14 |
