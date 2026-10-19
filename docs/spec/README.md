# Full Theta specification v0.5

Repo: migueltorrescosta/full-theta (GPL-3.0). Engine: Godot 4.7.2, typed GDScript. Date: 2026-10-19.

v0.4 amended spec v0.3 with the owner decisions D1–D89; v0.5 applies D90–D125, including the plan review (`../research/plan-review/README.md`). Later decisions supersede earlier ones (`decisions.md`). Where v0.3 conflicts with a decision, the decision wins and the change is listed below.

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
| [02-architecture-and-tech](02-architecture-and-tech.md) | Stack, modules, dependency rules, risks and spikes | FT-ARC | 22 |
| [03-networking-and-sessions](03-networking-and-sessions.md) | Hosting, protocol, lobby, 15 joint views, coverage check, claims, reconnect, disconnect pause | FT-NET | 46 |
| [04-simulation-flight-combat-damage](04-simulation-flight-combat-damage.md) | 6DOF flight, weapons, shields, damage, repair, AI | FT-SIM | 37 (+1 removed) |
| [05-stations](05-stations.md) | Common UI and alert level, Helm, Weapons, Engineering, Science (scan, hack), Relay (mark sending), Comms (card board), Captain, main screen, joint views | FT-STN, HLM, WPN, ENG, SCI, RLY, COM, CPT, MSC, JNT | 106 |
| [06-spatial-language-and-radar](06-spatial-language-and-radar.md) | Callsigns, clock/height/range, marks, pings, sent marks, disc radar, frames | FT-SPA | 30 (+1 removed) |
| [07-cooperation-pairs](07-cooperation-pairs.md) | Shared systems, shortcut toggles and presets, 15 pairs with variants and tests | FT-PAIR | 22 (+1 removed) |
| [08-missions-director-progression-economy](08-missions-director-progression-economy.md) | Global map, sites and encounters, director, outcomes, PvP types, retreat, economy, slot modules | FT-MIS | 40 (+2 removed) |
| [09-audio-tts-languages](09-audio-tts-languages.md) | Piper, routing, voice bus, languages, visual style | FT-AUD | 19 |
| [10-content-and-data-formats](10-content-and-data-formats.md) | `.tres` definitions, dialogue JSON, GDScript scenarios | FT-DAT | 14 |
| [11-milestone-1](11-milestone-1.md) | First playable scope | FT-M1 | 21 |
| [12-testing-ci-and-traceability](12-testing-ci-and-traceability.md) | Test layers, CI, traceability | FT-TST | 22 |
| [13-licensing-and-provenance](13-licensing-and-provenance.md) | GPL-3.0, EE ideas only, reproduced/redesigned/omitted | FT-LIC | 8 |
| [14-open-questions](14-open-questions.md) | None open: Q1–Q16 answered (D76–D92); plan review answered by D95–D102 | — | 0 |
| **Total** | | | **401 (+5 removed)** |

## Glossary

| Term | Meaning |
|---|---|
| Functional station | One of Helm, Weapons, Engineering, Science, Relay, Comms. All six must be covered to launch. |
| Captain | Optional, information-only seat that directs the main screen and places pings and marks. Never counts for coverage. |
| Viewer | A read-only main-screen connection. Counts toward the 64-connection cap. |
| Catalogue | The lobby list a player picks from: single stations, joint views, Captain, Viewer. |
| Joint view | A layout combining two functional stations on one screen, every control reachable, one panel focused at a time (for example Tactical = Helm + Weapons); one per pair, 15 in all (D76, D95). |
| Coverage | The condition that a ship's crew picks include every functional station, with at least 3 crew players. Enables Ready/Start. |
| Claim | A lock a player takes on a sub-control of a shared station (weapon mount, repair crew, probe, NPC conversation, scan/hack slot, Helm flight, Helm shield facing). |
| Callsign | Per-faction short name for a contact: allegiance letter (H, U, F, N) plus a number that never changes. |
| Clock / height / range | Spoken ship-relative direction: clock position in the deck plane, height word, range band (`H2 · 4 high · mid`; D114). |
| Mark | One of up to 8 named world-anchored points per ship (Alpha–Hotel), free or attached to a contact. |
| Ping | A rate-limited 3 s pulse plus chime on every screen of the ship, pointing at an item. |
| Disc radar | Elite-style radar: deck-plane disc with elevation stems, range ring at the selected contact, optional side strip. |
| Ship frame | Orientation relative to the ship: deck plane, bow at 12. Every radar and callout uses it; Relay, Captain maps and the tactical view may centre it on a selected mark, site or contact. Space has no world-fixed up (D124). |
| Request chip | A player-initiated typed request shown on another station; a shortcut toggle, off in the Hard preset. |
| Data shortcut | A share button or data link that puts one station's data on another station's screen; each is a toggle set before start, preset by difficulty (D84). |
| Pair (P1–P15) | One of the 15 pairs of functional stations and its cooperative mechanic. |
| PWR, COND, KNOW, MARK, STORY, CUE | The shared simulation systems that carry the pair mechanics. |
| Director | Server component that chooses and parameterises scenario components; never changes rules; logs every decision. |
| Run | One 20–40 minute playthrough of about 5 encounters; nothing persists after it. |
| Encounter | A self-contained situation (enemy wave, rescue, derelict, negotiation...) the director places or activates at a site, with its own triggers and outcome (D77). |
| Scenario map | The single global open 3D map of a scenario; no per-encounter maps (D77). |
| Site | A named place on the scenario map where an encounter happens; seeded by the scenario or spawned by the director (D80). Positions are site-local, each site a cube that wraps on all three axes with period P, and site names are a callout layer outside the 8 marks (D98, D124). |
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

