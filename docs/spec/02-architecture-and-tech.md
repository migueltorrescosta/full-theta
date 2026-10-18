# 2. Architecture and technology

## 2.1 Stack

| Concern | Choice | Decision |
|---|---|---|
| Engine | Godot 4.7.2, pinned; upgrades only by a dedicated PR | D5, D70 |
| Language | Typed GDScript (web export possible, no download for browser stations) | D5 |
| Renderer | Compatibility renderer on every platform | D70 |
| Topology | One authoritative headless server process per session | D7 |
| Transport | Custom protocol over WebSocket for every client | D8, D70 |
| Rates | Simulation 60 Hz fixed step; snapshots 30 Hz | D70 |
| Physics | Custom 6DOF integrator, simple collision shapes, no engine physics in the simulation | D70 |
| Randomness | Seeded RNG per subsystem; reproducible runs from seed plus command log | D70 |
| Tests | gdUnit4 headless; screenshot tests on fugaku with software GL | D70 |
| Repo | One repo, one Godot project, lint-enforced pure `sim/` folder | D70 |
| Prediction | None at first; clients interpolate snapshots | D70 |

## 2.2 Modules

```
content (.tres defs, dialogue JSON) --> sim/ (pure, no SceneTree, no I/O, seeded)
                                         ^  director/ + scenarios (Scenario API only)
                commands                 |            state views + events
net/ (protocol, codec, session, per-station view filter, discovery, web static server)
        ^ commands                        | replicated state + events
input/ (device -> intent) --> stations/ (helm, weapons, engineering, science,
                               relay, comms, captain, main_screen) --> presentation/, audio/
```

Dependency rules: `sim/`, `director/` and scenarios depend only on themselves and content definitions; only `net/` crosses the process boundary; stations never touch `sim/` directly, even on the host.

## 2.3 Requirements

- **FT-ARC-001** The project shall pin Godot 4.7.2 and change the engine version only in a dedicated PR. (D70)
- **FT-ARC-002** All game code shall be typed GDScript. (D5)
- **FT-ARC-003** Every client and the server shall use the Compatibility renderer. (D70)
- **FT-ARC-004** Each session shall run exactly one authoritative simulation. (v0.3 §3, D7)
- **FT-ARC-005** Clients shall not simulate gameplay; they shall send commands and render received state and events. (v0.3 §3, D70)
- **FT-ARC-006** The simulation shall step at a fixed 60 Hz driven by its own accumulator, not by engine physics callbacks. (D70)
- **FT-ARC-007** The simulation shall use a custom 6DOF integrator and shall not use Godot physics bodies. (D70)
- **FT-ARC-008** Every random draw in the simulation shall come from a seeded RNG, so a seed plus a command log reproduces a run on the same build and platform. (D70)
- **FT-ARC-009** Simulation iteration order shall be stable (entities ordered by id). (D70)
- **FT-ARC-010** Code under `sim/` and `director/` shall not extend Node, access the SceneTree or perform I/O, enforced by a lint gate. (D70)
- **FT-ARC-011** Station code shall reach simulation state only through `net/`, including on the host machine. (D70)
- **FT-ARC-012** All simulation state shall be keyed by ship id and faction. (D21, D72)
- **FT-ARC-013** Each faction shall hold its own contact knowledge (detection, scans, tracks). (D21)
- **FT-ARC-014** Every station, including those without a finished UI, shall have a station definition (id, visible state fields, accepted commands) from milestone 1. (v0.3 §9)
- **FT-ARC-015** Clients shall not use client-side prediction until a measured need is approved. (D70)
- **FT-ARC-016** The director shall act only through the public Scenario API and shall hold no write access to combat stats or physics. (v0.3 §5, D64)
- **FT-ARC-017** macOS builds shall be produced, with signing and notarisation tracked as a release risk. (D9)
- **FT-ARC-018** Allied ships (every ship in a co-op session, every ship of one PvP team) shall belong to one faction sharing contact knowledge, callsigns and reputation; marks and pings stay per ship. (D21, D78, D82)
- **FT-ARC-019** Runtime Piper synthesis shall run in the server process on the host, never on clients. (D85)

## 2.4 Risks and spikes

From tech.md §9, updated for the decisions. Each spike is time-boxed and has a pass criterion.

| Id | Risk | Spike | Pass criterion |
|---|---|---|---|
| R0 | Pinned versions unavailable | S0: verify Godot 4.7.2 binaries and templates, gdUnit4 tag, gdtoolkit, Piper release | All run on fugaku |
| R1 | Headless agent workflow gaps | S1: fresh clone, import, tests, exports from the CLI; time one CI run | Green from a clean checkout |
| R2 | No visual verification without a desktop | S2: Xvfb + llvmpipe screenshot of a toon ship and a UI panel, 10 repeats | Stable within tolerance, < 30 s per shot |
| R3 | Browser stations on tablets | S3: single-threaded web export of one station over WS from an `http://` LAN page (owner tests devices) | 30 fps UI, join < 10 s, touch and audio work |
| R4 | WebSocket stalls on busy Wi-Fi | S4: 8 clients, 30 Hz snapshots, 2 % induced loss | p99 snapshot age < 150 ms |
| R5 | 6DOF too hard or no fun | S5: Helm prototype with assist and decoupled modes (owner playtest) | Owner intercepts a target in < 60 s with assist |
| R6 | GDScript too slow | S6: 100 ships, 500 projectiles, 60 Hz headless on 1 core | < 4 ms per tick |
| R7 | TTS quality or voice licences | S7: Piper lines in en, pt_PT, it; voice licence audit; robotic filter; runtime latency (owner listens) | ≥ 1 approved voice per language |
| R8 | Runtime Piper latency on the host | S7b: runtime synthesis on the host server, clip streamed to one client, measured per line (D85) | Line audible < 1 s after the event |
| R9 | Information leaks across stations or factions | L3 tests from the first network PR | Snapshot schema tests pass |
| R10 | LAN discovery blocked | Part of S4 on the owner's network | Join works by at least one route |
| R11 | Cartoon art without an artist | S8: procedural/CC0 ship with toon shader via S2 (owner judges) | Owner approves a style |
| R12 | Licence contamination (EE GPL-2.0-only, proprietary EE packs) | Provenance policy; review check | — |
| R13 | 15 pair tests brittle | Pair harness built with P1 in milestone 1 | "co-op beats solo" in < 30 lines |
| R14 | macOS untested | Owner step per release | — |
| R15 | 64 connections × 6 ships load | S9: 6 ships, 36 crew, 28 viewers simulated on loopback | Server tick < 8 ms, p99 snapshot age < 150 ms |
