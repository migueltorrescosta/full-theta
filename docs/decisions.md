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

## Plan review (round 21, docs/research/plan-review/)
- D95 Joint views are modal: one focused panel (F1/F2, hold View + a bumper, a tap); a station's bindings act on the focused panel and are identical in every view that contains it; a short always-live set (alert, ping, panel switch, Helm translation, face, all-stop) works everywhere; one common-actions table for all stations. Amends D20's wording ("every control reachable, one panel focused at a time"), not its intent. (E1)
- D96 Pause exit (amends D83): coverage counts only ships still in play; during a pause the ship's remaining players or the host may abandon it (eliminated); players of other ships, Captains and viewers may take over an uncovered station, unless leaving would break their own ship's coverage. Rejoin restores pick and claims only if still free; the grace length is set from measured browser refresh times; a relaunched host client rejoins its orphaned server. (E2)
- D97 Flight assist (extends D47) holds, through real thrust: zero rotation without rotation input, zero drift without strafe input, forward speed tracking the throttle setpoint. All-stop on every device; hold-to-approach faces the selected item, flies to a stand-off and matches its velocity. Clock and high/low/overhead/under are always ship frame on every station; "up N / down N" is world frame, said only after a grid square. Level rolls first; a second press also pitches onto the ecliptic. (E3)
- D98 Positions are site-local: a site id plus a local offset; a jump changes the site. Sites have shared names (a callout layer outside the 8-mark cap); JUMP targets the selected site or mark. (E4)
- D99 Milestone 1 (refines D72): marks, pings and Relay's map read-out are built in M1 so Ops has a job; the lobby shows a load tag per station and joint view; the M1 playtest rotates players through Tactical, Systems and Ops. (E7)
- D100 Onboarding: a controls overlay generated from the input map (M1), per-station first-run tooltips that explain controls (dismissable, off by default after first run), a "Shakedown" training scenario with no director and no elimination that may prompt cooperation (FT-PAIR-012 applies outside training), and a host pause in co-op sessions (M3). (E11)
- D101 Runtime Piper (refines D85): the session's closed set (ship names, callsigns, NPC names) is synthesised at Start and cached; numbers use prerendered fragments; runtime synthesis only for free text. (TECH-5)
- D102 The plan review's enhancements E1–E14 are accepted and folded into #1 as spec v0.5.

## Toolchain (#2)
- D103 Module dependencies follow the API-boundary diagram (spec §2.2): the Scenario API lives in `sim/api/`; `sim/` names only itself, `shared/` and content; the director and scenarios name only `sim/api/`, `shared/` and content; `net/` names `sim/` and `director/` for the server; clients never name `sim/`, `director/` or `scenarios/`; `app/` composes everything. Replaces the group reading of "depend only on themselves".

