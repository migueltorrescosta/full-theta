# 13. Licensing and provenance

## 13.1 Stance

Full Theta is GPL-3.0 (D2). EmptyEpsilon's LICENSE is GPL-2.0 with no "or later" grant, so EE code cannot be combined with a GPL-3.0 project: EE contributes ideas only, with provenance recorded (D2 note, D62). EE model packs (TurboSquid, CGTrader) are proprietary and never reused. Mechanics and rules as game design are not protected; we pick our own values because our physics differs. Piper (GPL-3.0) may run at runtime (D38). Assets are procedural or CC0 (D63).

Clean-room practice: the EE reference clone stays outside the repo; implementers work from the design documents, not EE files.

## 13.2 EE mechanics: reproduced, redesigned, omitted

Updated from emptyepsilon.md §6 for decisions D1–D89.

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

## 13.3 Requirements

- **FT-LIC-001** The project shall be licensed GPL-3.0, with a LICENSE file at the repository root. (D2)
- **FT-LIC-002** No EE source, script, text, data, shader or asset shall be copied or translated into the project. (D2 note, D62)
- **FT-LIC-003** The EE reference clone shall stay outside the repository. (D2 note)
- **FT-LIC-004** `docs/provenance.md` shall keep the reproduced/redesigned/omitted record in §13.2 current. (v0.3 §10)
- **FT-LIC-005** A provenance manifest shall list every third-party asset, voice model and dependency with source, licence and attribution. (D63)
- **FT-LIC-006** Only CC0 art and sound packs shall be shipped unless a later decision allows otherwise. (D63)
- **FT-LIC-007** Every Piper voice shall be audited from its model card, and non-commercial or unclear voices shall not ship; a voice fine-tuned from a non-commercial or research-only checkpoint (lessac, ryan) counts as unclear. (D38, D105)
- **FT-LIC-008** Release packages shall include the GPL-3.0 text and a source offer or source link. (D2)
