# TECH review: are the technical choices consistent?

Scope: spec 02, 03, 04, 09, 10, 12; research/tech.md; D5–D9, D38, D39, D63–D65, D70, D85, D94; issues #2, #3, #5, #6, #7, #9, #12 (and #4, #10, #11 where a finding needed a check). Claims about Godot 4.x come from my knowledge of 4.3–4.5; where I'm not sure, the finding says so and names the spike that should check it.

### TECH-1: Single global map in SI units on float32 `Vector3`: precision breaks far from the origin
- Severity: blocker
- Evidence: D77 (one global 3D map for the whole scenario, jump drive between sites); FT-SIM-033 and FT-DAT-013 (SI units); FT-SIM-034; FT-SIM-009 (swept-sphere projectiles); #5 T027 criterion "constant thrust matches analytic position within 1e-6 relative". No spec file gives the map's size or a coordinate scheme (grep of 04, 06 and 08 finds only "close < 1 km").
- Problem: In the official Godot binaries that FT-ARC-001 pins, `Vector3`, `Quaternion`, `Basis` and `Transform3D` are single precision. Only GDScript's scalar `float` is 64-bit, and double-precision vectors need a custom engine build. With sites spread over a map that a jump drive crosses, distances quickly reach 10^7–10^8 m. At 10^7 m a float32 resolves only about 1 m, and at 10^8 m about 8 m. Suppose a ship fights at a site 50,000 km from the origin. Swept projectiles miss or tunnel, assist jitters, clients see ships shake, and the 1e-6 test passes only because it runs near the origin. Neither S5 nor S6 tests this, and the map scale is never fixed.
- Proposal: Add FT-SIM-035, "positions are stored relative to the site they are at (site id plus a local float32 offset), and a jump changes the site". Also add one sentence to spec §4.1 giving the largest local coordinate the game allows (for example 200 km). Add an S6 criterion: an intercept at 10^8 m from the world origin behaves exactly like one at the origin. The alternative is an engine built with `precision=double`, which goes against FT-ARC-001 and the official export templates, so I don't recommend it.
- Options (owner decision on the representation):
  1. (Recommended) Site-local frames: positions are site id plus a float32 offset, and jumps re-base the ship. The cost is a frame change at each jump and on the Relay world map.
  2. Store positions as 64-bit scalars (a custom `Vec3d` built on `PackedFloat64Array`) inside `sim/`. This keeps one frame, but it's slower in GDScript (S6 must re-measure it) and adds conversions at every boundary.
  3. Custom double-precision Godot build. This handles everything, but it amends FT-ARC-001 and D70 (no official templates, and each version upgrade costs more).
- Affects: #3, #5, #9 (Relay map), #10 (jump drive)