## Changes from v0.4 (v0.5, plan review)

The plan review (`../research/plan-review/README.md`) found 60 issues, merged into enhancements E1–E14; the owner answered its questions with D95–D102. Ids added, changed and removed are listed per file in `../research/plan-review/spec-changes.md`; counts above are current.

42. Joint views are modal; one common-actions table and an always-live set; station bindings are the same in every view; controller Helm can select, Level, decouple and all-stop. FT-STN-009, FT-JNT-001, 002, 005–008, FT-HLM-017. (D95, E1)
43. The pause has an exit: coverage counts ships in play; abandon a ship; cross-ship takeover; conditional claim restore; keep-awake tablets; the host rejoins its orphaned server. FT-NET-003, 026, 033–035, 041–043, 046. (D96, E2)
44. Flight assist holds rotation, drift and speed; all-stop and hold-to-approach; height words are ship frame, "up N" is world frame; Level rolls first. FT-SIM-004, 036, 037, FT-HLM-007, 014, 015, FT-SPA-026. (D97, E3)
45. Site-local positions, named sites, jump to the selected site or mark. FT-SIM-034, 035, FT-HLM-016, FT-SPA-027, FT-MIS-026. (D98, E4)
46. Spikes test flight aids, callouts, backpressure, bandwidth, Piper load and far-from-origin precision; the integrator is exact for constant thrust; commands are logged with their tick. §2.4, FT-NET-037–040, FT-SIM-038, FT-ARC-008, FT-TST-009. (E5)
47. `shared/` and `scenarios/` folders, class_name-aware lint, read-only definitions, a Scenario API of ids and copies. FT-ARC-010, 016, 020, 021, FT-DAT-006, 009. (E6)
48. Milestone 1 builds marks, pings and Relay's read-out, load tags, the controls overlay and tooltips; the playtest rotates seats. FT-M1-003, 006, 017–021, FT-STN-015. (D99, E7)
49. Joint views take the union of their stations' data and say which pair they make solo. FT-JNT-005, 006. (E8)
50. One ownership rule for shared stations; mark overflow; the Captain fills empty mark slots; one Captain per ship; module fitting; pair verbs in station lists. FT-NET-016, 022, 044, 045, FT-STN-010, FT-SPA-012, 013, 022, FT-ENG-008, FT-WPN-008, FT-RLY-011, FT-MIS-036. (E9)
51. Hard keeps pairs playable: scan positions and hazards outside the cap, marks on subsystems, seven request chips in data, same-room speech, a silent "copy". FT-SPA-014, 028, 029, 031, FT-PAIR-008, 021. (E10)
52. Onboarding and accessibility: controls overlay, first-run tooltips, Shakedown training, co-op host pause, UI scale, hold-to-toggle, letter and shape encoding, Easy lobby default, scaling minigames. FT-STN-006, 011–014, 016, FT-SCI-012, 014–016, FT-MIS-039, 040, FT-PAIR-012. (D100, E11)
53. Cooperation is verified: a minimum gain per pair, per-pair event counts, three named plays with end-to-end tests, a hack-window floor, P12 tested by its reverse flow, bot batches for death risk, an Easy target for first crews. FT-PAIR-010, 013, 015, 019, 022, 023, FT-MIS-009, 010, 037, 038, FT-TST-022. (E12)
54. Captain status view and read-only chips and cards; a Comms beat per hostile encounter; allied contract flags; world-stable turret aim, a horizon-stabilised main screen and a comfort toggle; radar zoom. FT-CPT-004, 005, FT-MSC-001, 005, 006, FT-MIS-041, 042, FT-WPN-005, 009, FT-STN-017, FT-SPA-003, 024, 025. (E13)
55. Runtime Piper pre-synthesises the closed set at Start. FT-ARC-019, FT-AUD-003, 015, 018, 019. (D101)
56. Release packages carry the web export and Piper; baselines record the Mesa version; D90–D94 are written into the spec. FT-ARC-017, 022, FT-TST-019–021, §7.2, FT-MIS-028, 030, FT-PAIR-017, 018. (E14)

### v0.5 update for D103 (#2)

