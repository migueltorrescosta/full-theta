# Decisions log (owner answers)

## Repo
- D1 Visibility: public (free Actions minutes).
- D2 Licence: GPL-3.0. EmptyEpsilon is GPL-2.0-only (no "or later" grant), so its code can't be reused; ideas only (see D62).
- D3 Repo creation: the owner creates the repo and invites the bot account.
- D4 Name: Full Theta, repo migueltorrescosta/full-theta.

## Tech
- D5 Engine: Godot 4.7.2, typed GDScript (owner: use GDScript because it allows play in the browser with no download; else C#).
- D6 Reconnect: a disconnected player (browser or desktop) must be able to refresh/relaunch and continue at their station mid-run (session token + full snapshot resync).
- D7 Hosting: Host button spawns headless authoritative server child process; same binary can run on a dedicated machine.
- D8 Browser/tablet stations: after the first playable; protocol web-ready (WebSocket) from day one.
- D9 Platforms v1: Linux + Windows + macOS (macOS: no Mac to test on; signing/notarisation is a risk to track).
- Licence note: EE LICENSE is GPL-2.0 with no "or later" grant found, so EE code can't go into a GPL-3.0 project. Ideas only, provenance recorded. EE ship model packs are proprietary.

## Crew and stations (owner answers, round 2)
- D10 Players: EE-like station selection. A player may hold several stations; several players may share one station (e.g. 2 on Weapons when there are many weapons). Unlimited viewers per ship (e.g. 10 watching the main screen); cap only the total player count, for performance. Owner asked for this to be compared against EE and challenged where appropriate (pending).
- D11 Ships: up to 6 player ships per session; both co-op and PvP allowed.
- D12 Unstaffed stations: simply off (no automation).
- D13 Combining stations: curated combos only.

## Info and roles (round 3)
- D14 Info asymmetry: by difficulty (strict on Hard, soft on Easy).
- D15 Captain: information only (overview + main screen control). Tension: the spec has 5 Captain pairs (raised in the next round).
- D16 Shields: Engineering sets shield power/allocation; Helm controls the shields' direction (facing toward the attack).
- D17 Minigames: mandatory, EE style (scan, hack).

## Challenge round (after EE comparison, crew-ships-challenge.md)
- D18 Shared station: players claim weapon mounts (and, by analogy, claimable sub-controls on other shared stations); claimed items are locked for others.
- D19 Coverage replaces "simply off" (D12 superseded): a station is only a view/control over server mechanics. A ship must have all functional stations covered before launching. Smaller crews use curated combos (several combos allowed) to cover every station. Captain is optional, so it's not required for coverage. Hence no automation and no "off" state.
- D20 Combos: curated only, but each combo is complete (keeps every control of its stations). Needs combos for every crew size 1..5 (incl. a solo combo).
- D21 Multi-ship: design PvP in now. Up to 6 ships, co-op and PvP from the architecture onward (state keyed by ship+faction, per-faction knowledge, director/balance/run-reset rules for PvP). Spec to be amended (no longer "one shared spacecraft").

## Round 4
- D22 Player cap: one total cap of 64 connections (crew + viewers).
- D23 Captain pairs dropped: spec amended to 10 pairs; the Captain is a pure overview seat (information only).
- D24 Flight: 6DOF Newtonian, flight assist on by default (real thrust), decoupled mode toggle.
- D25 Aiming: manual aim in a gunnery view with lead indicator; light aim assist on controllers.

## Round 5
- D26 Damage: hit location (nearest subsystem to impact).
- D27 Repairs: repair crews dispatched by Engineering through a ship cutaway; spare parts resource.
- D28 No frequency matching; Science reveals weak points and damage-type resistances.
- D29 Travel: jump drive within an encounter/open 3D map (EE-like), not a sector map. Owner: 3D navigation is essential; clarify 3D views and controls for Helm/Weapons/Tactical etc., especially how players talk about, navigate and communicate 3D angles and coordinates smoothly.

## Round 6
- D30 Win/lose: per-ship elimination. A destroyed ship's crew is out and its run progress resets; the other ships carry on. Win: final run objective (co-op) / per mode in PvP.
- D31 Death risk: 5–10% chance of losing the ship per encounter for an average crew (≈ 23–41% per run over 5 encounters; measured in playtests).
- D32 Persistence: nothing persists between runs.
- D33 Difficulty: crew picks Easy/Normal/Hard at start (encounter budget + info asymmetry D14), never hidden stats.

## Round 7
- D34 Economy: credits; ammunition (missiles, torpedoes, etc.); gas/propellant consumed by thrust (travel, turns) and by jumps, not by inertial coasting; reputation per faction. Reputation changes are moderately random, with distributions specific to each interaction type (seeded RNG, distributions in data, visible ranges where sensible).
- D35 Director: every decision logged with its reason and shown in the end-of-run debrief.
- D36 Retreat: fleeing an encounter (at a cost) and abandoning the run are both allowed.
- D37 Friendly fire and collisions: both on, with clear warnings.

## Round 8 (audio)
- D38 TTS: Piper. Authored lines prerendered at build time; dynamic lines synthesised at runtime (GPL OK under D2).
- D39 TTS output: only the relevant client plays a line, usually the comms player. If two players use comms, only the one interacting with that NPC hears it. (So per-client TTS + per-client audio routing; runtime Piper must run on whichever client needs it, or on the host and streamed — architecture task.)
- D40 Launch languages: English, Portuguese (pt_PT), Italian.
- D41 Language scope: one per session.

## Round 9 (3D language)
- D42 Radar frame: ship-relative on crew stations (Helm, Weapons, Science), world-fixed on Relay/Captain maps; Helm Level key aligns them.
- D43 Radar look: Elite-style disc with elevation stems + range ring at selected contact + optional side strip, on every station.
- D44 Marks: any station (incl. Captain) places; Relay curates; 8 NATO names per ship; rate-limited pings.
- D45 Callouts: A — callsign + clock/height/range + named marks; bearing/mark numbers on hover; grid squares on the world map (station-ui.md §1.2).

## Round 10 (Helm/Weapons)
- D46 Helm: cockpit + target compass + radar disc + shield ring (H-A), C toggles chase camera.
- D47 Facing: compass + hold-F face assist at real turn rate.
- D48 Shield aim: six-face snap + clock-sector tap + track-selected toggle.
- D49 Weapons: turret camera from a claimed mount (W-B), radar disc inset, swap between claimed mounts.

## Round 11 (other stations) — station roles redefined by owner
- D50 Engineering: cutaway + power pips + shield power/focus + faults/parts/request chips (E-A). Role: supervising all systems.
- D51 Science: orbitable 3D sensor disc + contact card + scan controls + share buttons (S-A). Role: information gathering — scanning AND hacking ships, learning what is most effective against them.
- D52 Relay: freely rotatable world-frame 3D map; probe coverage, routes sent to Helm, hazards, marks (drag, Shift+drag height); probes and contacts on the left; log. NO NPC text. Role: the full tactical view of the universe.
- D53 NEW STATION Comms (split from Relay): all NPC text, replies, contracts, priorities, missions and opportunities. Role: understanding the story of the universe. Comms player hears NPC TTS (D39).
- D54 Captain: main-screen director (mirror of main screen, view buttons, tap = ping). Information only.
- Roles summary (owner): Relay = tactical view of universe; Comms = story; Engineering = systems; Helm = movement; Weapons = damage; Science = information gathering (incl. hacking).
- D55 Pairs: redesign the 15 pairs across the 6 functional stations (Helm, Weapons, Engineering, Science, Relay, Comms); Captain outside the pairs.
- D56 Relay launches/places probes; Science scans and hacks (hacking benefits from probe coverage).
- D57 Comms accepts/declines contracts alone; no co-sign.

## Round 12 (minigames, main screen)
- D58 Scan minigame: silhouette alignment (point cloud vs wireframe; noise from range/sensor health; Helm at scan-position mark reduces noise).
- D59 Hack minigame: node route vs trace bar; hidden nodes revealed by scans / probe coverage.
- D60 Main screen default: forward view + wide radar disc + callsign rail (clock + range); Captain switches views (forward, chase, tactical, target, status).
- D61 Pings: middle-click / long-press pulses on every screen of the ship + chime, rate-limited.

## Round 13 (content)
- D62 EE compatibility: none; ideas only.
- D63 Assets: procedural/primitive meshes + CC0 packs (Kenney, Quaternius) + toon shader; CC0 sounds; provenance manifest.
- Pairs/combos drafted in pairs-and-combos.md (6 shared systems PWR/COND/KNOW/MARK/STORY/CUE); questions at L292–334 pending.
- D64 Scenarios: typed GDScript classes extending a restricted, typed Scenario API + declared metadata for the director; lint gate forbids sim internals.
- D65 Data: typed Resources (.tres text) for ships, weapons, subsystems, upgrades, enemies, validated by headless Godot gate; dialogue as JSON + JSON Schema (read by TTS prerenderer and translators).

## Round 14 (combos, crew size)
- D66 Minimum crew: 3 players per ship (no solo, no 2-player).
- D67 Joint positions: the lobby menu offers a catalogue of curated joint views (e.g. Ops R+C, Sensors S+R, Systems E+S, Tactical H+W, ...); players pick any. The only check: the ship's players together cover all 6 functional stations; then Ready/Start becomes clickable. (Supersedes the fixed per-size combo sets.)
- D68 Eng + Comms is verbal only: Engineering describes ship condition by talking; no one-key status snapshot. Comms sees what can be bought/sold; Engineering guides Comms verbally; Comms has the final say.

## Round 15
- D69 Cross-station data shortcuts by difficulty: Easy = share buttons/data links (weak points to Weapons, routes to Helm, probe tracks); Hard = verbal only except marks and pings. Eng+Comms is verbal at every difficulty (D68).
- D70 Accept remaining tech defaults: Godot 4.7.2 pinned, upgrade by PR; Compatibility renderer; custom WebSocket protocol (commands up, per-station filtered snapshots + reliable events down); sim 60 Hz / snapshots 30 Hz; UDP discovery + manual IP + QR; custom 6DOF integrator; gdUnit4; screenshot tests with software GL (llvmpipe/Xvfb) on fugaku; one repo, lint-enforced pure sim/ folder; LAN only; no client prediction at first; full CI on every ready PR (public repo); seeded RNG.
- D71 Ship computer voice: Piper with robotic/radio filter (no second engine).
- D72 Milestone 1: one ship, 3 clients covering all 6 stations via joint views, one enemy, Eng+Helm loop, refresh-to-rejoin, state keyed by ship+faction, a 2-ship PvP simulation test; dev flag lets one client hold all stations.

## Issue DAG (round 16)
- D73 DAG links: native GitHub "blocked by" dependencies + "Depends on: #N" line in body; epics hold tasks as native sub-issues.
- D74 Granularity: M0 spikes + M1 as PR-sized issues; later milestones as epics with outlined tasks, refined after M1.
- D75 Grouping: GitHub milestones M0 Spikes, M1 First playable, M2 Full crew, M3 Missions & director, M4 Multi-ship & PvP, M5 Polish & release; area labels sim, net, ui, audio, content, ci, docs.

## Open questions from spec v0.4 (round 17)
- D76 Joint views: every 2-station pair (15 layouts) available in the lobby.
- D77 World: a single global 3D map for the entire scenario; no per-encounter maps. "Encounter" = a self-contained situation (enemy wave, rescue, derelict, negotiation...) the director places/activates at a site in that map, with its own triggers and outcome. Ships move between sites by impulse and jump drive.
- D78 PvP: race the same run, last ship standing, and two-faction teams, each a distinct scenario.
- D79 Eliminated crew: scenario-defined; default/most common = viewers of a friendly ship's main screen.
- D80 Sites: scenario seeds some known sites; director spawns more over time within budget, each spawn logged for the debrief.
- D81 Multi-ship difficulty: one difficulty per session; director threat budget per ship.
- D82 Allies: faction knowledge shared (identified contacts, reputation); marks per ship. Relay can send a mark to another ship; that ship's Relay must accept it before it is shared with its crew.
- D83 Disconnect: 10 s grace (stations keep settings/claims), then the whole universe pauses (all ships) until coverage is restored by rejoin or takeover.
- D84 Data shortcuts: each cross-station data shortcut is an individual toggle set before start; Easy/Normal/Hard are presets (Easy all on; Normal = request chips, routes, lanes, hazard countdowns on, weak points/track feeds/diagnosed causes by voice, banded summaries; Hard = marks and pings only). Eng+Comms always verbal (D68).
- D85 Runtime Piper on the host server; clip streamed to the one client that plays it.
- D86 Upgrades: slot modules with trade-offs, bought while docked via Comms.
- D87 Comms layout: card board (missions/contracts/offers/hails as cards; conversation opens as overlay).
- D88 Main screen with no Captain: Relay only controls it.
- D89 Alert level: any crew station can set it.
- D90 Normal preset: mission mark icon on; contract flags on reticle and Science verify chips by voice.
- D91 Eliminated crews with no friendly ship: lobby + live scoreboard.
- D92 Custom toggles: threat budget follows the chosen difficulty; shown as '<Preset> (custom)'.

## Issue structure (round 20)
- D93 The 80-item task breakdown is aggregated into 13 GitHub issues, each resulting in one PR (owner issues have none); fewer, larger issues with extensive verification criteria.
- D94 Browser and touch stations move from M4 to M2 (full crew).
