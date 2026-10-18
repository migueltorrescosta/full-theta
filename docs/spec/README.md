# Full Theta specification v0.4

Repo: migueltorrescosta/full-theta (GPL-3.0). Engine: Godot 4.7.2, typed GDScript. Date: 2026-10-19.

v0.4 amends spec v0.3 with the owner decisions D1–D89 (`decisions.md`; later decisions supersede earlier ones). Where v0.3 conflicts with a decision, the decision wins and the change is listed below.

## How to use this spec

- Load only the sections you need; each file stands alone.
- Every normative requirement is one line: `**FT-AREA-NNN** ... shall ... (justification)`. Justifications cite a decision (`D39`), the original spec (`v0.3 §5`), a pair (`P1`) or a design document section.
- Issues, PRs and tests reference FT ids; `docs/traceability.md` in the repo maps each id to its tests (FT-TST-015).
- Requirement ids are stable: never renumber; retire an id by striking it through and marking it "Removed (Dnn)" with its successor; never reuse it. Counts below are active requirements, with removed ids in brackets.
- Open questions (§14) list what the decisions leave unresolved; don't resolve them silently.

## Index

| File | Content | Ids | Count |
|---|---|---|---|
| [01-objective-and-scope](01-objective-and-scope.md) | Multi-ship co-op and PvP, crew sizes, 64 connections, scope | FT-GEN | 14 |
| [02-architecture-and-tech](02-architecture-and-tech.md) | Stack, modules, dependency rules, risks and spikes | FT-ARC | 19 |
| [03-networking-and-sessions](03-networking-and-sessions.md) | Hosting, protocol, lobby, 15 joint views, coverage check, claims, reconnect, disconnect pause | FT-NET | 36 |
| [04-simulation-flight-combat-damage](04-simulation-flight-combat-damage.md) | 6DOF flight, weapons, shields, damage, repair, AI | FT-SIM | 33 (+1 removed) |
| [05-stations](05-stations.md) | Common UI and alert level, Helm, Weapons, Engineering, Science (scan, hack), Relay (mark sending), Comms (card board), Captain, main screen, joint views | FT-STN, HLM, WPN, ENG, SCI, RLY, COM, CPT, MSC, JNT | 79 |
| [06-spatial-language-and-radar](06-spatial-language-and-radar.md) | Callsigns, clock/height/range, marks, pings, sent marks, disc radar, frames | FT-SPA | 22 (+1 removed) |
| [07-cooperation-pairs](07-cooperation-pairs.md) | Shared systems, shortcut toggles and presets, 15 pairs with variants and tests | FT-PAIR | 19 (+1 removed) |
| [08-missions-director-progression-economy](08-missions-director-progression-economy.md) | Global map, sites and encounters, director, outcomes, PvP types, retreat, economy, slot modules | FT-MIS | 34 (+2 removed) |
| [09-audio-tts-languages](09-audio-tts-languages.md) | Piper, routing, voice bus, languages, visual style | FT-AUD | 18 |
| [10-content-and-data-formats](10-content-and-data-formats.md) | `.tres` definitions, dialogue JSON, GDScript scenarios | FT-DAT | 14 |
| [11-milestone-1](11-milestone-1.md) | First playable scope | FT-M1 | 16 |
| [12-testing-ci-and-traceability](12-testing-ci-and-traceability.md) | Test layers, CI, traceability | FT-TST | 18 |
| [13-licensing-and-provenance](13-licensing-and-provenance.md) | GPL-3.0, EE ideas only, reproduced/redesigned/omitted | FT-LIC | 8 |
| [14-open-questions](14-open-questions.md) | Q1–Q13 answered (D76–D89); new Q14–Q16, multiple choice with a recommendation | — | 0 |
| **Total** | | | **330 (+5 removed)** |

## Glossary

