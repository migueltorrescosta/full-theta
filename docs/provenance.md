# Provenance

Full Theta is GPL-3.0. EmptyEpsilon (EE) is GPL-2.0-only, so it contributes ideas only: no EE source, script, text, data, shader or asset enters the repository (FT-LIC-002, FT-DAT-012). The PR template's review item checks this on every PR.

## Clean room

The EE reference clone stays outside the repository (FT-LIC-003): never clone, vendor or submodule it under this tree, and don't paste from it. Implementers work from `docs/spec/` and `docs/research/`, not from EE files.

## Third-party files

`content/provenance.json` lists every third-party asset, voice model and dependency with source, licence and attribution (FT-LIC-005). `tools/check_licences.py` (run by `gate.sh l0`) fails on a file under `assets/` or `addons/` that no entry covers by path prefix, and on art or sound that isn't CC0 (FT-LIC-006). The Python tools' transitive dependencies are pinned in `tools/uv.lock`; they run only at development time and never ship.

## Runtime Piper (GPL aggregation)

The host server synthesises speech at runtime with Piper (GPL-3.0-or-later), which carries eSpeak NG (GPL-3.0-or-later) and ONNX Runtime (MIT) (D38, D85, FT-ARC-019). The game doesn't link them: it starts Piper as a separate process and exchanges only text and PCM with it over a pipe (S7b, `tools/tts/piper_stream.py`). Shipping that program next to the game in one package is aggregation. Even read as one combined work, every part is GPL-3.0-compatible, and Full Theta is GPL-3.0 itself, so the licences agree either way. A release that ships Piper must still meet its terms: include its licence text, name the Piper and eSpeak NG versions, and offer or link their exact source alongside the game's (FT-LIC-008, TECH-4). Voice models are data with their own licences (FT-LIC-007, `docs/spikes/S7.md`).

## Release packages

Each release package ships the game (Godot, MIT), its web export, the standalone Piper with its eSpeak NG and ONNX Runtime, and the release voices (D140, D141). `tools/release/package.py` puts the GPL-3.0 text in `LICENSE`, every third-party licence text and `licenses/VOICES.md` (from the voice entries in `content/provenance.json`) in `licenses/`, and the source link and offer in `SOURCE.md`, which names the Piper and eSpeak NG versions. The release page carries the upstream source archives next to the packages (FT-LIC-008). Piper's is its release tag. For piper-phonemize and eSpeak NG, the commits are inferred from the build date (D140), and `SOURCE.md` says so and offers the source on request too. `tools/release/inspect_packages.py` checks all of it before a release is drafted (`docs/release.md`).

## Provenance review checklist

Run through it for every release and for any PR that adds a dependency, asset or voice (FT-LIC-004, FT-LIC-005):

- [ ] Every new file under `assets/` or `addons/` has an entry in `content/provenance.json` (`gate.sh l0` checks this).
- [ ] Every program or library a package ships, and every voice in the `release` list of `tools/tts/voices.json`, has an entry with source, licence and attribution. A release voice must also have passed the S7 audit (FT-LIC-007). `tools/tests/test_release.py` and the build check the voices.
- [ ] Art and sound are CC0 (FT-LIC-006, `gate.sh l0`).
- [ ] The EE mechanics table below matches spec §13.2. `tools/tests/test_release.py` compares them; when a mechanic's status changes, update both.
- [ ] The inspection passes for every package, so it holds the licence texts, `SOURCE.md` and `BUILD.json`.

## EE mechanics: reproduced, redesigned, omitted

Seeded from spec §13.2 (`docs/spec/13-licensing-and-provenance.md`). Keep this record current when a mechanic's status changes (FT-LIC-004).

| EE mechanic | Status in Full Theta |
|---|---|
| Server-authoritative simulation, thin station clients, typed commands | Reproduced as an idea |
| One client holding several stations (position bitmask) | Redesigned: curated joint-view catalogue plus coverage check (D67) |
| Shared stations, last writer wins | Redesigned: claims on sub-controls (D18) |
| Unstaffed stations left at defaults | Redesigned: launch blocked until all stations are covered (D19) |
| Curated combos (Tactical, Operations, Single Pilot) | Redesigned: complete joint views, no solo or 2-player play (D20, D66) |
| Power, heat, coolant per system | Redesigned: pips plus overcharge and heat |
| Repair crews in rooms | Redesigned: 3D cutaway, spare parts (D27) |
| Random system damage per hull hit | Redesigned: nearest-subsystem hit location (D26) |
| Scan ladder with slider minigame | Redesigned: confidence values, silhouette-alignment minigame (D58) |
| Hacking (lights-out, minesweeper) at Relay | Redesigned: node-route minigame at Science, aided by probes (D51, D56, D59) |
| Beam/shield frequencies | Omitted; weak points and damage-type resistances instead (D28) |
| Front/rear shield segments, Weapons toggles shields | Redesigned: one focus direction (Helm) with power and tightness (Engineering) (D16) |
| Beams auto-fire at the selected target | Redesigned: manual aim from turret cameras (D25, D49) |
| Missile types (homing, nuke, EMP, mine, HVLI) | Redesigned: projectiles, beams, missiles, torpedoes |
| 2D movement with velocity locked to heading | Omitted: 6DOF Newtonian flight with assist (D24) |
| Combat maneuver boost/strafe | Redesigned: Engineering + Helm boost (P1) |
| Warp and jump drives | Redesigned: jump drive within the scenario's single global 3D map, consuming propellant (D29, D34, D77) |
| Probes linked to Science | Reproduced, extended to hacking (D56) |
| Waypoints Relay to Helm | Reproduced as 3D routes and marks; route ribbon behind a shortcut toggle (D44, D69, D84) |
| Comms dialogue at Relay | Redesigned: separate Comms station (D53) |
| Reputation as currency | Redesigned: credits plus per-faction reputation with random distributions (D34) |
| Docking resupply | Reproduced, gated by Comms clearance (P5) |
| Per-faction scan state | Reproduced: all knowledge keyed by faction (D21) |
| PvP by scenario and faction | Redesigned: up to 6 ships, PvP in the architecture, three PvP scenario types (D11, D21, D78) |
| Alert levels | Reproduced; any crew station sets it (D89) |
| Self-destruct cross-station codes | Omitted (no co-sign mechanics, D57) |
| Captain with no station | Redesigned: optional information-only Captain director seat (D54) |
| Main screen with view switching | Reproduced: M-A default plus five views (D60) |
| Game Master | Omitted: director plus logged debrief (D35); debug console for development only |
| Lua scenarios and ship templates | Omitted: typed GDScript scenarios and `.tres` definitions (D64, D65) |
| AI orders and target scoring | Reproduced as a starting point |
| EE content compatibility | Omitted (D62) |
| Hardware/DMX, HTTP API, voice chat, master server | Omitted |