57. Module dependencies follow the API-boundary diagram; the Scenario API lives in `sim/api/`, and the architecture lint enforces FT-DAT-007 from #2. §2.2, FT-ARC-010, FT-DAT-007. (D103)

### v0.5 update for D104–D111 (#3)

58. Site-local offsets are three 64-bit floats, measured by spike S6; R6's budget is mean and p99. §4.1, FT-SIM-035, R6. (D104)
59. Voices fine-tuned from lessac or ryan are unclear; medium voices for runtime; a clean pt_PT voice is trained (#16). §9.1, FT-LIC-007, FT-AUD-019. (D105)
60. The stall trigger for a client is fixed at more than 15 unacknowledged snapshots, a failed send or 256 KiB queued. FT-NET-037. (D106)
61. Art moves from toon to semi-realistic PBR-style procedural art with variant B's palette. §9.5, FT-AUD-016, R11. (D107)
62. Browser stations run from plain HTTP through a patched shell and audio guard; grace stays 10 s; keep-awake by a muted video. FT-NET-030, 033, 046. (D108)
63. S9's quiet-host tick counts as the pass for R15; #11 re-verifies. R15. (D109)
64. Free-text voice bursts beyond 4 queued lines show subtitles only. FT-AUD-015, R15. (D110)
65. Snapshots are encoded and sent off the sim thread (amends D109). FT-NET-040, R15. (D111)

### v0.5 update for D112–D123 (#5)

66. A faction identifies a contact within one of its ships' identify range. §6.1, FT-SPA-001. (D112)
67. Grid squares run A… along +X and 1… along +Z from a scenario corner; layers are rounded and omitted at 0. §6.1, FT-SPA-006, FT-SPA-026. (D113)
68. Chips show the range band, not the exact range. §6.1, FT-SPA-003. (D114)
69. A repair job takes its parts at dispatch and is refused without enough parts; crews are numbered. §4.4, FT-SIM-024. (D115)
70. Energy past the shields is split between the nearest subsystem (a per-ship share) and the hull. §4.4, FT-SIM-020. (D116)
71. Data thrust limits are the nominal envelope; overcharge and a one-press boost reach 1.5 times them. §4.4, FT-SIM-006. (D117)
72. Shield tightness runs from an even spread (the spawn value) to a tight lobe; shields absorb collisions too. §4.3, FT-SIM-018, FT-SIM-019. (D118)
73. Collisions: restitution 0.2, energy lost split half to each ship, warning 5 s ahead within 500 m. §4.1, FT-SIM-009, FT-SIM-010. (D119)
74. An enemy has retreated once in retreat and undetected by every hostile ship. §4.5, §8.3, FT-M1-012, FT-SIM-027. (D120)
75. Pair gain is the share of the solo value saved; P1's `pair_min_gain` is 0.2. §7.4, FT-PAIR-015. (D121)
76. The command log records each crew or server command (for example a ship reset) with its result. FT-ARC-008. (D122)
77. Hit energy a subsystem can't absorb passes to the next-nearest live subsystem, then the hull. §4.4, FT-SIM-020. (D123)

### v0.5 update for D124 (#5)

78. Each site wraps on all three axes with period P from scenario data (default 200 km, at least 4 times the longest sensing or radar range); offsets wrap after each step and differences use the minimum image, replacing the 200 km bound. §4.1, FT-SIM-035. (D124)
79. Level becomes Align: roll the selected item into the pitch plane above the bow, a second press faces it. §5.1, FT-HLM-007, 017, FT-NET-045, R5. (D124)
80. No privileged up: grid squares and altitude layers are retired; points are said relative to a mark or site; radars use the ship frame, optionally centred on a selected reference. §6.1, §6.2, FT-SPA-006, 010, 026. (D124)
81. Relay's map is a freely rotatable 3D map of the wrapping cube; marks are placed on the view plane with depth on Shift+drag. §5.5, §7.4 P4, FT-RLY-001, 002. (D124)
82. Turret roll, main-screen stabilisation and the comfort toggle use the ship's deck plane or the target; a per-client cosmetic reference plane is allowed but never spoken or used by rules. FT-WPN-009, FT-MSC-001, FT-STN-017. (D124)
83. One site period P per world, an exact multiple of 500 m and at least 4 times the longest sensor range, recorded in the command log setup and the state hash; weapon ranges under P/2 by content review. §4.1, FT-SIM-035. (D125)

### v0.5 update for D126–D128 (#6)

84. Load tags per station and joint view are fixed in data: Helm, Weapons and Tactical intense; Engineering, Science and Systems busy; Relay, Comms, Ops and Captain light; Viewer untagged. FT-STN-015. (D126)
85. The host is the client presenting the secret its Host button gave the child server; a dedicated server has no host. FT-NET-041. (D127)
86. A paused ship is abandoned by a majority vote of its remaining connected crew, or by the host alone; votes clear when the pause ends. FT-NET-041. (D128)