| Term | Meaning |
|---|---|
| Functional station | One of Helm, Weapons, Engineering, Science, Relay, Comms. All six must be covered to launch. |
| Captain | Optional, information-only seat that directs the main screen and places pings and marks. Never counts for coverage. |
| Viewer | A read-only main-screen connection. Counts toward the 64-connection cap. |
| Catalogue | The lobby list a player picks from: single stations, joint views, Captain, Viewer. |
| Joint view | A layout combining two functional stations on one screen, keeping every control of each (for example Tactical = Helm + Weapons); one per pair, 15 in all (D76). |
| Coverage | The condition that a ship's crew picks include every functional station, with at least 3 crew players. Enables Ready/Start. |
| Claim | A lock a player takes on a sub-control of a shared station (weapon mount, repair crew, probe, NPC conversation, scan/hack slot, Helm flight, Helm shield facing). |
| Callsign | Per-faction short name for a contact: allegiance letter (H, U, F, N) plus a number that never changes. |
| Clock / height / range | Spoken ship-relative direction: clock position in the deck plane, height word, range band (`H2 · 4 high · 2.3 km`). |
| Mark | One of up to 8 named world-anchored points per ship (Alpha–Hotel), free or attached to a contact. |
| Ping | A rate-limited 3 s pulse plus chime on every screen of the ship, pointing at an item. |
| Disc radar | Elite-style radar: deck-plane disc with elevation stems, range ring at the selected contact, optional side strip. |
| Ship frame / world frame | Radar orientation relative to the ship (crew stations) or to the scenario map's ecliptic (Relay, Captain maps). Helm's Level aligns them. |
| Request chip | A player-initiated typed request shown on another station; a shortcut toggle, off in the Hard preset. |
| Data shortcut | A share button or data link that puts one station's data on another station's screen; each is a toggle set before start, preset by difficulty (D84). |
| Pair (P1–P15) | One of the 15 pairs of functional stations and its cooperative mechanic. |
| PWR, COND, KNOW, MARK, STORY, CUE | The shared simulation systems that carry the pair mechanics. |
| Director | Server component that chooses and parameterises scenario components; never changes rules; logs every decision. |
| Run | One 20–40 minute playthrough of about 5 encounters; nothing persists after it. |
| Encounter | A self-contained situation (enemy wave, rescue, derelict, negotiation...) the director places or activates at a site, with its own triggers and outcome (D77). |
| Scenario map | The single global open 3D map of a scenario; no per-encounter maps (D77). |
| Site | A place on the scenario map where an encounter happens; seeded by the scenario or spawned by the director (D80). |
| Slot module | An upgrade fitted to a ship slot, with a trade-off; bought while docked via Comms (D86). |
| Faction | Owner of knowledge, callsigns and reputation; all state is keyed by ship and faction. Allied ships share one faction; marks stay per ship (D82). |
| EE | EmptyEpsilon, the reference game (GPL-2.0-only; ideas only). |

## Changes from v0.3

