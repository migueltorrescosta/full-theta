# Technical architecture and research: cooperative LAN bridge simulator

Spec: `spec-v0.3.md`. Date: 2026-10-18. Author: technical architect (agent).
Status: proposal. Nothing here is decided until the owner answers section 10.

Versions were checked on the web on 2026-10-18. Where only secondary sources were found, the text says so; spike S0 re-verifies every pin before it goes into the repo.

---

## 0. Summary

- **Engine:** Godot **4.7.2** stable (released 2026-08-18), typed **GDScript**, pinned. Unity, Unreal and Bevy are viable but each loses on licensing, headless agent workflow, or tooling maturity.
- **Topology:** one authoritative simulation in a **headless Godot server process**. The "Host game" button starts it as a child process on the host's machine (host-and-play), and the same binary runs on a dedicated box.
- **Network:** a small custom protocol (commands up; per-station filtered snapshots and reliable events down) on **WebSocket** for every client, so a browser station on a tablet uses the same code path as desktop. 60 Hz simulation, 30 Hz snapshots, no lockstep determinism, seeded RNG for reproducible tests.
- **Physics:** custom Newtonian 6DOF integrator and simple collision shapes in pure GDScript. Engine physics (Jolt) is not used in the simulation.
- **TTS:** **Piper** voices rendered **at build time** into Ogg clips, played on each client by a priority voice bus. Dynamic lines are stitched from fragments. GPL code never ships linked into the game. eSpeak NG is an option for a deliberately robotic ship computer. Kokoro is the alternative where Piper lacks a good voice.
- **Content:** JSON plus JSON Schema for ships, weapons, enemies, upgrades, dialogue and scenario components, validated in a local gate and loaded into typed classes.
- **Tests:** gdUnit4 headless. Simulation and network tests run in one process with no GPU. Screenshot tests use software GL under Xvfb and run only on fugaku. GitHub CI is one job running lint, unit, simulation and net tests, with the engine binary cached.

---

## 1. Engine choice

### 1.1 Candidates