## M0 spikes (#3, approved in #4)
- D104 Site-local offsets are three 64-bit floats, not a float32 `Vector3`: S6 showed float32 spacing at 200 km (1/64 m) freezes drift under about 0.47 m/s. Velocities and relative vectors stay float32 `Vector3`. Amends FT-SIM-035's wording, not D98. The S6 tick budget (< 4 ms) applies to mean and p99, not every tick.
- D105 Voices (S7): voices fine-tuned from the lessac or ryan checkpoints are unclear and not shipped (FT-LIC-007); serena is accepted for Italian (CC BY 4.0); pt_PT gets a clean voice fine-tuned from a from-scratch checkpoint (cori or kristin) on the CC0 tugão dataset (#16), and tugão stays development-only until then; medium voices for runtime and the closed set at Start, high voices allowed for prerendered lines.
- D106 Network (S4): R4's (T019) p99 snapshot age is pooled over all clients on loopback; per-device p99 is checked on the owner's Wi-Fi. A client is stalled (FT-NET-037) after more than 15 unacknowledged snapshots (about 533 ms at 30 Hz), a failed send, or a high-priority queue over 256 KiB.
- D107 Art direction (S8, amends D63's toon shader): less cartoonish, slightly more photorealistic; procedural, Compatibility renderer only, PBR-style metallic and roughness materials, panel detail, less exaggerated proportions, thin or no outline, a subtle rim from a back light, and S8 variant B's palette (mint and violet), desaturated. Approved style (T016, #4): S8 v2 worn (panel shade variation, light grime) with baked fake ambient occlusion.
- D108 Browser stations (S3): the grace stays 10 s (S3 measured at most 3.7 s from drop to resume) and is re-timed on tablets in #4; the web export pipeline keeps a custom shell without the secure-context check and a guarded AudioWorklet call in `index.js`, with a test that fails when the patched pattern changes, and both problems are reported upstream to Godot (godotengine/godot#124636, godotengine/godot#124637; drop the patches once fixed); keep-awake is a muted looping VP9 video (H.264 MP4 only if iPads need it), with Auto-Lock settings documented as the fallback. Also: WS port = HTTP port + 1, ETag with no-cache, a 400 µs per-frame HTTP budget, and a larger client inbound WebSocket buffer.
- D109 Load test (S9): the server tick budget (< 8 ms) is met by S9's quiet-host runs (mean 3.3 ms, p99 5.8–6.5 ms), which count as the pass; the runs under external host load (p99 10.7–23 ms) are recorded as a caveat, and #11's 64-connection gate re-verifies the tick.
- D110 Voice bursts (S7b, TECH-5): when more than 4 free-text lines are queued for synthesis, further lines show subtitles only, with no audio (FT-AUD-015, E10). TECH-5's 1 s burst target is not met; this is the approved fallback.
- D111 Server tick (S9, amends D109): the 8 ms tick criterion is treated as not met, since on an idle host at low CPU clocks the 64-connection tick p99 is 10.4–11 ms. T041 (#6) encodes and sends snapshots on a worker thread from a copy of the state, so the sim tick holds only the sim (FT-NET-040, R15).

## M1 simulation core (#5)
- D112 Identification in M1 (FT-SPA-001): each ship definition has an identify range (m) besides its sensor range, both scaled by sensor health; once any ship of a faction has a contact within it, the faction knows the contact's allegiance for good, so `U` becomes `H`, `F` or `N`. Science scans (E01) extend this later.
- D113 Grid squares (FT-SPA-006, FT-SPA-026): letters run along world +X and numbers from 1 along +Z, counted from a map corner the scenario supplies; the layer is the height above the corner divided by the layer size, rounded to the nearest whole layer, said `up N` / `down N` and omitted at layer 0. Scenario data: corner, square size, layer size.
- D114 Chips show the range band (FT-SPA-003), not the exact range; the exact range stays for markers and the radar.
- D115 Repairs (FT-SIM-024): a repair crew job takes its subsystem's spare parts when it is dispatched; with too few parts the dispatch is rejected with an event. Crews are numbered, so they can be claimed and shown apart.
- D116 Hit location (FT-SIM-020, D26): the energy a hit puts past the shields is split: the nearest subsystem takes a per-ship share (ship data, M1 0.5) and the hull takes the rest.
- D117 Power (FT-SIM-006, P1): a ship's thrust and torque limits in data are its nominal-power envelope; overcharge reaches up to 1.5 times them (the envelope curve in data, M1 1.5), and the assist turn-rate caps scale with the torque envelope. A boost is one press: engines and thrusters run at the per-subsystem maximum for a data duration (M1 8 s) above the reactor cap, limited only by heat (one boost doesn't fault; two back to back do). The reactor subsystem supplies pips and draws none.
- D118 Shields (FT-SIM-018, FT-SIM-019): tightness runs from tightness_min (0, an even spread) to tightness_max (ship data, M1 4: a tight lobe on the focus direction); ships spawn at tightness_min. Shields absorb every hit, collisions included.
- D119 Collisions (FT-SIM-009, FT-SIM-010): the proximity warning fires when two ships would touch within 5 s, searching pairs within 500 m, so ships closing faster than about 90 m/s get at least 500 m of warning instead; restitution is 0.2 (sim constant), the kinetic energy lost is split half to each ship as damage, and contacts give linear impulse only.
- D120 Retreat (FT-M1-012, FT-SIM-027): an enemy has retreated once it is in retreat and no ship of a hostile faction detects it any more; a win needs every ship of a hostile faction destroyed or retreated, a retreated ship stays in the world, and outcomes go to ships not flown by the AI until the server has seat data.
- D121 Pair gain (FT-PAIR-015): for a lower-is-better metric such as time, "co-op beats solo by `pair_min_gain`" is measured as the share of the solo value saved, (solo − co-op) / solo; for a higher-is-better one as co-op / solo − 1. P1's `pair_min_gain` is 0.2, because D117's 1.5× envelope cap limits a sprint's time saving to about 21–22 % (P1 measured 20.9 %); 25 % stays the starting value for the other pairs.
- D122 Command log (FT-ARC-008, amends its wording): the log records each crew or server command (for example a ship reset), accepted or rejected, with its tick and result, so a replay also reproduces rejection events such as missing parts.
- D123 Hit overflow (FT-SIM-020, amends D116): the share a subsystem can't absorb (all of it once destroyed, or the part beyond its remaining health) goes to the next-nearest live subsystem, then to the hull when none can absorb it; the total damage equals the energy past the shields.
- D124 Space and frames (#5): space is rotationally invariant, with no privileged up in any rule or spoken word. Each site is a cube that wraps on X, Y and Z (a 3-torus) with period P from scenario data (default 200 km; rejected at load when P is under 4 times the longest sensing or radar range). Positions stay a site id plus three 64-bit offsets, wrapped into [−P/2, P/2) after each integration step, and every position difference uses the minimum image; the wrap replaces the 200 km offset assertion, and AI retreat drops its edge clamp (D120 unchanged). Helm's Level becomes Align: the first press rolls the ship so the selected item lies in its pitch plane above the bow (12 o'clock), a second press also faces it, and with nothing selected Align does nothing; same bindings as Level, under the Helm flight claim (FT-NET-045). World grid squares and layers are retired: positions are spoken in the ship frame or relative to a mark or site ("Bravo, 12 high, 3 km"); clock and height words stay ship frame. Radars use the ship frame, optionally centred on a selected reference, and Relay's map is a freely rotatable 3D map of the wrapping cube. A client may offer an optional per-player cosmetic reference plane (#7), never spoken or used by rules. Supersedes D42's world-fixed frame on Relay and Captain maps and its "Level aligns them"; D52's world frame (the map itself stays); D97's world-frame `up N` / `down N` and Level's pitch onto the ecliptic (its ship-frame rule stays); D98's unbounded local offset (now wrapped); all of D113; and FT-SIM-035's 200 km bound (D104's 64-bit offsets stay).
- D125 Site period (amends D124): one period P per world for now (#10 may make it per site). P must be at least 4 times the longest sensor range and an exact multiple of 500 m (the broadphase cells); a weapon's max_range is assumed under P/2 and checked only by content review. P is recorded in the command log setup and included in the state hash. An Align press with the roll already done goes straight to facing, and mark placement stays as written.

## M1 networking and sessions (#6)
- D126 Load tags (FT-STN-015, FT-M1-018): Helm intense, Weapons intense, Engineering busy, Science busy, Relay light, Comms light; joint views Tactical intense, Systems busy, Ops light; Captain light; Viewer has no tag (it isn't a station). Data in each StationDef, retuned after the #8 playtest.
- D127 Host identity (FT-NET-041): the Host button's launcher passes a random host secret to the child server, and the client presenting it in its Hello is the host. A dedicated server has no host, so there only a ship's remaining crew can abandon it.
- D128 Abandon vote (FT-NET-041): during a pause, each remaining connected crew player of the paused ship may cast or withdraw an abandon vote; the ship is abandoned when the votes exceed half of that ship's remaining connected crew (2 of 2 in the 3-player case), or at once when the host abandons it. Votes clear when the pause ends, and every client gets a vote-count event naming the voters. #7 needs a small vote control.
- D129 Start (FT-NET-019): any crew player of a ship that passes the coverage check presses Start; the universe's sim steps from the first Start and not before (lobby snapshots still flow). #11 decides how several crewable ships start.
- D130 Implicit claims (FT-NET-044): a player alone on a station holds all its claims; when a second player joins, the first keeps every claim, implicit ones included, and the newcomer claims only what the first releases.

## M5 release packaging (#12, E15)
- D140 Packaged Piper (TECH-4, FT-ARC-022): release packages ship the standalone rhasspy/piper 2023.11.14-2 program (MIT; eSpeak NG 1.52.0.1, GPL-3.0-or-later; ONNX Runtime 1.14.1, MIT), not the Python piper-tts 1.8.0 the development pipeline uses. Upstream built piper-phonemize and eSpeak NG from their master branches without recording a commit, so the source offered is inferred from the build date: piper-phonemize fccd4f33 (tag 2023.11.14-4) and rhasspy/espeak-ng 0f65aa30; `SOURCE.md` says so and offers the source on request too. Its macOS archives lack their dylibs and are x86_64 only, so macOS takes `piper` from the x64 archive and the dylibs from piper-phonemize 2023.11.14-4, with an `@executable_path` rpath; on Apple silicon it runs under Rosetta 2. The pins live in `tools/release/piper.json`; the runtime adapter (E10) works with this program, which marks no clip end.
- D141 Release voices (provisional until #4 names them; one list, `release` in `tools/tts/voices.json`): en_GB-cori-medium, en_US-norman-medium and it_IT-serena-medium, the medium voices accepted under D105. pt_PT ships no voice (subtitles only) until #16's voice replaces the development-only tugão.
- D142 Release checks in the game: an exported build prints `build: VERSION COMMIT` from a `build_info.json` packed at release time (desktop and web alike), and `-- --tts-smoke TEXT --out WAV` synthesises one line with the bundled Piper. L6 uses both to prove each package's web export comes from the same commit and its Piper runs from the exported build (FT-TST-019).
- D143 Release flow: `release.yml` runs on `v*` tags only. A read-only job builds and inspects the three packages; a separate job with write access, which runs no repository code, drafts the GitHub release that the owner publishes after #13 (the signed macOS zip replaces the unsigned one, with `SHA256SUMS` regenerated, `docs/release.md`). L6 runs on fugaku before the tag. Third-party GPL sources are attached to the release next to the packages, which is the place `SOURCE.md` offers them from (GPL-3.0 §6(d)). macOS packages are unsigned until #13.
- D144 Voice configs for the bundled Piper: Piper 2023.11.14-2 rejects phoneme_id_map keys of more than one codepoint, which it_IT-serena-medium's `.onnx.json` has (aɪ, aʊ, ɔɪ, eɪ, oʊ). At bundling, every release voice's config drops such keys; the `.onnx` model stays untouched. The change is recorded in `content/provenance.json` and the packaged `licenses/VOICES.md` (CC BY 4.0 asks for changes to be indicated). The inspection checks the bundled configs, and L6 synthesises a line with every bundled voice through the bundled Piper.

## M3 voices (#10, E10)
- D150 Voice parts (owner, Q1): the VOICE message carries `part` (int) and `last` (bool), so a synthesised line streams one message per sentence and a stitched line as one message with `last` true; PROTOCOL_VERSION goes up by one (folded into version 3 with #6; FT-NET-038, FT-AUD-019, S7b).
- D151 Session language (owner, Q2): the host picks it before launch; the Host button's launcher passes `--language en|pt_PT|it` to the server child, and Welcome carries `lang`, which every client uses for UI text (`I18n`) while subtitles and voice arrive in it from the host (FT-AUD-013).
- D152 Prerendered audio (owner, Q3): clients play authored lines without slots from their own export; the host stitches slotted lines from prerendered segments, the closed set synthesised at Start and number fragments, synthesises free text, and streams only those clips, each only to the clients in the line's audience. Number fragments are compositional per language (0–99 whole, hundreds, thousands and connectors, pt_PT and it feminine forms, `NumberWords`), about 105–140 fragments per language. Prerendered audio is built at packaging time from the dialogue JSON and never committed (FT-AUD-002, FT-AUD-018, FT-ARC-019).
- D153 Ship-computer filter and Piper builds (owner, packaging strand): the robotic filter is an effect chain on the client's `VoiceComputer` bus (6 ms comb, 300–3,400 Hz band-pass, lo-fi bitcrush; S7's ring modulation dropped, no built-in effect), so it applies alike to local, stitched and synthesised computer clips and to either Piper build (FT-AUD-004). Development runs piper-tts 1.8.0 through `tools/tts/piper_stream.py`; releases run the standalone rhasspy/piper 2023.11.14-2 binary (`BundledPiper`), both behind one adapter, one persistent process per voice (FT-AUD-019). Provisional release voices: en_GB-cori-medium (computer), en_US-norman-medium (NPC), it_IT-serena-medium (both); pt_PT has no release voice until #16, so release sessions in pt_PT are subtitles only, and tugão stays development-only (D105). The 2023.11.14-2 binary can't load it_IT-serena-medium's multi-codepoint phonemes, so release voices get packaging's bundle-time `.onnx.json` patch (D144); the patched Italian voice is unreviewed until #4.
- D154 Two prerender packs (coordinator, for tablet download size): the client pack is one Ogg Vorbis file per unslotted line in `audio/prerendered/<lang>/` (about 53 kbps: 6.6 KB per second of speech plus about 3.5 KB of headers per file; S7's 2,000 lines × 3 s would be about 40 MB per language, against 265 MB as raw PCM), in desktop and web exports; the host pack is raw 16-bit PCM blobs of segments and number fragments in `audio/prerendered_host/<lang>/` (7–9 MB per language), desktop only. Each folder has an `index.json` the package inspection checks. Encoded at build time with python-soundfile (libsndfile).

## Load gate (#11, E11)
- D160 Load gate scene (#11, FT-GEN-003, FT-TST-011, FT-TST-014; approved in #11): the 64-connection gate runs 6 crewable ships of one co-op faction and 6 AI raiders split into two factions hostile to each other and to the crew, so they fight for the whole run; the seats are 36 crew (the six stations of each ship), 6 Captains and 22 viewers dealt round the ships (`LoadSeats`); each ship's Helm seat presses Start, and the window opens once all 6 ships have started. The server is pinned to CPUs 0 and 1; the 64 clients run as 8 processes of 8 connections on other physical cores, not on the server's hyperthread siblings. The same run with 94 raiders (the S6/S9 envelope of 100 ships) is the stress number, reported and not gating. It is `tools/gate.sh l4load` (fugaku only, in `all`, not `ci`); an L3 test checks connection 65 in a 6-ship session in `ci`. Until the multi-ship lobby lands, the 6 ships come from the dev and test flag `--load-ships` (`LoadEncounter`), never offered for play.
- D161 Load gate measurement (#11, FT-NET-040, D104, D106; approved in #11): the server tick is the wall time of each main-thread frame that stepped the sim (inbound messages, sim, event routing and the state capture), checked as mean and p99, with the frame's on-CPU and run-queue time from `schedstat` and the frame time per tick beside it; the sim must also keep real time (at least 59 ticks a second, since a late frame's extra ticks are capped and the rest dropped). The capture is stamped just before it is taken. Snapshot age is the client's arrival time, before decoding, minus the server's capture stamp, joined by snapshot seq after the run (no protocol change), as the p99 pooled over all clients; no age may be below −1 ms, every client must receive at least 90 % of the window's snapshots without a stall, and the gap between a client's receipts is reported beside the age. Bandwidth is the server's payload per connection as handed to `WebSocketPeer` over the window; when the server sends fewer than 30 snapshots a second it is also scaled to 30, and the loopback wire total is reported beside it (host-wide unless the run is in a network namespace).
- D162 Load gate result (#11, D111; approved in #11): two 60 s runs at host load 19.5 and 22 (an unpinned foreign job) with server-core clocks of 1.6–2.4 GHz. Met: snapshot age (p99 96–135 ms pooled), bandwidth (1.75–2.3 Mbit/s payload at 10–20 snapshots a second, 3.4–5.2 Mbit/s scaled to 30), one encode per view key (48 keys, 64 sends, 48 messages per snapshot) and the session cap. Not met: the tick (frame mean 28–79 ms, p99 146–216 ms, 53.6–58.4 ticks a second; 7.2–8.1 ms on CPU per tick mean, 10.6–11.5 ms p99), mostly sim (10.6–13.7 ms per tick in the server against 5.3 ms alone in `sim_profile` at load 17) with the net thread busy 0.54–0.69 of a core of the same two. These runs are indicative only: the load client then stopped pressing Start after the first ship started, so 1 of the 6 ships had started (all 6 were simulated and commanded, but 5 were not launched), and an age met at 10–20 snapshots a second (receipt gaps p99 190–250 ms) is weak evidence. The tick criterion stays open, and every criterion is re-verified by `gate.sh l4load` on the sim-performance work once it lands, on an idle fugaku (load average under about 2), since timings under the foreign job are not trustworthy.
- D163 Load gate rerun (#11, amends D162; approved in #11): no idle window came in 2 h (the unpinned foreign job held the load average at 15–22), so the gate ran once on the merged code with the faster sim (`bf67db3`, 2026-10-20, load 17.3–19.3, server cores 2.0–2.9 GHz). Evidence from it, independent of timing: all 6 ships started, the sim kept real time (60.0 ticks a second), one encode per view key (48 keys, 64 sends, 48 messages per snapshot), bytes recorded per client (3.5–5.0 kB/s) with a total of 1.96 Mbit/s payload at 14.3 snapshots a second (4.1 Mbit/s scaled to 30; 4.1 Mbit/s loopback wire, host-wide), connection 65 refused with `session_full`, no stalls, no starved client, no bad snapshot. Under load and not evidence: frame mean 11.0 ms and p99 31.1 ms (on CPU per tick 5.4 ms mean, 11.8 ms p99; sim 8.3 ms per tick in the server against 2.6 ms alone), snapshot age p99 133 ms with receipt gaps p99 121 ms, and the net thread saturating a core (32 ms per snapshot). The timing criteria (tick budget, snapshot age) move to a follow-up issue that reruns `gate.sh l4load` on an idle fugaku.

## M1 client and stations (#7)
- D170 Alert levels (owner, FT-STN-006, FT-STN-008): three levels, Normal (green circle, N), Yellow (amber triangle, Y) and Red (red square, R). Controller: hold View and press d-pad up for Red, right for Yellow, down for Normal; Alt+A cycles; clicking the top-bar chip opens a three-button picker.
- D171 Crew state outside the sim (owner): marks, pings and the alert level live per ship in the server session (`CrewMarks`, `CrewPings`), not in the sim, the command log or the state hash. They travel as the client messages Alert, Mark and Ping and as `alert`, `marks` and `ping` events to every pick on that ship; PROTOCOL_VERSION goes to 4. A run reset clears the marks and sets the alert to Normal.
- D172 Comfort roll lock (owner, FT-STN-017, D124): the comfort setting locks the roll of the cockpit, turret and main-screen cameras to the deck plane (default), the selected target, or a personal reference plane captured from the ship's attitude when the player presses "Set reference plane"; per client, never sent to the server, never spoken.
- D173 Main-screen auto-chase (owner, FT-MSC-001): the forward view switches to chase while the ship is decoupled or rolls faster than 45°/s, and back to forward after 1.5 s below 30°/s.
- D174 Client menu (owner, FT-M1-016): the main menu has a persisted Name, Host (bind on this computer only or a LAN address, the session language, and a development checkbox for one client holding all stations) and Join (hosts found by discovery, listed live, plus an address field).
- D175 Radar side strip key (owner, amends FT-SPA-009): the elevation side strip toggles with Z (controller View + d-pad left) on every station; B (View+Y) stays the request-chip key of §5.0.
- D176 Left click (owner, FT-STN-009): in the cockpit and the turret, a left click selects only when the pointer is over a chip, mark or radar item; elsewhere it fires. T and Y also select. The binding-table check exempts this pointer case.
- D177 Ship-computer voice audiences (owner, FT-AUD-006): hull critical goes to every crew station, shields low to Helm and Engineering, subsystem fault to Engineering, collision warning to Helm.
- D178 Run reset (owner, FT-M1-012, like D128): after a win or loss every station shows an outcome card (Victory or Ship lost, time, hull). Each connected crew player may cast or withdraw a "Run again" vote; the reset happens when the votes exceed half of the ship's connected crew, or at once when the host decides. The world is rebuilt from scratch (marks and alert cleared, picks kept) and everyone returns to the lobby to press Start.
- D179 Aim assist (owner, FT-SIM-015): light and controller only: within 4° of the lead, while the stick moves, aim slows to 60 % of its rate and is pulled toward the lead at up to 0.1 rad/s; never auto-aim.
- D180 Target roll lock (owner, FT-STN-017, D172): the comfort lock "Target" uses the target ship's deck plane from its NEAR orientation, and our own deck plane when there is none.
- D181 Engineering keys (owner, FT-ENG-003, FT-STN-009): Period and Comma tighten and spread the shields, O boosts; controller LB + d-pad up and down, and LB + RT.
- D182 Relay's ninth mark (owner, FT-SPA-022): with 8 marks, Relay's new mark replaces the selected mark; with none selected it is refused with a toast.
- D183 Helm pointer (owner, FT-HLM-001): the cockpit captures the mouse to steer; holding Ctrl (rebindable, may be a toggle) frees it, as do Esc or the menu, a pause and losing window focus; a click in the view captures it again.
- D184 Shield ring layout (owner, FT-HLM-009, FT-HLM-011): 12 clock sectors in 3 height bands (outer high, middle level, inner low) around a centre split into overhead and under.
- D185 One menu (owner, 2026-10-24, #22, after the #8 playtest, supersedes the separate tooltip of D100 and the separate `?` overlay): Settings and the controls are one opaque menu with tabs (Controls, Settings, Rebind keys). Escape opens it on the tab last used (Settings at first); `?` or View opens it on Controls, and so does a seat's first visit, where Controls is headed by the seat's role summary. Escape or a Back button closes it. Every lobby entry shows the same role summary, and a language switch retranslates every open screen, the menu included.
- D186 Joint views name their pair (owner, 2026-10-24, #22, FT-JNT-006): the lobby's pick button for a joint view shows its name with the pair on a second line ("Tactical" over "Helm + Weapons"), replacing the "Plays X and Y solo" hint.