1. One shared spacecraft becomes up to 6 player ships with co-op and PvP designed in from the start; all state is keyed by ship and faction. (D11, D21)
2. Players per session: one cap of 64 connections including viewers; unlimited viewers within it. (D10, D22)
3. Six logical stations become six functional stations (Helm, Weapons, Engineering, Science, Relay, Comms) plus an optional Captain; Comms splits from Relay and takes all NPC text. (D53)
4. "Stations independently usable and combinable" becomes: minimum 3 players per ship; launch only when all six functional stations are covered; curated joint views picked from a catalogue; no solo or 2-player crews; no unstaffed "off" state or automation. (D12, D13 and D20 superseded by D19, D66, D67)
5. Shared stations use claims on sub-controls. (D18)
6. Captain becomes information only (main-screen director, pings, marks); the 5 Captain pairs are dropped and the 15 pairs are redesigned over the six functional stations. (D15, D23, D54, D55)
7. Pair "Science + Weapons: identify shield frequencies" becomes weak points and damage-type resistances; no frequency matching. (D28)
8. Relay no longer handles communications or hacking: Comms talks, Science hacks, Relay maps and launches probes. (D51–D53, D56)
9. Pair "Engineering + Relay: docking, repairs, resupply" moves to Engineering + Comms and is verbal only; Engineering + Relay becomes hazards and probe logistics. (D68)
10. Information sharing between stations depends on per-session shortcut toggles, preset by difficulty: all on for Easy, voice plus marks and pings on Hard. (D14, D69, D84)
11. Flight specified: 6DOF Newtonian, assist on by default with real thrust, decoupled toggle, face assist, Level. (D24, D42, D47)
12. Shields: Engineering sets power and focus tightness, Helm sets direction. (D16, D48)
13. Damage by hit location; repairs by crews with spare parts. (D26, D27)
14. Travel: impulse and jump drive within one global 3D map per scenario, no sector map; encounters happen at sites on it. (D29, D77, D80)
15. "Ship destruction resets all run-specific progression" becomes per-ship elimination; others continue. Win per co-op objective or PvP mode. (D30)
16. Death-risk target defined: 5–10 % per encounter for an average crew. (D31)
17. Permanent unlocks: none; nothing persists between runs. (D32)
18. Difficulty Easy/Normal/Hard chosen at start, no hidden stats. (D33)
19. Economy defined: credits, ammunition, propellant, spare parts, probes, per-faction reputation with random distributions; retreat and abandon allowed; friendly fire and collisions on. (D34, D36, D37)
20. Director decisions logged and shown in a debrief. (D35)
21. TTS: Piper, prerendered plus runtime synthesis; per-client routing; robotic filter for the ship computer; launch languages en, pt_PT, it; one language per session. (D38–D41, D71)
22. Engine evaluation closed: Godot 4.7.2, typed GDScript, Compatibility renderer, WebSocket protocol, 60/30 Hz, custom integrator, gdUnit4. (D5, D70)
23. Hosting: host-and-play headless child process; dedicated server with the same binary; LAN only; reconnect by token. (D6, D7, D70)
24. Scenario format: typed GDScript on a restricted Scenario API; definitions as `.tres`; dialogue JSON. (D64, D65)
25. Licence: GPL-3.0; EE (GPL-2.0-only) contributes ideas only; no EE compatibility; CC0 or procedural assets. (D2, D62, D63)
26. Platforms: Linux, Windows, macOS; browser stations after the first playable. (D8, D9)
27. Milestone 1: two clients become three clients covering all six stations through joint views; adds refresh-to-rejoin, ship+faction keying, a 2-ship PvP test and a dev all-stations flag. (D72)
28. v0.3 §12 outstanding decisions are resolved by D1–D89; §14 holds only questions found while applying them.

### v0.4 update for D76–D89 (answers to Q1–Q13)

29. Joint views: one per pair, all 15 in the lobby; M1 builds Tactical, Systems, Ops; the rest come in M2. FT-NET-032, FT-JNT-004. (D76, Q1)
30. Data shortcuts: individual toggles set before start; Easy/Normal/Hard are presets; Normal keeps chips, routes, lanes and hazard countdowns, voices weak points, track feeds and diagnosed causes, bands summaries. FT-PAIR-006 removed; FT-PAIR-017 to 020. (D84, Q2)
31. World: a single global map per scenario; encounters are situations at sites; sites seeded by the scenario and spawned by the director, logged. FT-SIM-008 and FT-MIS-002 removed; FT-SIM-034, FT-MIS-024 to 027. (D77, D80, Q3)
32. PvP: race, last ship standing and two-faction teams as distinct scenario types. FT-MIS-031 to 034. (D78, Q4)
33. Multi-ship difficulty: one difficulty per session, director budget per ship. FT-MIS-007 removed; FT-MIS-028, 029. (D81, Q5)
34. Allies share one faction (knowledge, callsigns, reputation); marks stay per ship; Relay sends marks that the receiving Relay must accept. FT-SPA-018 removed; FT-ARC-018, FT-SPA-020 to 023, FT-RLY-008, 009. (D82, Q6)
35. Eliminated crew: scenario-defined, by default viewers of a friendly ship's main screen. FT-MIS-030. (D79, Q7)
36. Disconnect: 10 s grace keeping settings and claims, then the whole universe pauses until coverage returns. FT-NET-033 to 036. (D83, Q8)
37. Runtime Piper runs on the host; clips stream to one client. FT-ARC-019, FT-AUD-018. (D85, Q9)
38. Main screen: Captain switches it; with no Captain, only Relay. FT-RLY-010, FT-MSC-005. (D88, Q10)
39. Alert level: any crew station sets it. FT-STN-008. (D89, Q11)
40. Comms: card board with conversation overlay replaces the provisional layout. FT-COM-008. (D87, Q12)
41. Upgrades: slot modules with trade-offs, bought while docked via Comms. FT-COM-009, FT-MIS-035, 036, FT-DAT-014. (D86, Q13)