| | **Godot 4.7.2** | **Unity 6.x LTS** | **Unreal Engine 5.6/5.7** | **Bevy 0.19** |
|---|---|---|---|---|
| Licence | MIT; no fees, no seats | Proprietary. Runtime fee cancelled (Sept 2024); seat subscription, with Pro required above the revenue threshold (secondary sources quote about $2,310 per seat per year in 2026) | Proprietary EULA; 5% royalty above $1M lifetime gross (secondary sources) | MIT/Apache-2.0 |
| Headless server | `--headless` (dummy renderer and audio) plus a "dedicated server" export that strips visual assets | `-batchmode -nographics`, Dedicated Server build target | Dedicated server targets need a source-built engine | `MinimalPlugins`, no window; trivial |
| Exports | Linux, Windows, macOS, Android, iOS, Web (GDScript only; C# can't export to Web in Godot 4, still true on 4.7) | All, including WebGL (heavy) | Desktop, consoles, mobile; no web | Desktop, WASM/WebGPU/WebGL2, mobile (less mature) |
| Stylised 3D | Good: toon shading through custom shaders, outlines, Compatibility (GL ES 3/WebGL2) and Forward+ renderers | Excellent (URP plus toon shaders) | Excellent but heavyweight for a cartoon look | Adequate; fewer ready shaders and tools |
| Multiplayer | High-level `MultiplayerAPI`/RPC, `ENetMultiplayerPeer`, `WebSocketMultiplayerPeer`, `WebRTCMultiplayerPeer`, raw `PacketPeer`/`StreamPeer` | Netcode for GameObjects/Entities, Transport (UDP plus WebSocket) | Mature replication; best of the four | Third-party crates (lightyear, renet) that break with each Bevy release |
| Agent fit (headless, no GPU, CLI only) | Very good. The whole project is text (`.tscn`, `.tres`, `.gd`, `project.godot`); a single 100 MB binary; tests run with `godot --headless`; no licence activation | Poor to fair. Editor licence activation on a headless box, multi-GB editor install, YAML scenes full of GUIDs, slow domain reloads | Poor. Over 100 GB of toolchain, C++ builds of tens of minutes, needs a GPU for most things, binary `.uasset` files | Very good (pure code, `cargo test`), but no mature editor and a breaking release about every 3–4 months |
| Risk | GDScript speed for a heavy simulation (spike S6) | Licence and business risk; tooling weight | Weight and cost; poor fit for a small team of agents | API churn; UI, text and audio are thinner; slower to a first playable |

Other engines considered and rejected: Stride (C#, Windows-centric tooling), O3DE (heavy, small community), raw three.js plus a Node server (would require building the 3D tooling and native clients ourselves).

### 1.2 GDScript vs C# in Godot

| | Typed GDScript | C# (.NET 8+) |
|---|---|---|
| Web export | Yes | **No** (Godot 4 still can't export C# to Web) |
| Speed | About 5–20× slower than C# for tight numeric loops | Fast |
| Tooling for agents | Built in; `gdtoolkit` (gdlint, gdformat); `--check-only` parse | Roslyn, analysers, `dotnet test`, strong typing |
| Build | None | .NET SDK; mono-flavoured Godot binary |
| Test frameworks | gdUnit4, GUT | gdUnit4Net, plain xUnit for pure-C# simulation |

Recommendation: **typed GDScript** with `untyped_declaration` warnings set to error. That keeps the browser-client option open and keeps one language. If spike S6 shows the simulation hot loop is too slow, port only that loop (integration and collision broadphase) to a C++ or Rust **GDExtension**. GDExtension does compile to Web, but it needs the threads/no-threads variants and adds per-platform build cost, so it's the fallback, not the plan.

### 1.3 Recommendation

**Godot 4.7.2, typed GDScript, Compatibility renderer.** It fits the spec's stated preference, the licence (MIT, no royalties), headless agent development (text project, one binary, no activation), the web-client option, and a cheap CI. The proof-of-concept spikes S1–S6 in section 9 confirm the choice before broad implementation.

Pinning: a `tools/godot-version` file holds `4.7.2-stable` and the SHA-512 of the Linux binary and export templates. `tools/get-godot.sh` downloads and verifies them. CI caches them on that key. Upgrades are deliberate PRs, and Renovate doesn't touch the engine pin.

Renderer: **Compatibility** (OpenGL 3.3, GLES 3, WebGL2) everywhere. A flat or cel-shaded cartoon look doesn't need Forward+ features (SDFGI, volumetrics). The renderer runs on weak laptops and tablets and works under Mesa llvmpipe for screenshot tests, and the desktop and web clients then look identical. Forward+ for desktop stays a later option (decision D27).

---

## 2. Networking

### 2.1 Authority model

One **authoritative simulation** per session, as the spec requires. Clients never simulate gameplay. They send **commands** (intents such as `SetThrust{x,y,z}`, `SetPower{system, level}`, `Fire{mount, aim_dir}`, `LaunchProbe{target}`) and render **state** plus **events**.

- **Validation on the server.** Every command is checked against station ownership (does this client hold the Weapons station?), rate limits, and game rules (arc, cooldown, energy). Rejected commands produce a `CommandRejected{reason}` event so the UI can show why.
- **Asymmetric information is enforced on the server.** Each client gets a **station-filtered view**. Science receives scan details, and the other stations don't receive them at all. That makes "information asymmetry" a property of the protocol rather than of UI discipline, and it's testable (tests assert the Helm snapshot contains no shield-frequency field).

### 2.2 Hosting options

| Option | How | Pros | Cons |
|---|---|---|---|
| **A. Host-and-play, server as a child process** (recommended) | The "Host" button on any desktop client spawns `game --headless --server` (the same executable) and connects to it on localhost | One code path for LAN and dedicated hosting; a client crash doesn't kill the session; the server tick is isolated from rendering hitches | Two processes on the host machine; needs process lifecycle handling (kill on exit, orphan detection) |
| B. In-process listen server | The host client also runs the simulation in its SceneTree | Simplest to start | Rendering stalls stall the simulation; a host crash ends the game; temptation to share state outside the protocol |
| C. Dedicated machine only | A separate headless box | Cleanest | Needs a spare machine; worse UX |

A and C are the same binary, so A also delivers C. Recommendation: A, with C free.

### 2.3 Transport

| | ENet (UDP) | WebSocket (TCP) | WebRTC |
|---|---|---|---|
| Browser clients | No | **Yes** | Yes, but needs signalling and STUN-less LAN ICE quirks |
| Unreliable channel | Yes | No (everything reliable and ordered) | Yes |
| LAN fit | Ideal | Fine: head-of-line blocking is negligible at LAN RTT (< 5 ms) and loss | Overkill |
| Godot support | `ENetMultiplayerPeer` | `WebSocketMultiplayerPeer`, `WebSocketPeer` | Plugin binaries for desktop |

A single `MultiplayerAPI` binds to one peer type, so mixing ENet desktops with WebSocket browsers needs either two listeners and a bridging layer or a custom `MultiplayerPeerExtension`. Recommendation: **WebSocket for all clients**, behind a thin `Transport` interface so ENet can be added later if Wi-Fi tests show a problem (spike S4 measures this).

Bandwidth estimate: about 50 visible entities × 60 bytes × 30 Hz ≈ 90 KB/s per client before delta compression. Trivial on any LAN, and comfortable on 2.4 GHz Wi-Fi with 8 clients.

### 2.4 State sync vs commands and events

Use the hybrid that EmptyEpsilon-style games need:

- **Up (client to server):** commands only, each with a client sequence number.
- **Down, continuous state:** snapshots at **30 Hz** (positions, orientations, velocities, subsystem values the station may see). Full snapshot on join or resync; afterwards, deltas against the last snapshot the client acknowledged. With WebSocket's reliable delivery, "delta against last sent" is enough.
- **Down, discrete events:** a reliable ordered stream of `Event{tick, type, payload}` such as `ShieldsLow{40%}`, `HullHit{dir}`, `SubsystemDamaged{engines}`, `MissionUpdate`, `PlayVoice{line_id}`. Events drive alerts, voice and feedback, so feedback is immediate and identical for every station that should see it (spec §5).
- **Don't use** `MultiplayerSynchronizer`/`MultiplayerSpawner` scene replication for gameplay state. It couples the simulation to the SceneTree, it can't easily do per-station filtering, and it's hard to unit test. Godot RPCs are acceptable only as the transport for opaque byte messages, or skip the high-level API and use `WebSocketPeer` directly.
- **Serialization:** `var_to_bytes` (no objects) for the first milestone, with a protocol version number in the handshake. Move to a hand-packed `StreamPeerBuffer` format if profiling shows a need.

### 2.5 Tick rate, latency and determinism

- Simulation: fixed **60 Hz** (`dt = 1/60`), driven by the server's own accumulator, not `_physics_process`, so tests can step it directly. 60 Hz keeps fast projectiles and turning ships stable without substeps.
- Snapshots: **30 Hz**; clients interpolate with an about 66 ms buffer (2 snapshots). No client-side prediction: LAN RTT is below one tick, and helm inputs are thrust intents whose effect is inertial anyway. The camera and UI are smoothed locally. Weapons aiming is local (the reticle is client-side), and the aim vector is sent with `Fire`.
- **Determinism:** lockstep determinism across machines is **not** required, because the server is authoritative. **Reproducibility** is required for tests and debugging: one seeded `RandomNumberGenerator` per subsystem, a fixed timestep, single-threaded simulation, stable iteration order (entities in an array sorted by id, never iterated from a Dictionary of objects). The same binary on the same platform then reproduces runs from the seed plus the command log. That enables golden replays and bug reports carrying a replay file. Cross-platform float bit-equality isn't promised; golden tests use tolerances.

### 2.6 LAN discovery and joining

- **Desktop:** the server broadcasts `{name, port, version, free_stations}` once a second over UDP broadcast (`PacketPeerUDP`, port 47_000 or similar), and clients list hosts. Manual IP entry is the fallback (Wi-Fi AP isolation and some OS firewalls block broadcast; Windows shows a firewall prompt on first host).
- **Browser:** browsers can't listen for UDP. The host shows a **URL and QR code** (`http://192.168.x.y:8080/`). That requires the host to serve the web export over HTTP; see 2.7.
- mDNS/Bonjour is possible later but is extra work in Godot.

### 2.7 Browser station client (touch tablets and phones)

Feasible with caveats. Spike S3 settles it before the decision.

- Godot 4.3+ can export **single-threaded web builds**, which don't need `SharedArrayBuffer` and therefore don't need cross-origin isolation or HTTPS. That matters: on a LAN the page is plain `http://` from a private IP, which isn't a secure context. A threaded build would need HTTPS with a trusted certificate on the LAN, which is impractical.
- The page loaded over `http://` may open `ws://` to the same host (no mixed-content block). An HTTPS page couldn't.
- Something must serve about 10–15 MB of brotli-compressed wasm and pck. Options: a tiny static HTTP server inside the headless server (GDScript on `TCPServer`, about 200 lines, no TLS), or a separate static server binary started by the host. Built-in is preferred (one process to manage).
- The browser client should be a **lightweight station build**: 2D/UI-heavy stations (Engineering, Science, Relay, Captain) work well on tablets. Helm and Weapons need 3D and are better on desktops. The same Godot project exports with a feature tag (`station_lite`) that excludes heavy 3D assets.
- Audio in browsers starts only after a user gesture ("Tap to join" fixes this). Voice clips must be downloaded or streamed; preload the language pack on join.
- iOS Safari runs WebGL2 and wasm but has memory limits (about 1 GB on recent iPads; less on phones). Test the target devices early.

Recommendation: design the protocol web-ready from day one (WebSocket, no ENet-only features), ship **desktop clients for the first playable**, and run the web spike in parallel so the owner can decide with data (D5).

---

## 3. Physics

### 3.1 Custom integrator vs engine physics

| | Custom 6DOF in `sim/physics` (recommended) | Godot physics (Jolt, default since 4.6) | Hybrid |
|---|---|---|---|
| Testability | Pure functions on plain data; step N ticks and assert | Requires the SceneTree and PhysicsServer; stepping is coupled to the engine loop | Medium |
| Determinism and reproducibility | Full control | Jolt is deterministic per build, but Godot's integration adds ordering you don't control | Medium |
| Needed features | Thrust, torque, inertia tensor, angular momentum, simple collisions | A general rigid-body solver: far more than needed | — |
| Spec rule "never secretly manipulate physics" | Explicit and auditable | Hidden solver behaviour (sleep, damping defaults) | — |

Space combat with a few dozen bodies needs **dynamics** (forces to motion), **queries** (ray and sphere casts for beams and projectiles, arc checks) and **coarse collision** (ship vs ship, ship vs asteroid, ship vs projectile). It doesn't need stacking, joints or friction. A custom layer is about 1,000 lines and is fully testable.

### 3.2 Design

- **State per body:** position `Vector3`, velocity, orientation `Quaternion`, angular velocity in body frame, mass, diagonal inertia tensor (body frame), thruster capability table (max force per local axis, max torque per axis), drag zero.
- **Integration:** semi-implicit (symplectic) Euler at 60 Hz. Rotation: integrate angular momentum with Euler's equations (diagonal inertia), update the quaternion with `q += 0.5·ω_q·q·dt`, then normalise. Optional RK4 if spike S5 shows energy drift matters (unlikely at 60 Hz with no gravity wells; with gravity wells, use velocity Verlet).
- **Flight assist** (spike S5): pure 6DOF is notoriously hard to fly. Provide explicit, visible assist modes (rotation damping, velocity hold, "kill velocity" toward a target) implemented as **controllers that issue real thruster commands within the same limits**, never as direct state changes. That satisfies the spec's no-secret-manipulation rule and gives Engineering + Helm a lever: assist burns power.
- **Collision:** spheres and capsules (or compound spheres) per ship; asteroids as spheres; a uniform grid or sort-and-sweep broadphase (only if spike S6 shows more than about 200 bodies). Projectiles as **swept spheres** against targets (no tunnelling at 60 Hz). Beams as instantaneous rays with a range. Response is an impulse with restitution plus damage from relative kinetic energy.
- **Weapon geometry:** each mount has a local transform, an arc (cone half-angle or yaw/pitch limits) and a range. `can_fire(mount, aim_world)` transforms the aim into the mount frame and checks the limits. This is a pure function, which is ideal for tabled unit tests (spec §11 "weapon geometry").
- **Units:** SI (metres, seconds, kilograms, newtons), documented in the code and the content schema.

### 3.3 Testing

- Analytic tests: constant thrust gives `x = ½·a·t²` within tolerance; free rotation conserves angular momentum; a torque-free symmetric top precesses correctly; a zero-input ship holds velocity forever (Newton's first law).
- Property tests (a seeded random loop in gdUnit4): quaternions stay normalised; energy stays bounded with no input.
- Weapon-arc table tests: mount pose × aim vector gives the expected allowed or denied result, including edge-of-arc cases.
- Golden replays: a recorded command log run for N ticks matches the stored final state within ε.

---

## 4. Offline multilingual TTS

### 4.1 Candidates

| Engine | Quality | Languages | Licence (code; voices) | CPU latency (fugaku-class x86) | Godot integration |
|---|---|---|---|---|---|
| **Piper** (OHF-Voice/piper1-gpl, v1.8.0, Sept 2026) | Good neural (VITS); several voices per major language | About 40 languages (en, de, fr, es, pt-PT/BR, it, nl, pl, ru, uk, cs, fi, sv, no, da, el, tr, ar, zh, vi, …) | **Engine is GPL-3.0** since v1.3 (it embeds espeak-ng). The old rhasspy/piper (MIT) is archived. **Each voice has its own MODEL_CARD licence**: some are CC0 or CC-BY, some are **non-commercial** (derived from NC datasets). Audit voice by voice | Real-time factor about 0.05–0.2 for "medium" voices: a 3 s line renders in about 0.2–0.5 s on one core | CLI or `libpiper` C++ API; via subprocess, or via sherpa-onnx |
| **Kokoro-82M** | Very good for 82M parameters; English best | en (US/UK) full; ja, zh, es, fr, hi, it, pt-BR partial | Weights **Apache-2.0**. Its G2P (misaki) falls back to **espeak-ng (GPL-3.0)** for non-English | Slower than Piper: about 0.3–1 s per short line on CPU | ONNX via sherpa-onnx or Python |
| **eSpeak NG** | Robotic, formant synthesis. Arguably *on-style* for a retro ship computer | 100+ languages | **GPL-3.0** | Instant (ms) | Subprocess (`espeak-ng --stdout`) or library (GPL linking) |
| **Coqui XTTS v2** | Excellent, voice cloning | 17 | **CPML: non-commercial**; Coqui shut down in Jan 2024; unmaintained | Seconds per line on CPU; wants a GPU | **Reject** |
| **Godot `DisplayServer.tts_*`** (OS voices) | Varies by OS: SAPI/OneCore on Windows, AVSpeech on macOS, speech-dispatcher on Linux, Web Speech API in browsers | Whatever the OS has installed | None (OS) | Instant | Built in, with priority and interrupt flags and utterance callbacks |
| sherpa-onnx (k2-fsa, v1.13.x) | Runtime, not a voice | Runs Piper, Kokoro, VITS and Matcha models | Apache-2.0 itself, but its Piper and Kokoro front-ends **link espeak-ng (GPL-3.0)** | As the model | C API; would need a GDExtension wrapper (none exists that we found) |
| Others worth a look | MeloTTS (MIT; en, es, fr, zh, ja, ko); Kitten TTS (Apache-2.0, tiny, English only) | — | Check each model card | — | — |

### 4.2 The licensing point

Every good open phonemizer for these neural voices is **espeak-ng, which is GPL-3.0**. If the game binary links it (GDExtension wrapping libpiper or sherpa-onnx), the distributed game must be GPL-3.0-compatible. Ways to avoid that:

1. **Pre-render at build time** (recommended): GPL tools run only in the build pipeline. Their *output* (audio) isn't covered by the GPL. Only the voice model's licence (MODEL_CARD) governs the clips, so pick CC0, CC-BY or MIT voices and record attribution in `CREDITS.md`/`content/voices/LICENSES.json`.
2. Ship the Piper or eSpeak **CLI as a separate executable** and call it by subprocess (generally treated as "aggregation", but it carries GPL source-offer duties for that binary).
3. Make the whole game GPL-3.0 (also the simplest way to reuse EmptyEpsilon code, *if* EmptyEpsilon's GPL-2.0 is "or later": verify. GPL-2.0-only code can't be combined with GPL-3.0 code).

That interacts with the project licence: decision D17.

### 4.3 Integration design (recommended)

- **Line catalogue:** every spoken line has an id, a speaker voice role (`ship_computer`, `npc_trader`, …), a priority, and text per language in `content/dialogue/*.json`.
- **Build step** `tools/tts/render.py` (run with `uv`, pinned `piper-tts`): for each line × language, render WAV with the chosen voice, normalise loudness (−16 LUFS) and encode **Ogg Vorbis** into `assets/voice/<lang>/<line_id>.ogg`. A **content hash** of (text, voice, engine version) makes the step incremental, and a manifest records the hashes. Generated audio is **not committed**: it's rebuilt locally and cached, and only release packaging builds it all. Estimated cost: 2,000 lines × 4 languages × 0.3 s ≈ 40 minutes on one core, or 3 minutes across 16 cores.
- **Dynamic text** (ship names, numbers, bearings, credits): **fragment concatenation**. Pre-render number words, units, bearings and the proper names in the content files, and compose them at runtime ("Shields at" + "forty" + "percent"). Languages with grammatical agreement (pt, de, fr) need per-language templates; the line format allows slot variants. Truly free text (player-typed ship names) falls back to text-only or to the OS TTS.
- **Playback:** each client plays voice locally when it receives `PlayVoice{line_id, slots, priority, scope}` from the server, filtered by station (Engineering hears "Shields at forty percent"; Helm may not).
- **Voice bus with priority and interruption:**
  - Priorities: `P0 critical alarm` (hull breach, collision imminent) > `P1 ship computer status` > `P2 NPC radio/dialogue` > `P3 ambient chatter`.
  - Rules: a higher priority **preempts** a lower one (fade 80 ms, then resume or drop per line flag); equal priority **queues**; each queued line has a `max_age`, after which a stale "shields at 60%" is dropped when 40% has already been announced; **coalescing keys** mean newer same-key lines replace queued ones.
  - Non-voice alert tones play on a separate SFX bus and are never blocked by voice, so critical feedback can't be lost.
  - Implemented in `audio/voice_bus.gd` as pure logic (a queue state machine) plus a thin `AudioStreamPlayer` adapter, so the logic is unit-testable headless.
- **Fallbacks:** if a clip is missing (a new line not yet rendered), use the OS TTS in development builds and log it; in release builds, show the subtitle. **Subtitles always show** (accessibility, noisy room).

### 4.4 Recommendation

**Piper, pre-rendered at build time, with permissively licensed voices**, the language list chosen by the owner (D15). Optional stylistic choice (D16): **eSpeak NG** pre-rendered for the ship computer to get a retro robotic voice, with Piper for human NPCs. Kokoro is the fallback for languages or roles where Piper's voices are weak, if spike S7 shows a quality gain worth its slower rendering. Runtime synthesis (a sidecar) stays possible later because the voice bus takes clips from any source.

---

## 5. Input

Godot covers all three modes in one project:

- **Keyboard and mouse:** `InputMap` actions in `project.godot`; mouse capture for Weapons aiming; rebinding UI through `InputMap.action_erase_events`/`action_add_event`, persisted to `user://input.cfg`.
- **Controllers:** since 4.5, desktop gamepad support is **SDL3-based** (Windows, macOS, Linux), with the SDL controller database and hot-plugging. Analog sticks map to 6DOF (left stick translate, right stick pitch and yaw, bumpers roll, triggers forward and back thrust). Browser gamepads go through the older Web Gamepad API path; verify in spike S3.
- **Touch:** `InputEventScreenTouch`/`InputEventScreenDrag`, multi-touch, `emulate_mouse_from_touch` for plain UI. Touch-first layouts for the 2D stations (large hit targets, sliders for power, no hover). Virtual sticks only if Helm on touch is ever wanted.
- **Architecture:** `input/` maps device events to **station intents** (`HelmIntent{translate: Vector3, rotate: Vector3}`), which the station UI turns into protocol commands. Tests inject intents directly, and gdUnit4's scene runner can simulate key and mouse events for UI tests.
- **Multi-station on one client** (a "combinable" station per spec §4): a client may hold several stations, as tabs or split screen; input focus follows the active panel.

---

## 6. Data-driven content format

### 6.1 Definitions (ships, weapons, subsystems, upgrades, enemies)

| Format | Pros | Cons |
|---|---|---|
| **JSON + JSON Schema** (recommended) | Agents and humans edit it easily; diff-friendly; validated outside the engine (`check-jsonschema` in pre-commit, millisecond feedback); `JSON.parse` built in; also readable by Python tools (TTS renderer, balance scripts) | No comments (allow a `"_note"` field); no engine-native references |
| Godot Resources (`.tres`) with typed `Resource` classes | Typed, inspector-editable, native references to meshes and sounds, loaded by `load()` | Godot-only text format; schema lives in GDScript; validating needs the engine; awkward for the Python build tools; the owner doesn't use the editor |
| YAML / TOML | Comments; nicer to hand-write | Not built into Godot (needs an addon or GDExtension); YAML's implicit typing traps |
| Lua (EmptyEpsilon style) | Full scripting | Needs a GDExtension Lua binding (web builds harder); sandboxing; untyped; harder to validate statically |

Load JSON into **typed GDScript data classes** (`ShipDef`, `WeaponDef`, `MountDef`) at startup with explicit validation errors (file, path, reason). IDs are strings (`"weapon.laser_mk1"`) and cross-references are checked at load. Asset references are `res://` paths, and the schema test checks they exist.

### 6.2 Scenarios, missions and the director

Spec §2 and §7: reusable handcrafted components, branching, adaptive director, no game master.

| Option | Description | Trade-off |
|---|---|---|
| **A. Declarative component graph in JSON** (recommended) | A mission is a graph of **nodes** (objectives, encounters, dialogues, rewards) joined by **transitions** with conditions from a fixed vocabulary (`entity_destroyed`, `timer`, `scanned`, `flag`, `choice`, …) and actions (`spawn`, `say`, `give`, `set_flag`). The director picks and parameterises components from tagged pools by pacing curve and current tension | Fully validatable and testable (graph reachability, every branch terminates); the vocabulary grows deliberately; complex logic needs a new condition type in code |
| B. GDScript scenario scripts | Each scenario is a script extending a `Scenario` base with hooks | Maximum flexibility; harder to validate statically; agents may hide simulation manipulation in scripts |
| C. Lua scripts (EmptyEpsilon-compatible-ish) | Embed Lua | Only worthwhile if EmptyEpsilon scenario compatibility is a goal (spec §12 open); adds a GDExtension |

Expressions in conditions: a tiny safe expression subset parsed by our own code (comparisons, and/or, references to whitelisted state). **Don't use** Godot's `Expression` with a base instance: it can call arbitrary methods.

**Dialogue:** a JSON dialogue tree in the same format (nodes, options, conditions, effects, `line_id` per spoken line), so the TTS renderer and translators work from one source. An alternative is the Dialogue Manager addon (nathanhoad, MIT, GDScript, its own `.dialogue` format), which is pleasant to write but is a second format to feed the TTS pipeline. Yarn Spinner for Godot and godot-ink need C#, so they're out with GDScript.

**Localisation:** text lives in per-language string tables (`content/i18n/<lang>.json` or Godot's CSV/PO translations). Line ids are shared by the UI, subtitles and TTS.

---

## 7. Testing and CI

### 7.1 Frameworks

| | **gdUnit4** (recommended) | GUT 9.x |
|---|---|---|
| Godot support | v6.x supports Godot 4.3–4.7 (v6.1.3, April 2026, per a secondary source; verify) | Godot 4.x |
| Headless CLI | `godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --add res://tests --report-directory reports` | `-s addons/gut/gut_cmdln.gd` |
| Reports | JUnit XML and HTML | JUnit XML |
| Extras | Scene runner (input simulation, frame stepping), mocks, spies, fuzzers, parameterised tests | Simpler, doubles and stubs |

Pin the addon by vendoring it at a tag into `addons/` (copied, with the commit noted in `addons/VERSIONS.md`).

### 7.2 Test layers

| Layer | What | Needs | Where |
|---|---|---|---|
| L0 static | `gdlint`, `gdformat --check` (gdtoolkit 4.x, pinned with uv), `godot --headless --check-only` parse of all scripts, JSON Schema validation of `content/`, an "architecture lint" script (no `extends Node` and no SceneTree access under `sim/`; no `sim/` imports from `presentation/`) | Seconds | Pre-commit, CI |
| L1 unit | Pure simulation: physics, arcs, damage, power, voice-bus queue, protocol encode/decode, content loaders | `--headless`, no GPU | Local, CI |
| L2 simulation scenarios | Step the world N ticks with scripted commands: encounters, mission transitions, **run reset**, the **15 station-pair tests** (each asserts the cooperative variant beats the solo variant on its metric and the solo fallback still works), golden replays | Headless | Local, CI |
| L3 network in-process | Server plus 2–3 clients in **one headless process** over loopback WebSocket (Godot allows several `MultiplayerAPI`s or raw peers in one tree). Asserts join, station claim, command, snapshot convergence, per-station filtering (no leaks), reconnect | Headless, localhost | Local, CI |
| L4 network multi-process | A script starts `--server` plus 2 headless clients with a scripted bot and checks the outcome log. Pinned with `taskset -c 0,1` to mimic CI | Headless | Local; CI nightly or on demand only |
| L5 visual | Screenshot tests of each station UI and a 3D scene: `xvfb-run godot --rendering-driver opengl3` with Mesa **llvmpipe** (software, reproducible) and a fixed-time frame via `--fixed-fps` or Movie Maker `--write-movie`. Tolerant image diff plus a "not black/blank" check | Xvfb, Mesa | **fugaku only** |
| L6 export | Export Linux/Windows (and Web if chosen) from templates; smoke-run the Linux export headless | Templates | Local; CI on tag only |

Godot import cache: a fresh checkout needs `godot --headless --import` (4.x) before tests, or class names and resources won't resolve. That's the first step of every gate script.

### 7.3 Keeping CI cheap

- **One CI job** (no matrix) on PRs marked ready: restore the cached Godot binary (keyed on `tools/godot-version`), import, then L0 + L1 + L2 + L3. Target under 4 minutes wall time; one job avoids the per-job rounding that inflates billed minutes.
- `paths-ignore` for docs-only changes; `concurrency: cancel-in-progress` per branch.
- L4, L5 and L6 run on fugaku via `make gate` (or `just gate`). The PR body records which commit passed which local gates (the existing workspace rule).
- Generated TTS audio isn't needed by tests (the voice bus is tested with stub clips), so CI never runs Piper.
- No Windows or macOS runners (2× and 10× minute multipliers). Windows export is cross-built on Linux and smoke-tested manually by the owner per release (a Human-host issue).

---

## 8. Module architecture and repo layout

### 8.1 Modules and dependency rules

```
                 content (JSON + schemas)
                          │ loaded by
   ┌──────────────────────▼───────────────────────┐
   │ sim/  (pure, no SceneTree, no I/O, seeded)    │◄── director/ + missions/ (pure; act through sim commands/API)
   │  world · entities · physics · systems         │
   │  (power, weapons, damage, sensors, repair,    │
   │   comms, economy) · ai · rules/validation     │
   └───────▲───────────────────────┬──────────────┘
           │ commands               │ state views + events
   ┌───────┴───────────────────────▼──────────────┐
   │ net/  protocol · codec · server session ·     │
   │       per-station view filter · client sync · │
   │       discovery · web static server           │
   └───────▲───────────────────────┬──────────────┘
           │ commands               │ replicated state + events
   ┌───────┴──────┐   ┌────────────▼─────────────────────────────┐
   │ input/       │──►│ stations/ helm · weapons · engineering ·  │
   │ device→intent│   │ science · relay · captain · main_screen   │
   └──────────────┘   │ (UI; read client state, emit commands)    │
                      └───────┬───────────────────┬──────────────┘
                              │                   │
                   presentation/ (3D views,   audio/ (voice bus,
                   toon shaders, VFX, HUD)    alerts, music; plays
                                              PlayVoice/alert events)
```

Rules, enforced by the architecture lint:
- `sim/`, `director/` and `missions/` depend on nothing but themselves and `content` definitions. They are `RefCounted` classes with no Nodes, so they run the same in tests, on the server and in replays.
- The director changes **which events happen** only through the same public simulation API that missions use (spawn, offer, message), never by editing stats (spec §5, §7). A test asserts the director holds no write access to combat stats (code review plus an API surface test).
- Only `net/` crosses the process boundary. Stations never touch `sim/` directly, even on the host.
- Station interfaces for all six stations exist from milestone 1 (`StationDef`: id, visible state fields, accepted commands), even where the UI is a placeholder (spec §9).

### 8.2 Repo layout (one Godot project, one repo)

```
bridge/                         # repo root = Godot project root
  project.godot  export_presets.cfg  .gdlintrc  Makefile (or justfile)
  addons/gdUnit4/  addons/VERSIONS.md
  sim/        core/ physics/ systems/ ai/ rules/
  director/   missions/
  net/        protocol/ server/ client/ discovery/ webserve/
  stations/   common/ helm/ weapons/ engineering/ science/ relay/ captain/ main_screen/
  input/      presentation/ (ships/ shaders/ vfx/ hud/)  audio/ (voice_bus.gd, alerts/)
  app/        main.tscn (client menu) · server_main.gd (headless entry) · cli args
  content/    ships/ weapons/ subsystems/ upgrades/ enemies/ missions/ dialogue/ i18n/
              schemas/*.schema.json   voices/LICENSES.json
  assets/     models/ textures/ sfx/ voice/ (generated, git-ignored) 
  tests/      unit/ sim/ pairs/ net/ golden/ visual/ (fixtures/ replays/ baselines/)
  tools/      godot-version · get-godot.sh · gate.sh · tts/ (render.py, pyproject+uv.lock)
              lint_arch.py · schema_check
  docs/       architecture.md · protocol.md · launch.md · provenance.md (EmptyEpsilon: reproduced/redesigned/omitted) · traceability.md (requirement→test)
  .github/workflows/ci.yml
```

---

## 9. Risks and proof-of-concept spikes

Each spike is small and time-boxed, produces a short report plus code in `spikes/` (later deleted or promoted), and has a pass/fail criterion.

| # | Risk | Likelihood / impact | Spike that retires it | Pass criterion |
|---|---|---|---|---|
| R0 | Pinned versions wrong or unavailable | L / M | **S0** Verify Godot 4.7.2 binary and template hashes, gdUnit4 tag compatibility, gdtoolkit, Piper release | All download and run on fugaku |
| R1 | Headless agent workflow gaps (import cache, `.tscn` authoring without the editor, export without GUI) | M / H | **S1** Fresh clone, then `--import`, gdUnit4 run, Linux and Windows export, all from the CLI; measure CI job time on one Actions run | Green from a clean checkout; CI ≤ 5 min |
| R2 | No visual verification without a desktop | M / M | **S2** Xvfb + opengl3 + llvmpipe screenshot of a toon-shaded ship and a UI panel; repeat 10× for pixel stability; compare against the NVIDIA GPU under Xvfb if it works | Stable within tolerance; under 30 s per shot |
| R3 | Browser client on tablets infeasible (no-thread build performance, audio unlock, memory, touch, WS from an `http://` LAN page) | M / M | **S3** Single-threaded web export of an Engineering panel, served by the in-server HTTP server, connected over WS on a real iPad/Android tablet (**owner step** to test on devices) | 30 fps UI, joins in < 10 s, touch works, audio plays after tap |
| R4 | WebSocket head-of-line stalls on busy Wi-Fi | L / M | **S4** 8 clients over Wi-Fi with 30 Hz snapshots and 2% induced loss (`tc netem`); measure p99 snapshot age | p99 < 150 ms |
| R5 | Newtonian 6DOF too hard or no fun to fly | H / H | **S5** Helm prototype: pure 6DOF vs assist modes, keyboard and controller; owner playtest (**owner step**) | Owner can intercept a target in < 60 s with assist |
| R6 | GDScript too slow for the simulation | M / H | **S6** Benchmark: 100 ships, 500 projectiles, swept collision, 60 Hz, headless, on 1 core | < 4 ms per tick (25% of budget) on fugaku; otherwise plan a GDExtension hot path |
| R7 | TTS quality, language coverage or voice licences unacceptable | M / H | **S7** Render 20 representative lines in each candidate language with Piper (2 voices each) and Kokoro (where available), plus eSpeak for the computer; licence audit table from MODEL_CARDs; RTF measurement; owner listens (**owner step**) | Owner approves ≥ 1 permissive voice per launch language |
| R8 | Fragment-concatenated dynamic lines sound bad, especially in gendered or inflected languages | M / M | Part of S7: numbers and names stitched in pt/de | Owner rates acceptable |
| R9 | Information leaks across stations (asymmetry broken) | M / M | Built into L3 tests from the first network PR | Per-station snapshot schema tests pass |
| R10 | LAN discovery blocked (AP isolation, firewall) | M / L | Part of S4 on the owner's real network; fallbacks are manual IP and QR | Join works by at least one route |
| R11 | Cartoon art with no artist and agents that can't see | H / M | **S8** Procedural or CC0 ship plus a toon shader with outline, rendered via S2; owner judges the screenshots (**owner step**) | Owner approves a style direction |
| R12 | GPL contamination (EmptyEpsilon code, espeak-ng linked in) | M / H | Policy plus `docs/provenance.md`; no spike. Licence check in review | — |
| R13 | Cooperation tests (15 pairs) become brittle or meaningless | M / M | Write the pair test harness with the first pair (Engineering + Helm) in the first playable | Harness expresses "coop beats solo on metric X" in under 30 lines |
| R14 | CI minutes overrun | M / M | S1 measures; one job; local L4–L6 | ≤ 5 billed min per run |
| R15 | Engine upgrade breaks things mid-project | L / M | Pin; upgrade only by a dedicated PR running all local gates | — |

Suggested order: S0 → S1 → (S6 ∥ S5 ∥ S7 ∥ S2) → S4 → S3 → S8. S1, S6 and S5 gate the engine and simulation decisions; S7 gates TTS; S3 gates the browser client.

---

## 10. Decisions for the owner

Each question has one **Recommended** option.

**Engine and language**

1. **D1 Engine?** (a) **Godot 4.7.2 — Recommended**: MIT, headless-friendly, web export; weaker 3D tooling than Unity or Unreal. (b) Unity 6 LTS: best ecosystem; seat licences and painful headless activation. (c) Unreal 5: best networking and graphics; huge, slow, a poor fit for agents. (d) Bevy 0.19: pure code and testable; API churn and thin tooling.
2. **D2 Scripting language?** (a) **Typed GDScript — Recommended**: web export, zero build; slower hot loops. (b) C#: faster and strongly typed; no web export. (c) GDScript plus a C++/Rust GDExtension from the start: fast; per-platform builds before we know we need them.
3. **D3 Engine version policy?** (a) **Pin 4.7.2; upgrade by a deliberate PR only — Recommended**: stable; we miss fixes until we upgrade. (b) Auto-track patch releases via Renovate: fixes sooner; occasional regressions in CI. (c) Wait for 4.8: newer features; delays the start.
4. **D27 Renderer?** (a) **Compatibility everywhere — Recommended**: identical on web, desktop and llvmpipe tests, runs on weak hardware; fewer effects. (b) Forward+ on desktop and Compatibility on web: nicer desktop visuals; two looks to test. (c) Forward+ only: best effects; no web or software screenshots.

**Hosting and network**

5. **D4 Hosting model?** (a) **Host-and-play with the headless server as a child process — Recommended**: one binary, crash isolation; two processes to manage. (b) In-process listen server: simplest; host stalls or crashes affect everyone. (c) Dedicated machine only: cleanest; needs spare hardware.
6. **D5 Browser station clients for tablets and phones?** (a) **Desktop clients for the first playable, protocol web-ready, browser client after spike S3 — Recommended**: no early cost; tablets come later. (b) Browser clients in the first playable: tablets sooner; adds web risk to the critical path. (c) Never: simplest; no tablet stations.
7. **D6 Transport?** (a) **WebSocket for all clients — Recommended**: one code path, browser-ready; no unreliable channel (fine on LAN). (b) ENet only: UDP-ideal; rules out browsers. (c) ENet for desktop plus WebSocket for web: best of both; two transports and a bridge.
8. **D7 Sync mechanism?** (a) **Custom protocol: commands up, filtered snapshots plus events down — Recommended**: testable, enforces asymmetry; more code. (b) Godot RPC plus MultiplayerSynchronizer: quick start; couples the simulation to scenes and makes per-station filtering hard.
9. **D8 Tick rates?** (a) **Simulation 60 Hz, snapshots 30 Hz — Recommended**: stable physics, smooth enough with interpolation. (b) 30/30: half the CPU; less stable fast projectiles. (c) 120/60: smoother; 2× CPU and bandwidth for little gain.
10. **D9 Maximum connections per session?** (a) **8 (6 stations plus main screen plus a spare) — Recommended**: covers the spec; sizes tests. (b) 6: matches stations exactly; no main-screen viewer. (c) 16 with spectators: future-proof; more load testing.
11. **D10 Joining?** (a) **UDP broadcast discovery plus manual IP plus QR/URL for browsers — Recommended**: works in most rooms; a little more code. (b) Manual IP only: trivial; poor UX. (c) mDNS: standard; extra work in Godot.
12. **D28 Station-to-client mapping?** (a) **Any client may hold any set of free stations — Recommended**: supports "combinable" stations and small crews; a more complex UI. (b) Exactly one station per client: simple; needs more devices.
13. **D29 Reconnect and late join?** (a) **Allow rejoin to a station mid-run from a full snapshot — Recommended**: robust to Wi-Fi drops; resync code. (b) Lobby-only joining: simpler; a dropped tablet is out for the run.

**Simulation**

14. **D11 Physics?** (a) **Custom 6DOF integrator and simple collision in GDScript — Recommended**: testable, transparent; we maintain it. (b) Godot Jolt on the server: robust solver; hard to unit test and less transparent. (c) Custom dynamics plus Godot collision queries: less collision code; ties the simulation to the SceneTree.
15. **D12 Flight assist?** (a) **Optional, visible assist modes using real thrust within ship limits — Recommended**: playable and honest; extra controller code. (b) Pure manual 6DOF: purist; likely too hard. (c) Always-on assist: easiest; hides Newtonian play and the Engineering + Helm trade-off.

**TTS and audio**

16. **D13 TTS engine?** (a) **Piper, pre-rendered at build time — Recommended**: good quality, about 40 languages, no GPL in the shipped game; dynamic lines need fragments. (b) Kokoro, pre-rendered: better English; 8 languages, slower renders. (c) Runtime Piper sidecar: any text at runtime; ships a GPL binary, CPU spikes on the host. (d) OS voices via Godot: zero work; quality and languages vary per machine.
17. **D14 Dynamic lines (names, numbers)?** (a) **Fragment concatenation from pre-rendered clips — Recommended**: offline and consistent; seams are audible in some languages. (b) Runtime synthesis on the host: natural; GPL and latency concerns. (c) Text-only for dynamic parts: simplest; less immersive.
18. **D15 Launch languages?** (a) **English only for the first playable; add languages after S7 — Recommended**: no early translation cost. (b) English plus Portuguese: owner-relevant; doubles the line work early. (c) English plus 3 major European languages: broad; large voice and licence audit.
19. **D16 Ship-computer voice?** (a) **Robotic eSpeak NG for the computer, Piper for people — Recommended**: retro style and clearly distinguishable alerts; robotic may grate. (b) Piper for everything: uniform quality; the computer is less distinctive. (c) Decide after hearing S7: informed; the decision waits.
20. **D17 Project licence and GPL tolerance?** (a) **Keep the shipped game free of GPL code (GPL tools only at build time; no EmptyEpsilon code, only ideas) — Recommended**: any future licence stays open; we reimplement rather than copy. (b) Make the game GPL-3.0 open source: can use Piper or eSpeak at runtime and maybe EmptyEpsilon code (if GPL-2.0-or-later); the game must stay open source. (c) Decide later: no cost now; risk of rework if GPL code slips in.

**Content**

21. **D18 Definition format?** (a) **JSON plus JSON Schema — Recommended**: easy for agents, validated in milliseconds outside the engine; no comments. (b) Godot `.tres` resources: typed and editor-friendly; Godot-only, hard for the build tools. (c) YAML or TOML via an addon: comments; extra dependency and typing traps.
22. **D19 Scenario authoring?** (a) **Declarative JSON component graph with a fixed condition and action vocabulary, plus a director picking components — Recommended**: validatable, branch-testable; new logic needs code. (b) GDScript scenario scripts: flexible; hard to validate, room for hidden manipulation. (c) Lua, EmptyEpsilon-like: familiar to EmptyEpsilon authors; GDExtension and sandboxing cost.
23. **D20 Dialogue format?** (a) **JSON dialogue trees in the same content system — Recommended**: one source for UI, subtitles and TTS; less pleasant to write by hand. (b) Dialogue Manager addon (`.dialogue`): nice writing format; a second format to feed TTS. (c) Yarn or Ink: industry tools; need C#.
24. **D21 Asset approach?** (a) **Procedural or primitive meshes plus CC0 packs (e.g. Kenney, Quaternius) with a toon shader — Recommended**: free, agent-producible; generic look until refined. (b) Blender headless Python scripts producing glTF: more distinctive; slower iteration. (c) Commission an artist: best look; cost and dependency.

**Testing, CI and platforms**

25. **D22 Test framework?** (a) **gdUnit4 — Recommended**: scene runner, mocks, JUnit; heavier. (b) GUT: simpler; fewer features.
26. **D23 CI scope?** (a) **One job on ready PRs: lint, unit, simulation and in-process net tests; visual, multi-process and export tests local on fugaku — Recommended**: about 4–5 billed min per run; relies on the local gates. (b) Also exports on every PR: catches export breakage; about 2× minutes. (c) Everything local, CI only on main: cheapest; no PR guard.
27. **D24 Screenshot tests?** (a) **Software GL (llvmpipe) under Xvfb on fugaku, tolerant diffs — Recommended**: reproducible and GPU-free; doesn't catch GPU-specific bugs. (b) None, owner reviews screenshots manually: no maintenance; regressions slip. (c) GPU rendering on fugaku: realistic; flaky under a headless X server.
28. **D25 Repo structure?** (a) **One repo, one Godot project, the simulation as a pure `sim/` folder with lint-enforced boundaries — Recommended**: simple; discipline enforced by a script. (b) A separate simulation library repo: hard boundary; cross-repo PRs violate the one-PR-per-issue flow.
29. **D26 Target platforms for v1?** (a) **Linux plus Windows desktop — Recommended**: cross-built from fugaku; macOS later. (b) Plus macOS: wider reach; signing and notarisation, and no Mac to test on. (c) Plus native Android: tablets natively; mobile export and testing overhead (the browser route may suffice).
30. **D30 Controller support in the first playable?** (a) **Keyboard and mouse plus one standard gamepad profile for Helm — Recommended**: covers the cooperation loop; other stations stay mouse-first. (b) Keyboard and mouse only: fastest; controller later. (c) Full controller support for all stations: complete; heavy UI work early.

Count: **30 decision questions.**

---

## Sources

- [Godot download page (4.7.2 stable, 2026-08-18)](https://godotengine.org/download/linux/)
- [Godot 4.7.2 archive](https://godotengine.org/download/archive/4.7.2-stable/)
- [Godot 4.6 release notes (Jolt default)](https://godotengine.org/releases/4.6/)
- [Godot 4.6.2 maintenance release](https://godotengine.org/article/maintenance-release-godot-4-6-2/)
- [Godot controllers docs (SDL3 since 4.5)](https://docs.godotengine.org/en/latest/tutorials/inputs/controllers_gamepads_joysticks.html)
- [Godot C# basics (no C# web export)](https://docs.godotengine.org/fr/4.x/tutorials/scripting/c_sharp/c_sharp_basics.html)
- [Forum: C# web export still unsupported on 4.7](https://forum.godotengine.org/t/is-there-an-update-on-exporting-c-projects-to-web/128821)
- [Godot text-to-speech docs](https://docs.godotengine.org/en/4.1/tutorials/audio/text_to_speech.html)
- [Godot 4 `--headless` can't render](https://ask.godotengine.org/150510/godot-headless-not-same-godot-window-cant-render-the-backend)
- [gdUnit4Net Linux CI discussion](https://github.com/godot-gdunit-labs/gdUnit4Net/discussions/350)
- [gdUnit4 overview (v6.1.3)](https://dev.co/testing/open-source/gdunit4)
- [Piper (OHF-Voice/piper1-gpl) releases](https://github.com/OHF-Voice/piper1-gpl/releases)
- [Piper review (licence change, voice MODEL_CARDs)](https://www.promptquorum.com/power-local-llm/piper-tts-review)
- [Kokoro ONNX model card](https://huggingface.co/suryatmodulus/kokoro-82M-onnx-opt)
- [Kokoro voices and languages](https://tts.ai/voices/kokoro/?lang=ja)
- [sherpa-onnx releases](https://github.com/k2-fsa/sherpa-onnx/releases)
- [Bevy 0.19](https://bevy.org/news/bevy-0-19/)
- [Unity vs Unreal vs Godot 2026 (secondary)](https://tech-insider.org/unity-vs-unreal-vs-godot-2026/)
- [Unity after the runtime fee (secondary)](https://www.strayspark.studio/blog/unity-engine-2026-state-comeback-runtime-fee-aftermath)
