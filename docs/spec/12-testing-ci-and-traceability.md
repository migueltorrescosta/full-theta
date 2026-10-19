# 12. Testing, CI and traceability

## 12.1 Test layers

| Layer | Content | Where |
|---|---|---|
| L0 static | gdlint, gdformat check, script parse, `.tres` load gate, dialogue JSON Schema, architecture lint (`sim/` purity), scenario API lint | Local, CI |
| L1 unit | Physics, arcs, damage, power, voice-bus queue, protocol codec, loaders | Local, CI |
| L2 simulation | Scripted encounters, mission transitions, run reset, the 15 pair tests, golden replays, 2-ship PvP | Local, CI |
| L3 network in-process | Server and clients over loopback WebSocket: join, coverage, claims, filtering, reconnect | Local, CI |
| L4 network multi-process | Server plus headless clients, pinned to 2 cores | fugaku |
| L5 visual | Screenshots under Xvfb with llvmpipe, tolerant diffs, baselines tagged with the Mesa version | fugaku |
| L6 export | Linux, Windows, macOS exports and smoke run, including the bundled web export and Piper | fugaku, tags |

Every gate script first runs `godot --headless --import`.

## 12.2 Requirements

- **FT-TST-001** Tests shall use gdUnit4, vendored at a pinned tag. (D70)
- **FT-TST-002** L0–L3 shall run headless with no GPU. (D70)
- **FT-TST-003** Screenshot tests shall run on fugaku with software GL (llvmpipe under Xvfb) and tolerant image diffs. (D70)
- **FT-TST-004** CI shall run the full L0–L3 suite on every ready (non-draft) PR. (D70)
- **FT-TST-005** L4–L6 shall run locally on fugaku, and the PR body shall record which commit passed which gate. (D70)
- **FT-TST-006** Tests shall cover simulation, weapon geometry, damage, networking, mission transitions, run resets and all 15 pairs. (v0.3 §11)
- **FT-TST-007** Physics tests shall include analytic checks (constant thrust, momentum conservation, zero-input hold). (D24, D70)
- **FT-TST-008** Weapon-arc tests shall be table-driven, including edge-of-arc cases. (v0.3 §11)
- **FT-TST-009** Golden replays shall apply each command of a recorded log on its recorded tick and reproduce the final state within tolerance. (D70, plan review TECH-10)
- **FT-TST-010** Network tests shall assert that no snapshot contains a field forbidden to its station, difficulty or faction. (D14, D21, D69)
- **FT-TST-011** Network tests shall cover join, coverage check, claims, reconnect after disconnect, and the 64-connection limit. (D6, D18, D22, D67)
- **FT-TST-012** A test shall assert the director cannot write combat stats or physics state. (v0.3 §5, D64)
- **FT-TST-013** A 2-ship PvP simulation test shall assert per-faction knowledge separation and per-ship reset. (D21, D30, D72)
- **FT-TST-014** Multi-process network tests shall run pinned to 2 cores. (workspace rule)
- **FT-TST-015** The repository shall keep `docs/traceability.md` mapping every FT requirement id to its tests or to "manual". (v0.3 §11)
- **FT-TST-016** Each test shall name the FT ids it verifies. (v0.3 §11)
- **FT-TST-017** Each implementation issue shall list the FT ids it delivers. (v0.3 §11)
- **FT-TST-018** The planning agent shall produce a dependency-aware task DAG with explicit prerequisites, acceptance criteria and verification before broad implementation. (v0.3 §1, §11)
- **FT-TST-019** L6 shall serve and load each desktop package's bundled web export, and synthesise one line with its bundled Piper from the exported Linux and Windows builds. (plan review TECH-4)
- **FT-TST-020** Screenshot baselines shall record the Mesa and llvmpipe version, and L5 shall fail with "baseline environment changed" when it differs. (plan review TECH-11)
- **FT-TST-021** A Playwright smoke check of the web build shall take one screenshot of a touch layout and check it is not blank and shows the expected panel. (plan review TECH-11)
- **FT-TST-022** A headless batch of at least 200 encounters with scripted bot crews shall report the per-encounter loss rate for tuning. (D31, plan review CLASH-9)