### TECH-2: "Deltas against the last sent snapshot" over Godot WebSocket breaks under backpressure, and large messages exceed the default buffers
- Severity: major
- Evidence: spec §3.2 ("full on join or resync, deltas afterwards"); research/tech.md §2.4 ("delta against last sent is enough"); FT-NET-027; FT-AUD-018 (clips streamed on the same socket); #6 T040/T041 criteria; #3 S4 criteria.
- Problem: As far as I know, Godot 4's `WebSocketPeer` has bounded `outbound_buffer_size` and `inbound_buffer_size` (64 KiB by default) and a `max_queued_packets` limit. When the buffer is full, `put_packet` fails rather than blocking. S4 should verify these defaults. Suppose a tablet on weak Wi-Fi lags. A dropped delta silently desyncs that station, because the next delta builds on a base the client never got, and the reliable event stream (alerts, `CommandRejected`) can lose items too. A 3 s Piper clip as 22 kHz 16-bit PCM is about 130 KB, and a full join snapshot for 6 ships can exceed 64 KiB. Both are refused unless the buffers are raised or the message is chunked. No issue criterion covers a slow consumer.
- Proposal: Add FT-NET-037: "the server shall detect a send failure or a queue above a threshold for a client, stop sending it deltas, and send a full snapshot once the queue drains; events are never dropped." Add FT-NET-038: "messages above N KiB, such as clips and full snapshots, are chunked, and voice chunks have lower priority than snapshots." Add to S4 (#3) a stalled-reader client (one that pauses reading for 2 s) that must recover within one full snapshot. Snapshot deltas then need either acks or the "resync on failure" rule; the rule is simpler.
- Affects: #3, #6, #10

### TECH-3: Browser stations over plain `http://`: tablets sleep, and every sleeping tablet pauses the whole universe
- Severity: major
- Evidence: FT-NET-030 (plain HTTP), FT-NET-033–035 and D83 (10 s grace, then a universe pause), D94 (browser stations in M2), FT-STN-005, #3 S3 criteria (headless Chromium, ≥ 30 fps), #4 T022 (owner tablet test: join, touch and audio only), research/tech.md §2.7 (10–15 MB brotli, GDScript `TCPServer` static server).
- Problem: An `http://192.168.x.y` page isn't a secure context, so the Screen Wake Lock API is unavailable. The default auto-lock on iPads and Android tablets (30 s to 2 min) is likely to fire during a quiet Comms or Relay phase. Mobile Safari suspends a locked or background tab and its WebSocket, so after 10 s the whole universe pauses for all six ships. Three smaller gaps:
  - Browsers advertise `br` only over HTTPS, so the "brotli" size estimate doesn't hold, and the full project's wasm plus pck is bigger than the minimal S3 panel.
  - A naive `StreamPeerTCP.put_data` of a multi-MB file in the server's single-threaded main loop stalls the 60 Hz sim while tablets join.
  - S3's "≥ 30 fps in headless Chromium" runs on SwiftShader on fugaku and says nothing about tablets.
- Proposal:
  - Add an S3 criterion and a #4 T022 check: a tablet idles 10 min on a station without disconnecting, using a keep-awake workaround that works on `http` (a looping muted video, as NoSleep.js does), or tell players to turn off auto-lock in `docs/launch.md`.
  - Add FT-NET-039: "the static HTTP server shall not delay a sim tick by more than 1 ms" (serve from a `Thread` or with `put_partial_data` per frame). S3 measures it with 6 simultaneous joins of the full web export, gzip size recorded.
  - Move the 30 fps pass criterion to the owner's devices in #4. Keep Playwright for "joins and plays" only.
  - Grace and pause timers run on wall clock outside `sim/`, since the sim doesn't tick during a pause. Say so in FT-NET-034.
- Affects: #3, #4, #6, #9

### TECH-4: Release packages don't contain what the host must serve or run: the web export and the Piper runtime with its voices
- Severity: major
- Evidence: FT-NET-030 (the server serves the web export), FT-ARC-019 and FT-AUD-018 (runtime Piper in the server process on the host), D9 (Linux, Windows and macOS), #12 criteria (Linux/Windows packages with GPL text, macOS build, nothing about web or Piper), task-breakdown E15, #3 S7 (Piper pinned under `tools/tts/` with a uv lock), S7b (subprocess on fugaku), research/tech.md §4.2 point 2 (a bundled GPL binary carries source-offer duties), FT-LIC-008.
- Problem: A Windows owner downloads the release and hosts. Tablets get a 404, because no package bundles the web export built from the same commit (and a web build from another commit fails the FT-NET-005 version check). Dynamic lines are silent because Piper isn't bundled. S7 and S7b prove Piper only as a Python/uv venv on fugaku. Nothing shows a self-contained Piper with onnxruntime and espeak-ng data for Windows x86_64 and macOS arm64/x86_64, nor that macOS will run an unsigned helper binary spawned from inside the app bundle. FT-LIC-008's source link covers the game, not the bundled Piper and espeak-ng sources.
- Proposal: Add three #12 criteria. Each desktop package contains the web export of the same commit, which `gate.sh l6` serves and loads. Each package contains Piper, the approved voices and their licence files, and an L6 smoke test synthesises one line from the exported Linux and Windows builds. The source offer names Piper and espeak-ng versions. Add a criterion to S0 or S7b (#2/#3): a standalone Piper runs on Windows (cross-built or downloaded, smoke-tested under Wine or by the owner in #4). Note in FT-ARC-017 that Godot can ad-hoc sign the macOS export from Linux (and, I believe, sign and notarise with rcodesign given an Apple developer key), but the Piper helper needs signing too.
- Affects: #2, #3, #4, #12, #13

### TECH-5: Runtime Piper on a laptop host: latency and CPU are measured in isolation on fugaku, and the cheaper design isn't considered
- Severity: major
- Evidence: D85, FT-AUD-015 (< 1 s, "proposed target"), #3 S7b (p95 < 1 s over 50 lines on fugaku), #10 runtime criterion, research/tech.md §4.1 (RTF 0.05–0.2 per core) and §4.3 (fragment stitching), FT-ARC-006 (single-threaded sim), R15/S9 (server tick < 8 ms), spec §9.1 ("names, numbers, free text").
- Problem: Take the host player's laptop: it runs the server (sim, 64 filtered snapshots and HTTP), its own rendering client, and Piper. If six ships hit 40 % shields in the same second, six-plus synthesis jobs compete with the sim. A Piper process started per line also reloads the ONNX model each time, which is likely to take most of the 1 s budget on its own. S7b doesn't say whether Piper is a persistent process (`OS.execute_with_pipe`, available since 4.3, would allow one), and no spike measures the combined host load. Most "dynamic" text is a closed set known at lobby time: callsigns, ship names, scenario NPC names and numbers.
- Proposal: Make S7b say "one persistent Piper process per voice, fed over a pipe, off the sim thread". Add a combined host criterion to S9: server plus one rendering client plus a synthesis burst of 6 lines, with the tick still < 8 ms and p95 audible < 1 s. Then pick one of these:
- Options (owner decision; option 1 keeps D85):
  1. (Recommended) Synthesise the session's closed set at Start: every ship name, callsign and NPC name, cached per language. Numbers come from prerendered fragments, so runtime Piper runs on an event only for genuinely free text. This keeps D85 and makes the latency criterion nearly moot, at the cost of a few seconds' loading at Start and a fragment-template table per language.
  2. Keep D85 as is: synthesise per event with a persistent process and the combined-load spike. It's the simplest code, with latency and CPU risk on weak hosts.
  3. Amend D38/D85 back to tech.md §4.4: prerender plus fragments, with subtitle-only for free text. This drops the runtime GPL binary and its packaging (TECH-4), but loses spoken free text.
- Affects: #3, #10, #12

### TECH-6: The module-boundary lint can't work as #2 specifies it
- Severity: major
- Evidence: spec §2.2 (stations never touch `sim/`; `sim/`, `director/` and scenarios depend only on themselves and content), FT-ARC-010, FT-ARC-011, #2 `lint_arch.py` criterion (path patterns; folders `sim/ director/ missions/`; folder list without `missions/`), #5 T032 (lead point in sim) and T034 (clock/height/range helper in sim), #7 (Weapons lead reticle, contact chips with clock, height and range), FT-SIM-014, research/tech.md §2.5 (aiming is local), FT-DAT-001/D65 (`.tres` definitions), #5 T036 ("reset restores definitions exactly"), D86 (upgrade modules).
- Problem:
  - In Godot, a `class_name` is global. Station code can use `World` or `ShipState` without ever writing `res://sim/`, so a path-pattern lint misses the most common violation.
  - The other way round, the Weapons reticle must compute the lead point every frame from interpolated state, and contact chips need the clock/height/range helper. Both live in `sim/`, so the Weapons agent in #7 must either duplicate the math (and drift from the server) or fail the lint.
  - Scenarios are lint-covered as `missions/`, but that folder isn't in #2's module list, and spec 10 suggests scenarios are content. So it's unclear whether scenario lint applies anywhere.
  - Loaded `.tres` Resources are cached and shared. A sim that writes upgrade stats into a definition changes it for every ship and every later test in the same process, so the reset hash test is flaky or passes for the wrong reason.
- Proposal:
  - Add a `shared/` folder of pure value helpers (spatial callouts, lead intercept, units) that every module may import, and say so in §2.2.
  - Make `lint_arch.py` resolve `class_name` declarations to their folder and check identifiers as well as paths.
  - Name one scenarios folder (`scenarios/`) in §2.2, #2 and spec 10, and lint it.
  - Add FT-ARC-020: "definitions are read-only at runtime. Mutable per-ship state is copied from them, and `sim/` receives definitions already loaded (no `load()` or `ResourceLoader` in `sim/`)." Add `load`, `preload` and `ResourceLoader` to the lint's I/O patterns.
- Affects: #2, #5, #7, #10

### TECH-7: The restricted Scenario API can't be enforced by a lint in GDScript, so make it structural
- Severity: minor
- Evidence: D64, FT-DAT-007, FT-ARC-016, FT-TST-012, #10 criterion (lint fails a fixture that reaches past the API).
- Problem: GDScript has no sandbox or access modifiers. Any object reference a scenario receives can be changed through `obj.set("hull", 0)`, `call()`, `get_script()` or `Engine.get_main_loop()`, all built from strings that no lint resolves. Suppose a scenario author writes `target.set("shield_power", 0.0)` on a contact the API returned to force a dramatic loss. The lint passes, the test in FT-TST-012 passes, and FT-SIM-029 is broken. Scenarios are first-party code, so the risk is accidental coupling, not attack, but the stated guarantee ("no write access") is false as written.
- Proposal: Reword FT-DAT-009 and FT-ARC-016: "the Scenario API shall pass scenarios only ids and value copies (Dictionaries or read-only view objects that hold no sim reference). Every write is a queued sim command." FT-TST-012 then becomes checkable: a test walks every value the API returns and asserts that none of them is, or holds, a sim object. Keep the lint as a cheap extra (ban `set`, `call`, `get_script` and `Engine` in scenarios), not as the guarantee.
- Affects: #10

### TECH-8: The host player's crash kills the session, though D6 promises relaunch-and-continue to every player
- Severity: major
- Evidence: D6 ("a disconnected player (browser or desktop) must be able to refresh/relaunch and continue"), D7, FT-NET-001, FT-NET-003 (terminate the child on exit; "detect orphaned server processes on start"), FT-NET-026, #6 T046 criterion ("an orphan is detected on start via a pid file").
- Problem: The host machine runs the most code (server, rendering client, Piper), so its client is the one most likely to crash. If the client crashes, the child server survives as an orphan. On relaunch, "detect orphaned server" most plausibly kills it, and the run ends for all 64 players. Neither the spec nor #6 says that the relaunched host should reconnect to its orphan with its stored token, which is exactly the D6 path.
- Proposal: Amend FT-NET-003: "on start, if an orphaned server from this install is still running a session, the client offers to rejoin it with its stored token. It terminates the orphan only when that server has no session or the player chooses to." Add an L4 criterion to #6: kill the host client mid-run, relaunch it, and it rejoins the same ship and pick while the other two clients continue. Also make the server exit by itself when it has had no connections for N minutes, so orphans don't accumulate.
- Affects: #6, #7 (launch docs)

### TECH-9: The bandwidth budget for 64 connections is never estimated, and Wi-Fi is never measured
- Severity: major
- Evidence: research/tech.md §2.3 (about 90 KB/s per client, judged for 8 clients), FT-GEN-003 and D22 (64 connections), FT-NET-008, R4 and R10 in spec §2.4 ("busy Wi-Fi", "part of S4 on the owner's network"), #3 S4 and S9 (both on loopback with `tc netem`), #4 T022 (owner LAN test: join by one route only), #11 load criterion (loopback).
- Problem: Scaling tech.md's own figure gives 64 × 90 KB/s ≈ 5.8 MB/s, or about 46 Mbit/s of unicast TCP before delta compression. That's at or above the usable airtime of a busy 2.4 GHz home network, and every R4 and R15 test runs on loopback, where airtime doesn't exist. Take a 6-ship LAN party where half the screens are tablets: snapshot age spikes, and with TECH-2 deltas pile up. Spikes S4 and S9 pass on fugaku anyway. The server also filters and encodes 64 snapshots per tick in GDScript, although the 28 viewers of a ship receive identical main-screen views.
- Proposal: Add a per-client and total bytes/s line to S9 with a pass criterion (for example ≤ 10 Mbit/s total at 64 connections), and say so in R15. Add to #4 T022 one owner measurement of snapshot age with 4–8 real devices on the owner's Wi-Fi, using the S4 harness. Add FT-NET-040: "snapshots are encoded once per distinct view key (ship, catalogue entry, difficulty toggles) and sent to every client sharing it." That cuts viewer cost from 28 encodes to 6 at most, and costs one cache.
- Affects: #3, #4, #6, #11

### TECH-10: The integrator test is unmeetable as written, and the command log doesn't state the tick each command was applied on
- Severity: minor
- Evidence: #5 T027 criterion (semi-implicit integrator; "constant thrust matches analytic position within 1e-6 relative"), FT-TST-007, FT-ARC-008, FT-TST-009, #5 T037 (logs hold seed, build id and commands), §3.2 (commands carry a client sequence number).
- Problem: Semi-implicit Euler under constant acceleration from rest gives $x_n = a\,\Delta t^2\, n(n+1)/2$ against the analytic $a\,(n\Delta t)^2/2$, a relative error of $1/n$: 1.7 % after one second at 60 Hz, not 1e-6. Float32 vectors add drift on top (TECH-1). A replay is also reproducible only if the log records the sim tick at which the server applied each command, not just the client sequence numbers, because network arrival order and timing vary between runs.
- Proposal: In #5, either use the update $x \mathrel{+}= v\,\Delta t + \tfrac12 a\,\Delta t^2$ (exact for constant thrust), or compare against the discrete closed form, with a tolerance stated per vector precision. Amend FT-ARC-008 and FT-TST-009: "the command log records each accepted command with the tick it was applied on, in application order."
- Affects: #5

### TECH-11: Screenshot baselines are tied to fugaku's Mesa version, and tablet layouts are never rendered by the web build
- Severity: minor
- Evidence: FT-TST-003, #3 S2 ("10 repeats stable"), #7 and #9 L5 baselines (including "touch layouts ... at tablet size"), D70.
- Problem: llvmpipe output is stable within one Mesa version, but an unattended apt upgrade on fugaku can shift anti-aliasing and shading enough to fail every L5 baseline at once. An agent then "fixes" them with `--update-baselines` and hides real regressions. Touch-layout baselines come from the desktop renderer under Xvfb, so web-only differences (fonts, DPI scaling, WebGL2 shader precision) aren't covered.
- Proposal: Record the Mesa and llvmpipe version in `tests/visual/baselines/` metadata, and have `gate.sh l5` fail with a "baseline environment changed" message instead of a pixel diff. Have the #9 Playwright test also take one screenshot of a touch layout from the real web build, as a smoke check (not-blank and the expected panel visible), not a pixel baseline.
- Affects: #3, #7, #9

## Summary
The stack fits together (GDScript plus the single-threaded web export, WebSocket everywhere, a pure sim), but the plan never spikes six things: the float precision of a single SI-unit global map, WebSocket backpressure and buffer limits, tablets that sleep on `http`, Wi-Fi bandwidth for 64 clients, shipping Piper and the web export in releases, and a host crash.
The fixes are small: site-local coordinates, resync after a send failure, a keep-awake check, encoding once per view key, bundling and smoke-testing the web export and Piper in L6, and rejoining an orphaned server. TECH-1 must be settled before #5 starts.
Lint-based guarantees (`sim/` purity, the Scenario API) need structural backing in GDScript: a `shared/` helper folder, lint rules that resolve `class_name`, read-only definitions, and an API that hands out only ids and copies.
