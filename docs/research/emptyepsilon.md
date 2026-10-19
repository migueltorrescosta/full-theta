# EmptyEpsilon reference study and comparison with spec v0.3

Prepared for: the product owner and the coding agent that will build the task DAG.
Sources: shallow clones of `daid/EmptyEpsilon` (master, ECS rewrite) and `daid/SeriousProton` taken locally (read only, nothing built or run), the official site (daid.github.io/EmptyEpsilon), and the bundled Lua scenarios and tutorials. Paths below are relative to `ref/EmptyEpsilon/` unless they start with `SeriousProton/`.

Abbreviations: EE = EmptyEpsilon; SP = SeriousProton (EE's engine); U = EE distance unit (1U = 1000 world units); GM = Game Master; TTS = text-to-speech.

---

## 0. Executive summary

EE is a 2D-simulation, 3D-rendered bridge simulator in which **the server owns everything and stations are thin views that send typed commands**. Its cooperative depth comes from a few shared systems (one energy pool, per-system power/heat/coolant/health, a scan-state ladder, beam/shield frequencies, reputation as a currency) rather than from per-pair minigames. That is the right model to copy *as ideas*.

Where our spec departs from EE:

1. **Physics.** EE ships fly on a plane; impulse sets velocity directly along the heading (`src/systems/impulse.cpp`, `physics.setVelocity(forward * actual * max_speed)`), so there is no drift or momentum. Our spec requires full 3D Newtonian flight. This changes Helm, Weapons (arcs become cones), Science (3D sensor geometry), and AI completely.
2. **Aiming.** EE beams fire automatically at the selected target when it is in arc; missiles aim by bearing on a 2D radar. Our spec requires manual aiming from switchable 3D views.
3. **No Game Master.** EE's best sessions rely on a live GM (`src/screens/gm/`) who spawns ships, voices NPCs and fixes pacing. We need a procedural director plus authored components, and TTS voices in place of the GM's typed messages.
4. **Session shape.** EE scenarios are single-mission, often open-ended, 1–3 hours; no persistent upgrades. Ours are 20–40-minute roguelite runs with money, salvage and upgrades that reset on death.
5. **Captain.** EE's captain has no station (they watch the main screen and talk). Ours is an optional station with real but non-mandatory tools.
6. **Licence.** EE is GPL-2.0; SeriousProton is MIT; several EE model packs are proprietary (TurboSquid/CGTrader, redistribution only with EE). We should reimplement from ideas only and keep our code under a licence of our choosing.

---

## 1. EE reference summary

### 1.1 Architecture and networking

- **Engine:** SeriousProton (MIT, C++, SFML-era now SDL2/OpenGL), ECS in recent versions (`src/components/*.h` = data, `src/systems/*.cpp` = logic).
- **Authority:** one server runs the simulation; clients receive replicated component state (`src/multiplayer/*.cpp`, `SeriousProton/src/multiplayer_server.cpp`) over TCP, and find servers on the LAN through UDP broadcast (`multiplayer_server_scanner`). Default port 35666. Optional internet master-server registration and a proxy mode.
- **Commands:** every player action is a named command sent to the server (`src/playerInfo.cpp`, ~49 commands such as `commandImpulse`, `commandTargetRotation`, `commandFireTube`, `commandSetSystemPowerRequest`, `commandScan`, `commandLaunchProbe`, `commandSetBeamFrequency`, `commandSetBeamSystemTarget`, `commandHackingFinished`, `commandConfirmDestructCode`). Minigames run client-side and report only the result (`commandScanDone`, `commandHackingFinished`) — a trust shortcut that is fine on a LAN.
- **Headless server:** `headless=<scenario>` preference starts a server with no window (`src/main.cpp`). An optional HTTP server exposes Lua for external tools (`src/httpScriptAccess.cpp`). Serial/DMX hardware output for room lighting (`src/hardware/`). Built-in voice chat (`SeriousProton/src/networkAudioStream.cpp`) for remote crews.
- **Crew assignment:** a bitmask of `CrewPosition`s per client (`src/crewPosition.h`), so one machine can host several stations; a ship can restrict allowed positions and set a control code (password).

### 1.2 Stations (what each screen shows and controls)

| Station | Shows | Controls | Source |
|---|---|---|---|
| **Main screen** (captain's view) | 3D viewport front/back/left/right/target; or tactical radar, long-range radar, strategic map (each can be disabled by server option); comms overlay; global messages; jump indicator; self-destruct indicator; ship-destroyed popup | Keyboard (number keys/arrows) on the main-screen machine, or main-screen buttons granted to a station | `src/screens/mainScreen.cpp`, `screenComponents/mainScreenControls.cpp`, `components/player.h` (`MainScreenSetting`) |
| **Helms** | Short-range radar with heading ring, velocity, heading, energy | Click radar to set heading; impulse slider (−100..100%); warp slider (0–4) or jump distance + jump button; combat maneuver pad (boost forward / strafe, limited charge, heats systems); dock/undock button; custom script buttons | `screens/crew6/helmsScreen.cpp`, `screenComponents/impulseControls`, `warpControls`, `jumpControls`, `combatManeuver`, `dockingButton` |
| **Weapons** | Short-range radar with beam arcs and tube directions, energy, front/rear shield %, beam info | Click to select target (beams auto-fire on it); beam frequency selector; beam subsystem-target selector; per-tube load/unload/fire with missile type selector; aim lock / manual missile aim dial; shields on/off; shield frequency (25 s recalibration) | `crew6/weaponsScreen.cpp`, `missileTubeControls`, `aimLock`, `beamFrequencySelector`, `beamTargetSelector`, `shieldsEnableButton`, `shieldFreqencySelect` |
| **Engineering** | Energy, hull, front/rear shields, coolant reserve; a row per system with health, heat, power, coolant; an effects panel per selected system; ship internal room view with repair crews | Per-system power slider 0–300% and coolant slider 0–10 (shared pool); select a crew and click a room to send it; auto-repair toggle (server option); self-destruct (codes shown on other stations) | `crew6/engineeringScreen.cpp`, `shipInternalView`, `systems/energysystem.cpp`, `coolantsystem.cpp`, `internalcrew.cpp` |
| **Science** | Long-range radar (default 25–30U) with zoom; raw scanner overlay (gravity / electrical / biological signature bands); probe view; sidebar: callsign, faction, type, shields, hull, distance, bearing, relative speed, per-system health, shield and beam **frequency curves**; description text per scan level; database | Select contact; Scan (opens slider-matching minigame); toggle probe view of a Relay-linked probe; database browser | `crew6/scienceScreen.cpp`, `scanningDialog.cpp`, `rawScannerDataRadarOverlay.cpp`, `frequencyCurve.cpp`, `databaseView.cpp` |
| **Relay** | Strategic map; objects only seen within 5U of the ship or of probes/allied ships ("short-range radar sharing"); reputation; clock; ship's log | Place/move/delete waypoints (Helms sees them); launch probe to a point (8 stock, recharge when docked); link probe to Science; open comms / answer hails (scripted dialogue trees); hack a target system (lights-out or minesweeper minigame); set alert level (normal/yellow/red) | `crew6/relayScreen.cpp`, `hackingDialog.cpp`, `lightsOut.cpp`, `mineSweeper.cpp`, `commsOverlay.cpp`, `components/comms.h` |
| **Tactical** (4/3-crew) | Helms + Weapons on one radar, minus shields | All helm + weapon controls | `crew4/tacticalScreen.cpp` |
| **Engineering+** | Engineering plus shields enable and shield frequency | | `crew4/engineeringAdvancedScreen.cpp` |
| **Operations** | Science + Relay comms/waypoints (no probes/hacking) | | `crew4/operationsScreen.cpp` |
| **Single pilot** | Helm + weapons + shields + comms | | `crew1/singlePilotScreen.cpp` |
| **Extras** | Damage control (room view only), Power management (power/coolant sliders only), Database, Alt relay, Comms only, Ship's log | | `screens/extra/` |
| **Spectator / top-down / cinematic / window** | Non-crew views (a "window" shows a side view for immersion) | | `screens/*.cpp` |
| **Game Master** | Whole-map radar; every object editable | Spawn ships/stations/hazards; give AI orders (idle, roaming, stand ground, defend, fly towards, attack, dock); "Tweak" any component; global message; hail as any ship; intercept all comms; pause; copy scenario as Lua | `screens/gm/gameMasterScreen.cpp`, `tweak.cpp`, `objectCreationView.cpp`, `GMActions.cpp` |

The captain has **no station**. Captains use the main screen, the alert level (Relay), and their voice. Custom script buttons (`GuiCustomShipFunctions`) let a scenario add per-station buttons and info.

### 1.3 Mechanics

**Ship systems** (`components/shipsystem.h`): Reactor, BeamWeapons, MissileSystem, Maneuver, Impulse, Warp, JumpDrive, FrontShield, RearShield. Each has `health` (−1..1; ≤0 = offline), `power_level` 0–3 (requests ramp at 0.3/s), `heat_level` 0–1, `coolant_level` 0–10, `hacked_level` 0–1. Effectiveness = `max(0, power − 0.75·hacked) · health` (or `· (1 − heat)` when system damage is off). Heat rises by `1.7^(power−1) − (1.01 + 0.1·coolant)` per tick-unit; at 1.0 the system takes 0.08 health/s damage.

**Energy** (`systems/energysystem.cpp`): one reactor store (default 1000). Each system draws `power_factor × 0.08 × power_level` per second (factors: beams 3, tubes 1, maneuver 2, impulse 4, warp 5, jump 5, each shield 5); the reactor produces the sum at 100%. Below 10 energy all systems are depowered. A reactor below −90% health and overheating explodes. Beam shots cost energy and heat per shot.

**Coolant** (`systems/coolantsystem.cpp`): a shared pool (default 10) spread by requests; over-requests are scaled down; optional auto-coolant proportional to heat.

**Repair crews** (`components/internalrooms.h`, `systems/internalcrew.cpp`): ships define rooms on a grid, each optionally mapped to a system, plus doors. Crew walk room to room; in a system room they repair 0.007 health/s and also remove hacking. Optional auto-repair. Docked at a friendly station: hull repair.

**Hull and damage** (`systems/damage.cpp`): damage hits the shield segment facing the hit (N segments over 360°); shield absorbs according to power (`getDamageFactor`) and frequency; overflow goes to hull. Each hull hit also damages a random system (beams 2.5× more); if the attacker chose a target system, that system takes extra damage. Energy damage to hull is mostly absorbed when targeting systems. EMP damages shields only.

**Beams** (`components/beamweapon.h`, `systems/beamweapon.cpp`): per mount: position (3D, visual only), arc, direction, range, cycle time, damage, energy and heat per shot, optional turret (arc that rotates within a turret arc). Auto-fire at the selected target when in arc and range. Frequency 0–20 (400–800 THz); damage factor 0.5–1.5 based on beam vs shield frequency (`frequencyVsFrequencyDamageFactor`, a shield-dependent sine curve); server option to disable.

**Shields** (`components/shields.h`): any number of segments (players: front/rear); toggled by Weapons, drain 1.5 energy/s when up; frequency change takes them offline for 25 s.

**Missiles** (`missileWeaponData.cpp`, `systems/missilesystem.cpp`): tubes with direction, load time (default 8 s), allowed-type mask, size S/M/L (damage multiplier). Types: Homing (speed 200, 35 dmg, homing range 1.2U), Nuke (160 centre / 30 edge, 1U blast), Mine (dropped, 1U trigger, 160/30), EMP (shield-only area 160/30), HVLI (fast 500, unguided, 10 dmg, full damage only after 1U flight). Storage per type; resupply only via station comms when docked (costs reputation).

**Movement**: impulse (max speed, acceleration, velocity locked to heading), maneuvering (deg/s turn rate toward a target heading), combat maneuver (charge-limited boost/strafe that heats impulse and maneuver), warp (levels 1–4, 1000 U/s per level, energy per second, blocked by warp jammers), jump drive (5–50U, charges over 90 s by energy, 10 s countdown, teleport along heading, heat per jump). Ships usually have warp **or** jump.

**Scanning** (`components/scanning.h`, `screenComponents/scanningDialog.cpp`): per-faction state NotScanned → FriendOrFoeIdentified → SimpleScan → FullScan. Simple scan reveals type/faction; full scan reveals shields, systems, frequencies, description. Science plays a minigame: match N sliders (complexity) to a hidden signal shown as a waveform, repeated `depth` times; server option None/Simple/Normal/Advanced. Without the minigame a scan is a 6 s delay. Scenario scripts can hook scan events.

**Probes and radar** (`components/probe.h`, `radar.h`, `radarblock.h`): 8 probes, launched by Relay to a point, last about 10 min, share a 5U short-range radar; one probe can be linked to Science for a remote long-range view. Nebulae block long-range radar except at short range. Raw signature data (gravity/electrical/biological) is shown as noise bands on Science radar, with live boosts from engines.

**Comms and reputation** (`components/comms.h`, `scripts/comms_station.lua`, `comms_ship.lua`): hailing opens a Lua dialogue (message + reply buttons); stations sell ordnance by reputation (Homing 2, Nuke 15 rep each; supply drop 100; reinforcements 100–300) when docked and friendly enough. Reputation is per faction (`FactionInfo::reputation_points`), earned by script (kills, missions).

**Hacking** (`hackingDialog.cpp`): Relay picks a system on a target with a `HackingDevice`, solves lights-out or minesweeper; success raises `hacked_level` on that system (−75% power at full), decaying over time and removable by repair crews.

**Docking** (`components/docking.h`, `systems/docking.cpp`): within ~1U, Helms docks; bays can share energy, repair hull, recharge shields, restock probes; players buy missiles via comms.

**Alert level and self-destruct**: Relay sets normal/yellow/red (colour overlays on all stations). Self-destruct needs up to three codes, each shown on one station and typed on another (`components/selfdestruct.h`) — a small, elegant forced-communication mechanic.

**AI** (`src/ai/`, `components/ai.h`): orders Idle, Roaming, Retreat (go restock missiles), StandGround, DefendLocation, DefendTarget, FlyFormation, FlyTowards, FlyTowardsBlind, Dock, Attack. Target score = −distance − turn cost, +2500 if armed, −1500 for stations, +1000 if already in a beam arc. Variants: default, fighter (strafing runs), missilevolley (salvo then turn), evasion (dodge). AI does not flank or coordinate; GMs and scripts supply strategy.

**Ship templates** (`scripts/shiptemplates/*.lua`, `scripts/api/shipTemplate.lua`): Lua builder calls: `setHull`, `setShields(...)`, `setSpeed(fwd, turn, accel)`, `setBeam(i, arc, dir, range, cycle, dmg)`, `setBeamWeaponTurret`, `setTubes(n, load)`, `setTubeDirection`, `setWeaponStorage`, `weaponTubeDisallowMissle`, `setJumpDrive`/`setWarpDrive`, `setCombatManeuver`, `addRoomSystem`/`addDoor`, radar trace, model, description; `copy()` for variants (e.g. Atlantis X23 → player Atlantis).

**Scenarios** (`scripts/scenario_*.lua`): header comments declare name, description, type and settings (`-- Setting[Enemies]: ...`). `init()` builds the map; `update(delta)` runs a state machine (e.g. `scenario_05_beacon.lua`: `missionStartState`, `missionRT4UnderAttack`, ...). Callbacks on destruction, scan, dock, comms. `victory("Faction")` ends the game; players lose when their faction is not the winner, or when the scenario declares it. Many scenarios have no end. Tutorials in `scripts/tutorial/`.

**Server options** (`gameGlobalInfo.h`): scanning complexity, hacking games/difficulty, beam/shield frequencies on/off, system damage on/off, which main-screen views are allowed, intercept all comms to GM.

### 1.4 Licensing facts

- EE code: GPL-2.0 (`LICENSE`, no per-file headers, no "or later" text found).
- SeriousProton: MIT.
- Model packs `packs/Angryfly.pack` (TurboSquid royalty-free) and `msgamedev-*.pack` (CGTrader): redistribution only unmodified, together with EE (`packs/License.txt`). **Not reusable.**
- Music and sfx: mix of CC-BY-3.0 and CC0 from OpenGameArt (`resources/music/source.txt`, `resources/sfx/source.txt`); fonts under their own OFL/Apache licences. Reusable only by going to the original sources with attribution, not via EE.

---

## 2. Section-by-section comparison with the spec

Each item: **EE** (how EE does it), **Δ** (what differs for us), **Options** (trade-offs), **Rec.** (recommendation).

### §2 Core requirements

**2.1 Cross-platform desktop clients.** EE: Windows, Linux, macOS, Android, one binary for server and all stations. Δ: same need. Options: (a) one Godot binary, role chosen at launch — simplest distribution; (b) separate dedicated-server build + client build — smaller attack surface, more pipelines; (c) web client for secondary stations — easy for tablets, but WebRTC/WebSocket path and performance limits. Rec.: (a), with a headless flag; revisit (c) only for touch stations later.

**2.2 LAN multiplayer.** EE: TCP + UDP broadcast discovery, server is any machine. Δ: same. Options: (a) Godot high-level multiplayer (ENet) + custom LAN discovery broadcast — fast to build; (b) custom UDP protocol with snapshot/delta compression — best control for many physics bodies; (c) WebSocket — needed only for browser clients. Rec.: (a) with our own command/snapshot message layer on top so we can swap transport.

**2.3 Mixed displays, keyboard/mouse, controllers, touch.** EE: mouse/touch-first 2D UIs, hotkeys, joystick for Helms/Weapons, on-screen keyboard. Δ: our Helm and Weapons need analogue 3D control; touch is awkward for 6-DOF. Options: (a) per-station input profiles, touch only for Engineering/Science/Relay/Captain — realistic; (b) full parity on all inputs — costly; (c) gamepad for Helm/Weapons, touch for the rest, keyboard/mouse everywhere — good default. Rec.: (c), with touch for Helm/Weapons as a "virtual stick" stretch goal.

**2.4 Offline multilingual TTS, no speech recognition.** EE: no TTS; text comms, optional voice chat. Δ: new subsystem. Options: (a) Piper (MIT, ONNX voices, many languages, fast on CPU) — best quality/latency offline; (b) eSpeak NG (GPL-3.0, robotic but tiny, ~100 languages) — fits retro style, but GPL binary must be a separate process; (c) pre-render all lines at build time with Piper and play files — zero runtime cost, but no dynamic text (names, numbers) unless templated; (d) OS TTS (SAPI/AVSpeech/speech-dispatcher) — inconsistent per platform. Rec.: (a) at runtime on the server or each client, with (c) caching for authored lines; check each Piper voice's licence (voices vary).

**2.5 No human GM; procedural adventures with handcrafted components + adaptive director.** EE: GM screen and hand-written Lua scenarios; procedural content only in some community scenarios. Δ: core difference. Options: (a) authored "encounter cards" (data) composed by a director on a sector graph (FTL/Slay-the-Spire-like) — predictable, testable; (b) fully systemic world sim with emergent missions — rich but hard to test and pace; (c) linear authored missions with random variants — cheapest, low replay value. Rec.: (a). Keep an optional, hidden "debug GM" console for testing, not for play.

**2.6 Session 20–40 min, earn resources, upgrade, death resets run.** EE: one scenario per session, reputation only, no upgrades between sessions. Options: (a) run = 4–6 sector "jumps", each 4–7 min, with a shop/dock between them — fits 20–40 min; (b) continuous open sector with timed escalation — closer to EE, harder to pace; (c) single long mission with checkpoints — contradicts reset rule. Rec.: (a).

### §3 Engine and architecture

**3.1 Engine.** EE uses its own C++ engine. Options: (a) Godot 4 (MIT, headless export, ENet, GDScript/C#) — preferred, fine for this scale; (b) Unity — mature tooling, licence/fee risk, closed engine; (c) Unreal — overkill for cartoon art, heavy. Rec.: (a), proved by a PoC that runs headless server + 2 clients with 50 rigid bodies at 30 Hz.

**3.2 One authoritative simulation; separation of concerns.** EE: ECS (components = data, systems = logic) with client views and replicated components; commands per station. Δ: same model, but EE replicates component fields generically; we need prediction for our own Helm (Newtonian control feels laggy otherwise). Options: (a) server-authoritative, no client prediction — simplest, fine on a LAN (<5 ms RTT); (b) client-side prediction for own-ship pose only — smoother at Helm on Wi-Fi; (c) deterministic lockstep — fragile with floats. Rec.: (a) first, measure on Wi-Fi, add (b) for the Helm camera only if needed. Write the simulation as an engine-light module (plain classes, fixed tick) so it can be unit-tested without rendering.

**3.3 Command validation.** EE trusts client minigame results. Options: (a) server validates every command (ranges, ownership by station, cooldowns), minigames run server-side or are verified by seed — robust; (b) trust LAN clients — faster. Rec.: (a) for gameplay commands; minigames send inputs, not results, where cheap.

**3.4 Data-driven definitions.** EE: Lua builder scripts for templates; scenarios in Lua. Options: (a) Godot `Resource` (.tres) files — editor-friendly, engine-bound; (b) JSON/YAML/TOML with JSON Schema validation — engine-agnostic, diffable, testable in CI; (c) Lua like EE — powerful but runtime code from data. Rec.: (b) for ships, weapons, subsystems, upgrades, enemies; dialogue in a dedicated format (see §7).

**3.5 Pinned versions, offline tools, procedural assets.** EE: CMake with pinned SP. Rec.: pin Godot version in `project.godot` and CI, vendor TTS models with checksums, generate ships from primitives (CSG/extruded shapes) to match "simple geometry".

### §4 Stations

**4.1 Helm.** EE: top-down heading click, impulse slider, warp/jump, combat maneuver, docking. Δ: forward cockpit view + 6-DOF Newtonian. Options: (a) full manual 6-DOF (pitch/yaw/roll + 3-axis translation) — authentic, steep learning; (b) flight-assist modes: "coupled" (assist cancels drift, like Elite Dangerous FA-on) and "decoupled" (pure Newtonian), toggled by Helm — accessible yet Newtonian; (c) waypoint autopilot with burn planning — good for travel, boring in combat. Rec.: (b) + (c) for travel; assist strength and max rotation are limited by Engineering power to maneuvering thrusters (pair Eng+Helm).

**4.2 Weapons.** EE: target select, auto-fire beams, tubes, frequencies, shields. Δ: manual aiming, switchable 3D views, physical mounts. Options: (a) per-mount turret cameras with free aim within cone — highly physical; (b) one "gunnery view" (third-person around the ship) with lead indicator; cursor aims all mounts that can reach — readable; (c) EE-like target-and-auto-fire with manual override — easiest. Rec.: (b) with mount cones drawn in 3D and a view switcher (forward, rear, target-locked, mount camera). Shields stay with Weapons or move to Engineering per §12 decision.

**4.3 Engineering.** EE: power 0–300%, coolant pool, heat, room-based repair crews. Δ: spec adds "impulse energy", "maneuverability". Options: (a) EE-like sliders per system + heat + coolant — proven; (b) discrete power pips (FTL-like) with a reactor cap and heat — faster, touch-friendly, readable; (c) node-graph power routing with breakers — deep, slower. Rec.: (b) with overcharge (pip above nominal = heat) and a 2D/3D cutaway for repair teams.

**4.4 Science.** EE: long-range radar, scan minigame, frequencies, raw signatures, database, probe view. Δ: "uncertain information" explicit; 3D sensor volume. Options: (a) scan ladder like EE (detect → classify → identify → analyse) with confidence values shown — clear; (b) signal-analysis puzzle (match spectrum bands) whose quality sets confidence — skill-based; (c) passive/active sensor modes (active ping reveals more but reveals you) — creates trade-offs with Helm/Weapons. Rec.: (a) + (c), with a short (b) minigame only for deep analysis.

**4.5 Relay.** EE: map, probes, waypoints, comms, hacking, alert, reputation. Δ: "mission opportunities" and procedural contracts. Options: (a) EE-like map + comms + probes, contracts via comms — proven; (b) split Comms and Relay — matches EE extras but needs 7 seats. Rec.: (a). Hacking optional (stretch).

**4.6 Captain (optional).** EE: no station. Options: (a) Captain board: map, crew status summary, set priorities/policies/orders that buff or highlight on other stations, accept contracts, alert level — useful, never required; (b) Captain only drives main screen — EE-style, weak; (c) no station, but any station can "propose" and others "ack" — no captain at all. Rec.: (a), with every Captain action also available somewhere else (Relay accepts contracts, any station sets alert), so absence only removes bonuses.

**4.7 Independent and combinable.** EE: fixed combos (Tactical, Engineering+, Operations, Single pilot) plus multi-select of positions per client. Options: (a) fixed combo screens like EE — tuned layouts; (b) composable panel layout: any set of stations on one client, tabs or split panes — flexible, harder to make good; (c) both: curated combos for 1–4 players + tabbed fallback for others. Rec.: (c). Plus automation for unmanned stations (§12).

### §5 Flight, combat, damage

**5.1 3D Newtonian movement.** EE: 2D, velocity locked to heading, turn rate. Options: (a) Godot `RigidBody3D` with forces/torques — quick, less deterministic, harder to test; (b) custom integrator (semi-implicit Euler at fixed 60 Hz) for ships and projectiles, Godot physics only for collision queries — deterministic and unit-testable; (c) Jolt via Godot 4.4+ — better perf, same caveats as (a). Rec.: (b) for ship and projectile motion with Godot shape queries for collision.

**5.2 Mount geometry and arcs.** EE: mounts have a 2D arc and direction; position is visual only; optional turret rotation. Δ: physical position and orientation, 3D cones, occlusion by own hull. Options: (a) cone per mount (half-angle + direction) + range, no occlusion — simple, testable; (b) cone + turret traverse/elevation limits + rotation speed — richer, harder; (c) (b) plus hull occlusion by raycast — realistic, costly. Rec.: (b) without occlusion for the first slice ((a) for fixed mounts).

**5.3 Arsenal.** EE: beams (frequency), Homing, Nuke, EMP, Mine, HVLI. Options: map to our set: projectile cannons (ballistic, manual lead), energy beams (hitscan, heat/energy, frequency), missiles (guided, need lock from Weapons, ammunition), torpedoes (slow, big, need Science-provided weak point or lock, can be shot down), mines/EMP as upgrades. Rec.: start with one projectile cannon and one beam; missiles and torpedoes after the slice.

**5.4 Independent subsystem damage.** EE: random system hit per hull hit plus optional targeted system; effectiveness = power × health; overheating damages. Δ: spec wants direct, legible consequences. Options: (a) EE-like location-free random damage — simple, feels arbitrary; (b) hit-location: subsystems have positions on the hull; hits damage the nearest — physical and readable, synergy with 3D; (c) (b) + component-level faults (e.g. "coolant leak", "sensor misalignment") with specific fixes — richer Eng+Sci play. Rec.: (b) for the slice, (c) later.

**5.5 Immediate visible feedback, e.g. shields at 40%.** EE: alert-level overlays, hull damage flash, sounds; no thresholds. Options: (a) central event bus with typed events + per-station subscriptions and thresholds in data — testable; (b) ad-hoc UI checks — fast, untestable. Rec.: (a), with priority classes that feed both UI and the TTS queue.

**5.6 Enemy AI.** EE: order-based behaviours; target scoring; fighter/missile-volley/evasion variants; no flanking or coordination. Options: (a) behaviour trees per ship + simple squad coordinator (assign flank slots, focus fire) — industry standard; (b) utility AI (score actions) — adaptive, harder to debug; (c) EE-like orders + scripted variants — fast start. Rec.: (c) for the slice (attack, keep-range, retreat at hull <25%), then (a) with a squad layer. AI reads only what its sensors know (no cheating), consistent with "never secretly manipulate".

**5.7 No secret manipulation.** EE: GM can do anything; scenarios often spawn directly. Δ: our director may choose events but not change rules. Rec.: director acts only through visible world events (spawns at range, arrivals via jump flashes, offers), every director decision logged and shown in an end-of-run debrief.

### §6 Pairwise cooperation

EE has strong asymmetric information (Science sees frequencies, Weapons sets them; Relay sees far, Helms sees near; Engineering sees health) but no designed coverage of every pair. We design shared systems first, then pair mechanics on them (section 3).

Shared systems proposed:
1. **Contact knowledge model** (per contact: detection, class, identity, intent, vulnerabilities, each with a confidence and the station that produced it).
2. **Power and heat bus** (reactor output, pips per system, heat per system, coolant).
3. **Marks and designations** (any station can tag a contact/point; tags carry type: target, avoid, investigate, dock, priority 1–3).
4. **Orders and policies** (rules of engagement, ammo policy, priorities; set by Captain, or by any station as a proposal when no Captain).
5. **Comms and contracts** (dialogue trees, offers, reputation/credits).
6. **Ship condition model** (subsystem health, faults, repair jobs, resources: ammo, spares, probes).
7. **Event bus and alert priorities** (UI and TTS).

### §7 Missions and progression

**7.1 Enemy waves and rescue first.** EE: `scenario_03_waves.lua` (endless waves), `scenario_05_beacon.lua` (escort/rescue state machine). Options: (a) build both as compositions of components (spawn wave, protect target, retrieve pod, escort, timer) — proves the component model; (b) hand-script them — faster first, harder later. Rec.: (a).

**7.2 Reusable mission components and branching.** EE: Lua state machines per scenario. Options: (a) data-defined state machines (YAML: states, triggers, actions) + small expression language — testable, no arbitrary code; (b) embedded scripting (GDScript or Lua) per mission — flexible, harder to sandbox and test; (c) dialogue tool (Ink or Yarn Spinner) for comms + data FSM for world — best authoring for branching text. Rec.: (c): Ink (MIT) or Yarn (MIT) for dialogue, YAML FSM for encounters.

**7.3 Adaptive director.** EE: none (GM). Options: (a) intensity curve director (Left 4 Dead-style: build-up, peak, relax) choosing from encounter cards by tags and crew stress signals — proven; (b) difficulty-score budget per sector from ship strength — fair, predictable; (c) both: budget sets the menu, intensity picks timing. Rec.: (c), with all inputs observable (hull, ammo, time) and no stat changes.

**7.4 Money, salvage, repairs, upgrades, distinct builds.** EE: reputation buys ammo/reinforcements; no upgrades (`scripts/player_ship_upgrade_downgrade_path_scenario_utility.lua` exists in community scenarios). Options: (a) slot-based upgrades with trade-offs (e.g. more power vs more heat), 3–4 archetypes emerging (glass cannon, tank, stealth/sensor, missile boat) — clear builds; (b) linear stat upgrades — no distinct builds; (c) crew-perk tree per station — rewards each player personally. Rec.: (a) + a light (c) later.

**7.5 Death resets run.** EE: none. Rec.: run state is one object owned by the simulation; reset = discard and reload from definitions; test it.

### §8 Audio and presentation

**8.1 TTS for radio, computer, alerts, crew.** EE: none. Options: (a) per-NPC voice + radio filter; ship computer with a fixed voice; priority queue with interrupt — required; (b) TTS only for computer alerts, NPCs as text — cheaper. Rec.: (a), with three channels (critical alert, ship computer, radio) and ducking.

**8.2 Multiple languages.** EE: gettext-style locale files (`scripts/locale`, `resources/locale`, `tr()` everywhere). Options: (a) Godot translation (PO/CSV) for UI + per-language TTS voices; (b) English only at launch. Rec.: (a) with 2–3 languages where Piper has good voices (§12 decision).

**8.3 Structured dialogue choices; TTS prioritisation.** EE: reply buttons on Relay, text only. Rec.: Relay (or Captain) picks replies; NPC line plays via TTS, text shown on comms log; critical alerts interrupt radio and radio resumes or summarises.

**8.4 Retro cartoon art.** EE: realistic-ish licensed models. Rec.: own procedural/low-poly assets; flat shading, outlines, bold faction colours; silhouette tests.

### §9 First playable milestone (EE features to reuse as ideas)

| Milestone item | EE equivalent | Our approach |
|---|---|---|
| Newtonian ship | none (2D velocity lock) | custom integrator + flight assist |
| Helm/Weapons/Engineering UIs | crew6 screens | new 3D-first screens (section 4) |
| One enemy with basic AI | `ai/ai.cpp` default (roam/attack) | attack, keep range, retreat |
| Manual aiming + constrained mount | beam arcs + tube direction | cone mount + gunnery view |
| Damageable + repairable subsystem | system health + repair crews | engine (impulse) subsystem + repair job |
| Eng+Helm loop | power to impulse/maneuver | power pips + overcharge window + boost (section 3, pair 3) |
| Notifications + sync | alert overlay, replication | event bus + snapshot |
| Clear outcome + reset | `victory()` | win/lose screen + run reset |
| Tests + launch docs | none automated | headless sim tests |

---

## 3. The 15 station pairs

Format per pair: **EE** (what EE does), **Designs** (2–3), **Rec.** Each design lists: independent ability, asymmetric info, cooperative advantage, feedback, failure cost / fallback.

### 3.1 Relay + Science
- **EE:** Relay launches probes and links one to Science, which gets a long-range view from it; Relay's short-range sharing reveals contacts Science can then scan; nebulae block Science, probes see inside.
- **D1 Probe-assisted analysis:** Relay places probes (3D positions, limited stock); Science can run full analysis only on contacts within its own range *or* within a probe's sensor bubble. Info: Relay sees probe coverage map; Science sees signal quality. Advantage: scan far contacts, inside nebulae, behind planets. Feedback: coverage volume on both screens, quality meter. Failure: Science must ask Helm to close distance (slower, riskier).
- **D2 Triangulation:** passive signals (distress beacons, cloaked ships) produce only a bearing; two bearings (ship + probe) give a position. Relay positions the probe; Science reads bearings and marks the fix. Fallback: Helm moves the ship to get the second bearing (costs time).
- **D3 Comms unlock:** Science's analysis of an anomaly/ship reveals data (language, transponder code) that unlocks extra dialogue options for Relay (e.g. bluff a code, offer help to a damaged ship). Fallback: base dialogue only.
- **Rec.:** D1 + D3 (both use the knowledge model); D2 as a mission component later.

### 3.2 Science + Weapons
- **EE:** Science's full scan shows the target's shield frequency curve; Weapons sets beam frequency (0–20) for up to 1.5× damage; Weapons can choose a target subsystem.
- **D1 Frequency tuning (EE idea, reworked):** Science identifies shield harmonics with a confidence band; Weapons sets beam phase. Correct match = bonus damage; wrong = penalty. Fallback: neutral damage.
- **D2 Weak-point designation:** Science analyses a target and reveals weak points (exposed reactor vent on its 3D model, engine block); they appear as hit zones on Weapons' gunnery view only when Science has shared them. Hitting them gives subsystem damage. Fallback: hits land on random subsystems.
- **D3 Damage-type matching:** enemies have armour/shield types (ablative, energy-absorbing); Science identifies the type; Weapons picks ammo/beam mode. Fallback: generic ammo, lower efficiency.
- **Rec.:** D2 (fits manual 3D aiming, physical hit locations) + D3; D1 optional upgrade path (keeps a nod to EE).

### 3.3 Engineering + Helm (milestone loop)
- **EE:** Engineering's power to Impulse/Maneuver changes speed/turn rate; combat maneuver heats both; jump charge uses energy.
- **D1 Thrust budget:** Helm's max linear thrust and angular acceleration scale with power pips on Engines and Thrusters. Engineering can overcharge (extra pip) for a limited window that builds heat. Helm sees available thrust envelope; Engineering sees heat and reactor load. Advantage: sharper maneuvers when needed. Feedback: Helm thrust gauge glows when boosted; Eng heat bar rises; TTS "Thrusters overcharged". Failure: overheat damages thrusters; fallback is nominal thrust.
- **D2 Boost request/ack:** Helm presses "Request boost" (shows on Eng); Engineering commits a capacitor dump for 5 s of high thrust (cooldown, heat). Without Eng, Helm can trigger a weaker auto-boost.
- **D3 Flight-assist cost:** flight assist (drift cancel) consumes thruster power; Engineering balances assist vs shields. Low power → assist degrades, ship drifts.
- **Rec.:** D1 + D2 for the milestone (simple, testable: thrust = f(power, health, heat)).

### 3.4 Helm + Weapons
- **EE:** Weapons' beams only fire in arcs; Helms turns the ship; Tactical combines both.
- **D1 Arc alignment:** fixed/limited mounts mean Helm must point the ship; Weapons sees which mounts can reach the target and requests "bring port side to bear". Helm sees arc overlays for the selected target in the cockpit HUD. Fallback: turrets with small traverse still fire, less damage.
- **D2 Firing solution window:** projectile lead depends on relative velocity; Helm matching velocity ("stabilise") increases Weapons' accuracy indicator; evasive maneuvers lower it but also lower incoming hit chance. Explicit trade-off.
- **D3 Attack-run mode:** Helm commits to a run (locks course for N seconds) giving Weapons a stable solution and damage bonus; aborting cancels it.
- **Rec.:** D1 + D2 (pure physics, no extra UI rules).

### 3.5 Helm + Science
- **EE:** Science scanning range is fixed; Helms must close distance; nebulae force approaches.
- **D1 Scan geometry:** sensor quality depends on distance and aspect (e.g. scanning the engine side reveals drive data; occlusion by asteroids); Science marks the ideal position as a 3D waypoint; Helm flies there. Fallback: slower, lower-confidence scan.
- **D2 Hazard pathing:** Science maps hazard fields (radiation, gravity wells) with uncertainty; Helm sees them only after Science shares; flying blind costs damage.
- **D3 Active ping:** Science's active ping reveals more but gives away position; Helm chooses when to cut thrust (lower signature) to stay hidden.
- **Rec.:** D1 + D2.

### 3.6 Helm + Relay
- **EE:** Relay places waypoints that appear on Helms' radar; Relay sees far, Helms sees near; docking needs Helms.
- **D1 Route plotting:** Relay draws a route (3D waypoints) through known hazards on the map; Helm sees it as a ribbon in the cockpit and can engage autopilot to follow at lower efficiency. Fallback: Helm navigates by compass.
- **D2 Docking approach:** stations require clearance (Relay negotiates) and approach vectors (shown to Helm); docking without clearance is refused or costs reputation.
- **D3 Intercept plotting:** Relay computes intercept points for moving contacts using long-range tracks; Helm executes. Without, Helm chases tail.
- **Rec.:** D1 + D2.

### 3.7 Weapons + Engineering
- **EE:** beams cost energy and heat per shot; Engineering powers beams/tubes; shields drain energy; reload time scales with tube power.
- **D1 Weapon power and heat:** beams draw from the reactor and add heat; Engineering's pips set recharge/cycle time; Weapons sees heat per mount and a "throttle" warning. Overheat locks a mount. Fallback: slower fire.
- **D2 Capacitor charge for heavy shots:** torpedo or charged beam requires Engineering to divert power to a capacitor; Weapons fires when charged.
- **D3 Shields vs guns:** shared power budget; Engineering shifts between shields and weapons on request (shown as a "Weapons requests power" chip).
- **Rec.:** D1 + D3 (single power bus), D2 as an upgrade.

### 3.8 Weapons + Relay
- **EE:** Relay sees faction and comms; firing on neutrals changes relations (`didAnOffensiveAction`); Relay can hack enemy systems to weaken them.
- **D1 Intent and IFF:** contacts carry intent (hostile, neutral, surrendering, unknown); Relay confirms through comms or transponder; Weapons sees Relay's IFF tag; firing on neutrals/surrendered costs reputation and contracts. Fallback: Weapons fires on "unknown" at its own risk.
- **D2 Target priority from missions:** Relay marks mission-critical targets (e.g. "disable, do not destroy" for capture contracts); disabling them gives bonus rewards.
- **D3 Hacking support:** Relay jams or hacks a target subsystem (minigame or timer), lowering its shields for a window Weapons can exploit.
- **Rec.:** D1 + D2; D3 as stretch.

### 3.9 Engineering + Science
- **EE:** none directly (Science sees enemy systems, Engineering sees own).
- **D1 Fault diagnosis:** some damage arrives as unknown faults ("power fluctuation in sector 3"); Science runs an internal scan to identify the cause (e.g. coolant leak vs. hacked controller vs. radiation); the correct repair is then fast; wrong repair wastes time. Fallback: Engineering can brute-force repair slowly.
- **D2 Environmental hardening:** Science measures radiation/ion storm intensity and type; Engineering tunes shield mode or allocates power to hardening for that type.
- **D3 Sensor power:** Science's sensor range/resolution depends on Engineering's power to sensors.
- **Rec.:** D1 + D3.

### 3.10 Engineering + Relay
- **EE:** docking repairs hull, restocks probes; Relay buys ordnance with reputation; supply drops.
- **D1 Repair/resupply quotes:** Relay gets offers from stations (repair X for Y credits, time to dock); Engineering sees what is broken and estimates own repair time and spare parts; together they decide. Fallback: Relay accepts blindly (overspend) or Engineering repairs slowly in field.
- **D2 Contract feasibility:** mission offers show requirements (e.g. "tow cargo: needs tractor power 2"); Engineering confirms/refuses.
- **D3 Emergency assistance:** Relay calls a tug/repair drone; Engineering prepares a docking clamp power state.
- **Rec.:** D1 + D2.

### 3.11 Captain + Helm
- **EE:** captain talks; main screen views.
- **D1 Movement orders:** Captain sets an order on the map (intercept, hold, retreat to, rendezvous); Helm sees it as a HUD order with a "comply/acknowledge" button; complying grants a small bonus (e.g. crew focus: reduced heat during the order) and logs to debrief. Fallback (no Captain): Helm or Relay sets the same marker without the bonus.
- **D2 Retreat threshold:** Captain sets a retreat condition (hull <40% or objective done); when triggered, Helm gets a pre-plotted escape vector.
- **Rec.:** D1 (generic orders system shared with other Captain pairs).

### 3.12 Captain + Weapons
- **EE:** none.
- **D1 Rules of engagement:** Captain sets ROE (weapons hold, return fire, free) and ammo policy (conserve torpedoes); Weapons' UI greys/flags actions against policy (still allowed, but violations show and may cost reputation/morale).
- **D2 Priority targets:** Captain designates P1/P2 targets; Weapons gets damage bonus vs. P1 (focus fire).
- **D3 Collateral constraints:** in missions with civilians, Captain sets no-fire zones; Weapons sees them in 3D.
- **Rec.:** D1 + D2 (both on the orders/policies system).

### 3.13 Captain + Engineering
- **EE:** self-destruct confirmation spans stations; no captain role.
- **D1 Emergency authorisations:** some actions need two keys: reactor overload, jettisoning a damaged module (loses an upgrade but stops a fire), using emergency reserve power. Captain authorises; with no Captain, any second station can co-sign (EE self-destruct pattern).
- **D2 Damage-control priorities:** Captain orders repair order (engines first); repair teams work faster on the captain's priority.
- **Rec.:** D1 (forces a deliberate decision) + D2.

### 3.14 Captain + Science
- **EE:** none.
- **D1 Risk assessment:** Science reports on anomalies with an uncertainty estimate (e.g. "70% salvage, 30% radiation hazard"); Captain decides to investigate deeper (costs time, risk) or leave; reward scales. Without Captain, Science decides.
- **D2 Research priorities:** Captain chooses which discovered data to "bank" for credits vs use for current tactical info.
- **Rec.:** D1 (uses knowledge model + director events).

### 3.15 Captain + Relay
- **EE:** Relay runs all comms; captain decides by voice.
- **D1 Negotiation stance:** Captain chooses stance (friendly, firm, threatening) which filters the dialogue options Relay can pick, and changes outcomes; Relay alone uses a neutral stance.
- **D2 Contract board:** Relay receives offers; Captain accepts/declines; accepted contracts become mission branches. Without Captain, Relay accepts.
- **Rec.:** D2 + D1.

**Testing note.** Each pair maps to a test: "with both stations acting, metric X improves vs. one station" (e.g. thrust envelope, hit rate on weak points, scan confidence). That gives the spec's "tests for all 15 pairs" a concrete form.

---

## 4. Proposed station UI

General: 16:9 layout first, scalable to tablets; consistent top bar (hull, shields, reactor, alert level, station name, mission timer); event toasts at top-right; colour-blind-safe palette; every critical alert both visual and audio.

### 4.1 Helm
- **Recommended:** full-screen forward cockpit 3D view; HUD with velocity vector (prograde/retrograde markers), target marker, Relay route ribbon, arc hints; bottom-left: thrust envelope gauge (power-limited), flight-assist mode; bottom-right: mini radar sphere (3D "Elite" scanner disc); right edge: dock/autopilot/boost buttons.
  - KB/M: WASD translate, QE roll, mouse pitch/yaw, Shift boost, Space all-stop (assist), Tab assist toggle.
  - Controller: left stick pitch/yaw, right stick strafe, triggers forward/back, bumpers roll, A boost.
  - Touch: left virtual stick attitude, right stick translate, throttle slider, big buttons; recommended only with assist on.
- **Alt A:** chase camera (third person) instead of cockpit — better spatial awareness.
- **Alt B:** split: cockpit top 70%, orbital map bottom 30% — better for navigation-heavy missions.

### 4.2 Weapons
- **Recommended:** gunnery view (third-person orbit camera behind ship) with mount cones, lead reticle, target hit zones (from Science); left panel mount list (state, heat, ammo, ready); right panel target card (IFF from Relay, shields facing, priority from Captain); view switcher (forward / target-lock / per-mount).
  - KB/M: mouse aims, LMB fire group 1, RMB group 2, 1–4 select groups, R reload type, T cycle targets.
  - Controller: right stick aim (aim assist), triggers fire, d-pad groups.
  - Touch: tap target, drag to aim, fire buttons; usable but less precise.
- **Alt A:** per-mount turret camera full-screen (most immersive, less awareness).
- **Alt B:** EE-like top-down tactical radar with lead markers + small 3D inset (accessible for touch).

### 4.3 Engineering
- **Recommended:** left: ship cutaway (low-poly, rotatable) showing subsystems coloured by health/heat and repair teams; centre: power pip columns per system with reactor cap and overcharge row; right: heat/coolant and faults list with repair job queue; request chips from other stations (e.g. "Helm requests boost").
  - KB/M: click/drag pips, number keys select system, +/− pips, drag teams.
  - Controller: d-pad select, A/B add/remove pips, bumper switch panel.
  - Touch: excellent fit (tap pips, drag teams).
- **Alt A:** EE-like slider rows (power 0–300%, coolant) — finer control.
- **Alt B:** node graph routing (reactor → buses → systems) — deeper, slower.

### 4.4 Science
- **Recommended:** centre: 3D sensor volume (rotatable sphere/disc) with contacts as icons sized by confidence; left: contact list sorted by threat/interest; right: contact card (class, identity, intent, vulnerabilities with confidence bars, database text); bottom: scan controls (passive/active toggle, analyse button, short signal-matching minigame), "share to" buttons (Weapons weak points, Helm scan position, Relay data).
  - KB/M: click contacts, scroll zoom, S scan, A active ping.
  - Controller: stick cursor with snap-to-contact, A scan.
  - Touch: good fit.
- **Alt A:** EE-like 2D long-range radar with altitude stalks — simpler, readable.
- **Alt B:** spectrum-analysis view dominant (puzzle-first), map secondary.

### 4.5 Relay
- **Recommended:** sector map (2.5D: plane + altitude stalks) with probe coverage bubbles, routes and marks; right: comms panel (current channel, NPC line text, reply choices, contract offers); left: probes (stock, launch), contacts sorted by faction/intent, reputation/credits; bottom: log.
  - KB/M: click map to place probe/waypoint, drag routes, 1–4 dialogue choices.
  - Controller: cursor + radial menu.
  - Touch: excellent fit.
- **Alt A:** comms-dominant layout (map small) for negotiation-heavy missions.
- **Alt B:** split Relay into Map and Comms tabs on a single small screen.

### 4.6 Captain
- **Recommended:** top: mission and contract board with objectives and branches; centre: strategic map with orders (intercept, hold, retreat, rendezvous), priority targets, no-fire zones; right: crew status chips per station (manned/automated, alerts, requests) and authorisation queue (emergency actions awaiting co-sign); ROE and ammo policy toggles; alert-level switch; main-screen view control.
  - KB/M, touch: both good; controller: radial menus.
- **Alt A:** main screen only (EE style) with a handheld/tablet "orders" panel.
- **Alt B:** no separate screen; Captain panel as an overlay tab on any station.

### 4.7 Shared main screen (optional)
A shared big screen (TV) showing a cinematic external view or tactical view, controllable by Captain (or anyone if no Captain). Mirrors EE's main screen; useful in same-room play.

---

## 5. Decisions for the product owner

Format: question; options with one-line trade-off; **(Recommended)** marks one.

**Players and hosting**

1. **Maximum player count per ship?**
   - A. 6 (one per station) — simple, matches spec. **(Recommended)**
   - B. 7 (6 + main-screen operator) — more seats, little gameplay.
   - C. 8+ with duplicated stations (two gunners) — more fun at parties, more UI and balance work.
2. **Multiple player ships in one session?**
   - A. One ship only. **(Recommended)** — focus.
   - B. Up to 2 ships co-op — great for groups, doubles balancing and networking scope.
   - C. PvP between ships — needs separate design.
3. **Hosting model?**
   - A. Any player machine runs the server in-process ("host" button) plus optional headless. **(Recommended)** — easiest setup.
   - B. Dedicated headless server only — cleaner, needs an extra machine.
   - C. Peer-to-peer — no clear authority; contradicts spec.
4. **LAN discovery?**
   - A. UDP broadcast + manual IP fallback. **(Recommended)** — works on most LANs.
   - B. Manual IP only — simplest, worse UX.
   - C. QR code on host screen for tablets — nice for touch, extra work.
5. **Internet play?**
   - A. Not supported (LAN only). **(Recommended)** — matches spec, no NAT work.
   - B. Direct IP over internet/VPN, unsupported but not blocked — free.
   - C. Relay/matchmaking — significant work and cost.
6. **Client prediction for Helm?**
   - A. None at first; add only if Wi-Fi tests show lag. **(Recommended)**
   - B. Predict own ship from day one — smoother, more complex.

**Stations and crew**

7. **Absent-station behaviour?**
   - A. Automation at reduced effectiveness (auto-power, auto-repair, auto-target nearest, auto-scan slow), any present player can take over via tabs. **(Recommended)** — playable with 2–5.
   - B. Fixed curated combos (Tactical, Operations etc.) only — tuned UX, inflexible.
   - C. Absent stations are simply off — punishing.
8. **Station combinations?**
   - A. Curated combos for common counts (1: Single pilot, 2: Pilot+Ops, 3: Helm/Weapons/Eng+Sci+Relay, 4–5 variants) plus tabbed any-set fallback. **(Recommended)**
   - B. Tabs only — cheap, worse ergonomics.
   - C. Curated combos only.
9. **Where do shields live?**
   - A. Engineering (power and facing allocation), Weapons sees them. **(Recommended)** — Weapons already busy with manual aim.
   - B. Weapons (EE default).
   - C. Helm (shield facing tied to attitude).
10. **Captain powers when present?**
    - A. Orders/policies with small bonuses + co-sign authority + contract acceptance (duplicated elsewhere). **(Recommended)**
    - B. Information-only (overview + main screen) — never feels needed.
    - C. Exclusive powers (only Captain accepts contracts) — conflicts with "never mandatory".
11. **Shared main screen?**
    - A. Optional external/tactical view, controlled by Captain or any station. **(Recommended)**
    - B. None.
12. **Information-sharing rules?**
    - A. Strict asymmetry: each station sees only its domain plus explicitly shared items (marks, IFF, weak points); a shared main screen shows only exterior. **(Recommended)** — drives talk.
    - B. Soft asymmetry: everyone sees a basic map, details per station — easier for new players.
    - C. Configurable per difficulty (A on hard, B on easy) — flexible, more testing.
13. **Hacking at Relay?**
    - A. Later stretch goal. **(Recommended)**
    - B. Include in v1 with one minigame.
    - C. Never.
14. **Minigames (scan, hack) or not?**
    - A. Short, optional skill layers (skip = slower timer). **(Recommended)**
    - B. Mandatory minigames (EE style).
    - C. No minigames; all timer-based.

**Flight and combat**

15. **Flight model default?**
    - A. Newtonian with flight assist on by default, toggleable decoupled mode. **(Recommended)**
    - B. Pure Newtonian always — authentic, steep.
    - C. Arcade (velocity follows heading) — EE-like, violates spec.
16. **Weapon aiming model?**
    - A. Manual aim in a gunnery view with lead indicator and light aim assist on controller. **(Recommended)**
    - B. Full manual, no assist.
    - C. Target lock + auto-fire with manual override.
17. **Subsystem damage model?**
    - A. Hit-location: nearest subsystem to impact takes damage. **(Recommended)**
    - B. Random system per hull hit (EE).
    - C. Hit-location plus typed faults needing diagnosis (later).
18. **Repair model?**
    - A. Repair teams assigned by Engineering, travel inside a cutaway, with spare parts as a resource. **(Recommended)**
    - B. Click-to-repair timers.
    - C. Automatic repair with power.
19. **Include frequency-matching (EE beams/shields)?**
    - A. No; use weak points and damage types instead. **(Recommended)** — fits 3D aiming.
    - B. Yes, as in EE.
    - C. As an upgrade-unlocked mechanic.
20. **FTL/travel between areas?**
    - A. Sector map jumps between encounters (no in-encounter jump). **(Recommended)**
    - B. Jump drive inside the encounter (EE).
    - C. Warp drive (EE).
21. **Friendly fire and collisions?**
    - A. Both on, with clear warnings. **(Recommended)**
    - B. Both off.
    - C. Collisions on, friendly fire off.

**Missions, director, progression**

22. **Interpretation of the 20–30% death-risk target?**
    - A. Per run: 20–30% of runs by an average crew end in destruction (measured in playtests). **(Recommended)**
    - B. Per encounter: 20–30% chance of losing the ship each fight — far too punishing over a run.
    - C. Per "risky choice" offered: 20–30% failure on optional high-risk events.
23. **Victory/defeat model?**
    - A. Run victory = complete the final sector objective; defeat = ship destroyed or crew abandons; mid-run mission failures cost rewards but continue the run. **(Recommended)**
    - B. Score-based endless waves only.
    - C. Per-mission win/lose, no run arc.
24. **Can the crew abandon/retreat from a run?**
    - A. Yes, ends the run with partial score. **(Recommended)**
    - B. No.
25. **Permanent unlocks (meta-progression)?**
    - A. Cosmetic + unlockable starting ships/encounter pools, no power creep. **(Recommended)**
    - B. None.
    - C. Permanent stat upgrades.
26. **Scenario authoring format?**
    - A. YAML/JSON encounter state machines + Ink (or Yarn) dialogue, validated in CI. **(Recommended)**
    - B. Embedded scripting (GDScript or Lua).
    - C. Godot scenes/resources edited in the editor.
27. **Director transparency?**
    - A. Director decisions logged and shown in end-of-run debrief. **(Recommended)**
    - B. Hidden but rule-abiding.
28. **Difficulty selection?**
    - A. Crew picks Easy/Normal/Hard at run start (changes encounter budget, not hidden stats). **(Recommended)**
    - B. Single difficulty, director adapts within rules.
29. **Economy?**
    - A. One currency (credits) + salvage converted at stations + reputation per faction. **(Recommended)**
    - B. Credits only.
    - C. Multiple materials (crafting).

**Audio, language, art**

30. **TTS engine?**
    - A. Piper at runtime, pre-cached authored lines. **(Recommended)**
    - B. eSpeak NG (retro robotic, GPL-3.0 separate process).
    - C. Pre-rendered only.
31. **Where does TTS run?**
    - A. On each client (each station plays its own relevant lines; the main screen/host plays shared radio). **(Recommended)** — less audio clutter, per-station languages possible.
    - B. Host only, broadcast audio.
32. **Initial TTS languages?**
    - A. English + Portuguese + Spanish. **(Recommended)** — good Piper voices, owner-relevant.
    - B. English only.
    - C. English + German + French.
33. **Per-player language?**
    - A. One language per session. **(Recommended)** — less testing.
    - B. Per station.

**Reference and licensing**

34. **EmptyEpsilon compatibility expectations?**
    - A. None: no file, protocol or scenario compatibility; ideas only. **(Recommended)** — avoids GPL and 2D constraints.
    - B. Import EE ship templates as data (conversion tool) — useful content, licence questions.
    - C. Network/HTTP API compatibility for EE hardware/DMX setups.
35. **Our project's licence?**
    - A. MIT or similar permissive, with no EE code or assets. **(Recommended)**
    - B. GPL-3.0 (could reuse GPL code; obliges source release).
    - C. Proprietary/closed.
36. **Asset sourcing?**
    - A. Procedural/own low-poly only; CC0 sounds; track provenance in a manifest. **(Recommended)**
    - B. Also CC-BY assets with attribution file.

**Input and platforms**

37. **Target platforms for v1?**
    - A. Windows + Linux + macOS desktop. **(Recommended)**
    - B. Add Android tablets for non-flight stations.
38. **Touch support depth?**
    - A. Touch-first for Engineering/Science/Relay/Captain; Helm/Weapons touch later. **(Recommended)**
    - B. Touch for all stations in v1.

---

## 6. GPL-2.0 implications and licence stance

- **Ideas, mechanics, rules, numbers as game design** are not protected by copyright; re-implementing "power 0–300% with heat" or "scan ladder" in our own code is fine. Specific tuned constants are facts/ideas too, but we should still pick our own values because our physics differs.
- **Code:** copying or translating EE source (C++, Lua scripts including `comms_station.lua`, ship templates, scenario scripts, shaders) into our project would make our distribution a derivative work under GPL-2.0: we would have to license the combined work under GPL-2.0, ship source, and could not combine it with GPL-incompatible code (e.g. Apache-2.0 under GPL-2.0-only is incompatible). Avoid: no copy-paste, no line-by-line translation into GDScript, no port of the frequency curve function.
- **Text and data:** EE ship descriptions, database entries, scenario dialogue and tutorial text are covered by the same licence; write our own.
- **Assets:** EE model packs are proprietary (TurboSquid/CGTrader terms; redistribution only with EE): never reuse. Music/sfx are CC-BY-3.0/CC0 from OpenGameArt; if we want any, fetch from the original source and attribute — not via EE. Fonts: use their own OFL/Apache licences directly if needed.
- **SeriousProton** is MIT: could be reused with attribution, but we are on Godot, so not relevant.
- **Clean-room practice:** keep the reference clone outside the repo; the person/agent writing code works from this report (ideas) rather than open EE files; record in a `PROVENANCE.md`/`THIRD_PARTY.md` every reused asset and dependency licence (Godot MIT, Piper MIT + per-voice licences, Ink/Yarn MIT, eSpeak NG GPL-3.0 if used as a separate process).
- **Recommended stance:** permissive licence (MIT) for our code, no EE code or assets, ideas-only reuse documented as "reproduced / redesigned / omitted" (spec §10). Revisit only if the owner wants to import EE content (decision 34-B), which would push us to GPL.

### Reproduced / redesigned / omitted (spec §10 record, first pass)

| EE mechanic | Status |
|---|---|
| Server-authoritative sim, station clients, typed commands | Reproduced (as an idea) |
| Power/heat/coolant per system | Redesigned (pips + overcharge) |
| Repair crews in rooms | Redesigned (3D cutaway, spare parts) |
| Scan ladder | Redesigned (confidence values, passive/active) |
| Beam/shield frequencies | Omitted for v1 (weak points/damage types instead) |
| Missile types (homing, nuke, EMP, mine, HVLI) | Redesigned (missiles, torpedoes, cannons; mines/EMP as upgrades) |
| Probes linked to Science | Reproduced |
| Waypoints Relay→Helm | Reproduced (3D routes) |
| Reputation currency | Redesigned (credits + per-faction reputation) |
| Docking resupply | Reproduced |
| Jump/warp drives | Redesigned (sector-map travel) |
| Hacking minigames | Deferred |
| Self-destruct cross-station codes | Redesigned (co-sign authorisations) |
| Alert levels | Reproduced |
| Game Master | Omitted (director + debug console) |
| Combat maneuver boost/strafe | Redesigned (Eng+Helm boost) |
| AI orders and target scoring | Reproduced as a starting point; extended with squads |
| 2D movement | Omitted (3D Newtonian) |
| Main screen | Reproduced (optional) |
| Hardware/DMX, HTTP API, voice chat | Omitted |
