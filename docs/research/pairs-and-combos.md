# Full Theta: the 15 pairs and the curated combos

> Historical. Superseded by spec 05 and 07 and by D66–D102: P12 is verbal only (D68, no status report), there are no 1–2-player crews or 3-station views (D66, D76), and joint views are modal (D95). Read the spec, not this file, for current rules.

Scope: the six functional stations of D50–D57: Helm (H, movement), Weapons (W, damage), Engineering (E, systems), Science (S, information gathering, scan and hack), Relay (R, tactical view of the universe) and Comms (C, story of the universe). The Captain is optional, information only (D15, D23, D54) and sits outside the pairs; the Captain can still place marks and pings (D44). This file supersedes the pair list in emptyepsilon.md §3, which predates the Relay/Comms split and the Captain change. Callouts, radar and marks follow station-ui.md §1 (D42–D45). Multi-ship play (D11, D21): every system below is keyed by ship and faction, so in PvP each crew cooperates inside its own ship and competes through the same systems.

## 0. Shared simulation systems

The 15 pairs run on six shared server systems plus the physics substrate. No pair owns a private minigame; the two minigames (scan, hack, D17) belong to Science and feed the knowledge system.

| Id | System | Holds | Written by | Read by |
|---|---|---|---|---|
| PWR | Power bus | reactor output, pips per subsystem, heat, capacitors, overcharge | E | H, W, S (as envelopes) |
| COND | Ship condition | subsystem health, faults, crews, parts, ammo, propellant, probe stock, mount arcs | damage, E, W, R | all |
| KNOW | Contact knowledge (per faction) | detection, scan level, class, intent/IFF, weak points, resistances, hack access, track quality | S, R (probes), C (intent) | all |
| MARK | Marks and pings | 8 NATO marks, routes, hazard zones, scan positions, approach lanes, pings | any station, R curates | all |
| STORY | Story state | NPC conversations, contracts, missions, opportunities, clearances, reputation per faction | C, director | C full, others summaries |
| CUE | Requests and cues | request chips (typed, player-initiated), acknowledgements, audio cues, debrief log | any station | target station, debrief (D35) |

Rules that keep cooperation honest:

- **Asymmetry is data access, not hidden UI.** Each station gets the full record of its own system and a summary of the others. On Hard the summaries are banded or absent; on Easy they're exact (D14, D33).
- **Requests are chips, not prompts.** A player sends a request (one key or tap); it shows as a small chip on the target station with a soft tone. The game never generates "talk to X" prompts. Unanswered chips expire silently and appear in the debrief.
- **Every pair has a no-partner path.** Because D19 guarantees every station is covered, "alone" means the partner is busy or ignores you, not absent. The fallback is always slower, costlier or less precise, never blocked.

## 1. The 15 pairs

Order: Helm pairs, then Weapons, Engineering, Science, Relay. Each entry: mechanic; what each station does alone; asymmetric information; cooperative advantage; feedback; cost of not cooperating; shared system; automated test. Tests run on the headless authoritative server with scripted station inputs and seeded RNG; "co-op vs solo" means the same scenario run with and without the partner's action, asserting the metric moves the right way and the solo run still completes.

### P1. Engineering + Helm: thrust envelope and shields (first-playable loop)

- **Mechanic:** Helm's maximum linear thrust and turn rate are a function of Engineering's pips on Engines and Thrusters, their health and heat. Helm sends a `Boost` request chip; Engineering overcharges for a short window that builds heat. Shields split the same way (D16): Engineering sets shield power and focus tightness, Helm sets the focus direction.
- **Alone:** Helm flies, faces and aims shields on nominal power. Engineering sets pips, focus and repairs without any Helm input.
- **Info:** Helm sees the thrust envelope gauge and the shield ring, not the reactor. Engineering sees reactor load, heat and per-face shield strength, not where threats are.
- **Advantage:** sharper evasive turns and faster intercepts; a tight shield focus pointed at the attacker absorbs much more.
- **Feedback:** Helm's thrust gauge glows and the engine note rises during overcharge; Engineering's heat bar climbs with a ticking sound; the shield ring shows width (E) and direction (H) in one widget.
- **Failure:** without boost Helm keeps nominal thrust; ignoring heat damages thrusters (a fault for Engineering to repair). A tight focus pointed the wrong way leaves the struck face thin.
- **System:** PWR (+ COND for heat damage, CUE for the chip).
- **Test:** scripted 90° turn plus 2 km sprint: with boost the time is shorter than nominal; heat past threshold creates a thruster fault; with zero Engineering input the manoeuvre still completes at nominal time. Shield test: the same volley against tight-focus-correct, tight-focus-wrong and spread; hull damage ordered correct < spread < wrong.

### P2. Helm + Weapons: arcs and firing solution

- **Mechanic:** mounts have limited traverse (COND mount arcs), so Helm must bring the right side to bear. Projectile lead depends on relative velocity: Helm matching velocity ("stabilise") tightens the lead reticle, and evasion widens it while also lowering incoming accuracy. Weapons sends `Bring mount N to bear` chips.
- **Alone:** Weapons aims and fires from any claimed mount that has the target in arc. Helm flies, and fixed nose guns (if fitted) fire via the Flight combo or Weapons.
- **Info:** Weapons sees which mounts reach the target and the solution quality; Helm sees arc overlays only for the selected target, and the threat picture.
- **Advantage:** more mounts on target and a stable solution give a large hit-rate gain; good Helm turns put the strongest broadside on the enemy.
- **Feedback:** mount arcs light green on Helm's HUD when the target enters them; the Weapons reticle shrinks with a rising tone as the solution stabilises.
- **Failure:** fewer mounts in arc and a wider spread mean lower damage per second, not zero.
- **System:** COND (mount arcs) + physics + CUE.
- **Test:** scripted target pass with Helm holding stable vs flying random evasion: hit rate (stable) > hit rate (random) and both > 0; with the target outside all arcs, a `bring to bear` turn raises the in-arc mount count from 0 to at least 1.

### P3. Helm + Science: scan geometry

- **Mechanic:** scan and hack noise depend on range, aspect and occlusion. Science places a `Scan position` mark (a point and facing that minimises noise); Helm flies there. The silhouette scan minigame (station-ui.md §4.1) gets a denser point cloud there.
- **Alone:** Science scans from wherever the ship is, with more noise and a longer minigame. Helm flies without scan data.
- **Info:** Science sees the noise field around a contact (best aspect, occluders); Helm sees only the mark and its facing arrow.
- **Advantage:** faster, higher-confidence scans; aspect-dependent data (drive section reveals engine weak points) only from the right side.
- **Feedback:** the scan position mark glows as Helm closes; Science's noise meter drops in steps with a clicking tone.
- **Failure:** longer minigame, lower confidence band, some aspect-only data missing; never blocks a scan.
- **System:** KNOW + MARK.
- **Test:** scripted scan at 8 km off-aspect vs at the scan-position mark: point-cloud density and final confidence higher at the mark; the off-aspect scan still completes within the time cap.

### P4. Helm + Relay: routes and intercepts

- **Mechanic:** Relay draws 3D routes on the world map around hazards it knows (probe coverage) and plots intercept points for moving contacts from long-range tracks. Helm sees the route as a ribbon in the cockpit and can follow it by hand or with an autopilot at lower efficiency.
- **Alone:** Helm navigates by compass and marks, seeing only near hazards. Relay maps, launches probes and marks without Helm moving.
- **Info:** Relay sees hazards, far contacts and tracks in the world frame; Helm sees the near field in the ship frame.
- **Advantage:** shorter safe paths, less propellant (D34), intercepts instead of tail chases.
- **Feedback:** ribbon and waypoint gates on Helm's HUD; a chime on each gate; Relay's map shows the ship's actual track against the plan.
- **Failure:** Helm flies into a hazard it couldn't see (hull or system damage) or chases a target's tail, burning propellant.
- **System:** MARK (+ KNOW for tracks).
- **Test:** scripted transit through a mine/radiation field: route-following run takes less hull damage and propellant than a straight-line run; the straight-line run still arrives.

### P5. Helm + Comms: clearance and approach lanes

- **Mechanic:** Comms negotiates docking clearance, safe passage and rendezvous with NPCs; an accepted clearance writes an approach lane (corridor plus time window) to MARK. Helm flies the lane inside the window.
- **Alone:** Helm can approach any station; Comms can talk, haggle and accept without Helm doing anything.
- **Info:** Comms knows the terms (window, lane, what counts as hostile approach); Helm sees the lane and a countdown, not the terms.
- **Advantage:** docking for repair and resupply, safe passage through defended zones, timed rendezvous rewards.
- **Feedback:** the lane turns from amber to green when cleared; a soft countdown tick in the last 10 s; the NPC's tone (TTS on Comms, D39) changes if the ship strays.
- **Failure:** docking refused or delayed, reputation loss (D34 distributions) for entering without clearance, a missed window costs the bonus, not the mission.
- **System:** STORY + MARK.
- **Test:** scripted approach with and without clearance: cleared run docks and keeps reputation; uncleared run is refused or loses reputation within the data-defined range; both runs remain alive and can retry.

### P6. Weapons + Engineering: firepower on the power bus

- **Mechanic:** beams draw power and add heat per mount; tube reload scales with pips; guns and shields share the reactor. Weapons sends `Power to weapons` chips; Engineering shifts pips or charges a capacitor for a heavy shot.
- **Alone:** Weapons fires at nominal cycle time and manages its own mount heat by pacing. Engineering balances power without requests.
- **Info:** Weapons sees per-mount heat and ammo; Engineering sees reactor budget, total heat and shield drain.
- **Advantage:** faster cycles and heavy shots at the decisive moment; Engineering avoids starving shields when Weapons doesn't need power.
- **Feedback:** mount icons pulse when power-boosted; an overheated mount hisses and greys; a capacitor-charged chime on both stations.
- **Failure:** slower fire, an overheated mount locks for a cooldown, or shields thin while guns are overpowered.
- **System:** PWR (+ COND for ammo and heat damage).
- **Test:** scripted 30 s engagement: damage output with weapon pips at 3 > at 1; overheating a mount locks it for the specified cooldown; zero Engineering input still yields non-zero damage.

### P7. Weapons + Science: weak points and resistances

- **Mechanic:** Science's scan reveals weak points on the target's model and its damage-type resistances (D26, D28); once shared, weak points appear as hit zones in Weapons' gunnery view and the ammo selector shows effectiveness. A successful hack (Hack minigame) can open a short shield-down window on the chosen subsystem.
- **Alone:** Weapons hits whatever it aims at (nearest-subsystem hit location) with any ammo. Science scans and hacks without Weapons firing.
- **Info:** Science sees the internal layout and resistances with a confidence band; Weapons sees only zones and ratings Science has shared.
- **Advantage:** subsystem kills (disable engines or weapons) and better damage per shot; hack windows multiply that.
- **Feedback:** weak-point brackets on the target in the gunnery view; a distinct "crit" sound when hit; a hack-window timer bar on both stations.
- **Failure:** random subsystem hits and ammo mismatch: longer fights, more incoming damage, not impossible ones.
- **System:** KNOW.
- **Test:** scripted target with a known weak point: shots on the shared zone damage the named subsystem; time-to-disable with sharing < without; correct ammo type yields higher damage per hit than the resisted type.

### P8. Weapons + Relay: over-the-horizon targeting and firing lanes

- **Mechanic:** Relay's probes keep tracks on contacts beyond the ship's own sensors; Relay attaches a mark to a tracked contact and Weapons can fire guided ordnance at it (missiles, torpedoes) with the track quality as accuracy. Relay also flags firing lanes that cross friendly ships (co-op multi-ship, D37) and neutrals.
- **Alone:** Weapons engages anything inside own-sensor range. Relay builds the picture without anyone firing.
- **Info:** Relay sees the full tactical picture, including friendlies behind the target; Weapons sees a narrow, ship-centred view.
- **Advantage:** first strike at range, focused fire across ships, fewer friendly-fire incidents.
- **Feedback:** a track-quality bar on the attached mark; a red lane overlay with a warning tone when a shot would cross a friendly.
- **Failure:** shorter engagement range, more friendly-fire risk (D37 is on, with warnings), wasted ordnance on stale tracks.
- **System:** KNOW (tracks) + MARK.
- **Test:** scripted target at 1.5× own sensor range: a guided shot is possible only with a Relay-attached track and hits with probability rising with track quality; a scripted shot through a friendly triggers the lane warning before firing.

### P9. Weapons + Comms: intent, surrender and contract targets

- **Mechanic:** Comms learns and sets intent through conversation: hails, demands surrender, bluffs. Intent is written to KNOW as an IFF tag (hostile, neutral, surrendering, bluffing). Contracts flag targets as "disable, do not destroy" or "protect". Weapons sees tags and contract flags on its reticle.
- **Alone:** Weapons can fire on anything; Comms can talk to anything.
- **Info:** Comms knows who is surrendering, which target a contract needs intact, and what the NPC promised; Weapons sees the tag only.
- **Advantage:** surrenders end fights early (fewer risks, D31), capture rewards, reputation gains; pressure from Weapons (a warning shot, a disabled engine) improves Comms' surrender odds.
- **Feedback:** the reticle chip turns white for "surrendering" or shows a padlock for "do not destroy"; a short Comms-side NPC line plays (TTS only on Comms, D39) when a surrender is accepted.
- **Failure:** firing on a surrendered or protected target costs reputation and contract rewards; a fight that could have ended continues.
- **System:** STORY + KNOW.
- **Test:** scripted encounter where the NPC accepts surrender after its engines are disabled: surrender probability with prior engine damage > without; destroying a surrendered contact reduces reputation within the data range and logs a debrief line.

### P10. Engineering + Science: fault diagnosis and sensor power

- **Mechanic:** some damage arrives as unknown faults ("power fluctuation, deck 3"). Science runs an internal scan (same scan minigame, own ship as target) to name the cause (coolant leak, hacked controller, radiation); the right repair is then fast. Engineering's sensor pips set scan noise and range.
- **Alone:** Engineering can brute-force repair an unknown fault slowly; Science scans at whatever sensor power it has.
- **Info:** Engineering sees symptoms (where power drops); Science sees causes after an internal scan; Science sees noise, Engineering sees the pip budget.
- **Advantage:** fast, correct repairs; cleaner scans when Engineering gives sensors power.
- **Feedback:** the fault icon on the cutaway changes from "?" to a named cause; the scan noise bar drops when sensor pips rise.
- **Failure:** slow repairs and wasted parts on wrong fixes; noisy scans.
- **System:** COND + PWR.
- **Test:** scripted unknown fault: time to repair with diagnosis < brute force; scan noise at sensor pips 3 < at 1; brute force still repairs.

### P11. Engineering + Relay: hazards and probe logistics

- **Mechanic:** Relay's probes measure hazard fronts (ion storm, radiation, nebula drain) and forecast arrival; Engineering pre-hardens (power to shields in hazard mode, shuts down vulnerable systems). Probes come from a finite stock in COND; Engineering can fabricate a probe from spare parts on request.
- **Alone:** Engineering reacts to hazards when they hit. Relay works with the probes in stock.
- **Info:** Relay sees where and when the hazard arrives; Engineering sees what it will break and what parts remain.
- **Advantage:** hazards pass with little damage; probe stock lasts the run.
- **Feedback:** a hazard countdown chip on Engineering; hardened systems show a blue rim; a fabrication progress bar on both stations.
- **Failure:** hazard damage and faults; Relay runs out of probes (smaller map, which also hurts P8 and P13).
- **System:** MARK (hazard zones) + PWR + COND.
- **Test:** scripted ion storm: subsystem damage with hardening started on the forecast < without; probe fabrication consumes the specified parts and adds one probe.

### P12. Engineering + Comms: quotes and contract feasibility

- **Mechanic:** Comms receives repair, resupply and contract offers; their cards show requirements (hull, tractor power, cargo space, ammo). Engineering publishes a `Status report` (a one-key snapshot of COND) that turns Comms' banded estimates into exact fit checks and itemises repair quotes. Comms decides alone (D57).
- **Alone:** Comms can accept any offer using banded condition; Engineering repairs in the field.
- **Info:** Engineering knows exact condition and repair times; Comms knows prices, deadlines and NPC terms.
- **Advantage:** no overspending on repairs Engineering could do cheaply, no contracts the ship can't fulfil.
- **Feedback:** contract cards show a tick or cross per requirement once a fresh report exists; the report ages (fades) as condition changes.
- **Failure:** credits wasted, failed contracts with reputation loss; never a hard block.
- **System:** COND + STORY.
- **Test:** scripted offer requiring tractor power 2 while tractor is damaged: with a fresh report the card shows a cross; accepting anyway and failing reduces reputation within range; without a report the card shows a band and acceptance is still allowed.

### P13. Science + Relay: probe-assisted scanning and hacking

- **Mechanic (D56):** Relay places probes; Science can scan and hack contacts inside a probe's sensor bubble as if in own range, with noise from probe distance. Nebulae and planets block the ship but not a probe inside them.
- **Alone:** Science scans and hacks within own sensor range; Relay maps with probes.
- **Info:** Relay sees probe coverage volumes; Science sees per-contact signal quality.
- **Advantage:** scans and hacks at range, inside nebulae and behind planets, before the enemy closes.
- **Feedback:** coverage volumes on both maps; a contact gains a "probe link" icon on Science's list with a link tone.
- **Failure:** Science must wait for range or ask Helm to close (P3), which is slower and riskier.
- **System:** KNOW + MARK.
- **Test:** scripted contact outside own range inside a nebula: scan impossible without a probe, possible with one; hack trace speed lower with probe coverage than at the edge of own range.

### P14. Science + Comms: data that changes conversations

- **Mechanic:** Science's analysis reveals facts (transponder code, cargo manifest, hidden weapons, damaged reactor) that unlock dialogue options for Comms (bluff a code, call a smuggler's cargo, offer help). Comms' conversations create scan objectives (an NPC claims to carry medicine: verify it).
- **Alone:** Comms has base dialogue options; Science scans without context.
- **Info:** Science knows the physical truth; Comms knows what NPCs claim and want.
- **Advantage:** better deals, exposed lies, branches that avoid fights.
- **Feedback:** new dialogue options appear with a Science icon; a "verify" objective chip appears on Science's contact card.
- **Failure:** base options only; lies go undetected (bad deals, ambushes), no hard block.
- **System:** KNOW + STORY.
- **Test:** scripted freighter with false manifest: the "call the bluff" option is present only after a cargo scan; choosing it yields the scripted reputation/credit outcome distribution.

### P15. Relay + Comms: locating the story

- **Mechanic:** missions and opportunities arrive as text with vague places ("past the ice belt", "distress, sector north"); Relay resolves them to marks and routes from the map. Relay's probe discoveries (derelicts, beacons, unknown ships) open Comms opportunities (hail, salvage rights, distress response).
- **Alone:** Comms reads and accepts missions; Relay maps and marks.
- **Info:** Comms knows what and why; Relay knows where and what's in the way.
- **Advantage:** objectives found fast, opportunities that only exist once discovered.
- **Feedback:** mission entries gain a mark icon when located; a discovery adds a "new contact to hail" chip on Comms with a soft chime.
- **Failure:** time lost searching (timed missions may lapse), missed side opportunities.
- **System:** STORY + MARK.
- **Test:** scripted mission with a vague location: time to reach it with a Relay mark < searching; a probe discovery creates a Comms opportunity entry.

### Pair summary

| Pair | Mechanic | Systems |
|---|---|---|
| E+H | thrust envelope, boost, shield power/facing | PWR |
| H+W | arcs and firing solution | COND, CUE |
| H+S | scan position geometry | KNOW, MARK |
| H+R | routes and intercepts | MARK |
| H+C | clearance and approach lanes | STORY, MARK |
| W+E | firepower on the power bus | PWR |
| W+S | weak points, resistances, hack windows | KNOW |
| W+R | over-the-horizon targeting, firing lanes | KNOW, MARK |
| W+C | intent, surrender, contract targets | STORY, KNOW |
| E+S | fault diagnosis, sensor power | COND, PWR |
| E+R | hazard forecast, probe logistics | MARK, PWR, COND |
| E+C | status report, quotes, feasibility | COND, STORY |
| S+R | probe-assisted scan and hack | KNOW, MARK |
| S+C | scan facts unlock dialogue | KNOW, STORY |
| R+C | locating missions, discoveries | STORY, MARK |

Each station sits in five pairs, and each system carries at least two. Build order follows the systems: PWR + COND (P1, then P6, P10), KNOW (P7, P3, P13), MARK (P4, P8, P11), STORY (P5, P9, P12, P14, P15).

## 2. Curated combos (D19, D20)

Rules: all six functional stations must be covered before launch; the Captain is never required. A combo keeps every control of each station it merges (D20): it's a layout, not automation. Merged screens keep one shared radar and one top bar; extra stations become docked panels switched by keys (F1–F4) or a controller bumper; hotkeys don't collide (Helm keeps sticks, Weapons the mouse buttons, the rest Ctrl/Alt chords and panels).

Sharing (D10, D18): any number of players can share one station or combo seat. Sub-controls are claimable and locked to the claimer: weapon mounts, repair crews, scan/hack queue slots, probes, and NPC conversations (only the claimer hears that NPC's TTS, D39). So a crew of 8 can run six seats with two players on Weapons and two on Comms.

Proposed set (the lobby offers only sets that cover all six; a crew can also mix: any partition below is valid for its size):

| Crew | Recommended | Alternatives |
|---|---|---|
| 6 | H · W · E · S · R · C | (+ optional Captain) |
| 5 | H · W · E · S · **Ops** (R+C) | H · W · E · **Sensors** (S+R) · C |
| 4 | **Tactical** (H+W) · E · S · **Ops** (R+C) | H · W · **Systems** (E+S) · **Ops** (R+C) |
| 3 | **Tactical** (H+W) · **Systems** (E+S) · **Ops** (R+C) | **Ship** (H+W+E) · S · **Ops** (R+C) |
| 2 | **Ship** (H+W+E) · **Intel** (S+R+C) | **Flight** (H+W) · **Bridge** (E+S+R+C) |
| 1 | **Solo Commander** (all six) | |

Why these merges: Relay and Comms share the world map (missions resolve to marks, P15), so **Ops** is one map with a story panel. Helm and Weapons share the cockpit and aiming (P2), as in EE's Tactical. Engineering and Science both read the ship and contacts as cards (P10). At 2 players the split is action (move, shoot, power) vs knowledge (scan, map, story), which balances combat load: Engineering's pips and crew orders fit a side panel, while the Intel seat carries both minigames and the conversations.

**Ship (H+W+E), 2-player seat 1.**

```
+-[SHIP = HELM+WEAPONS+ENG]------------------+
| <H1    +lead  H2 4hi 2.3k  | PWR  E W S T  |
|       ( reticle )          |      # # # #  |
| compass(o)      shld(ring) | heat [###-]   |
| MNT 1RDY 2HOT 3 2/6 [CAM]  | crews A> B>   |
| THR[###] ASSIST  [F] [G]   | faults 2  !   |
| .-12-. req: Intel weak pt  | parts 6       |
| 9 * * 3                    | [cutaway]     |
+--------------------------------------------+
```

**Intel (S+R+C), 2-player seat 2.**

```
+-[INTEL = SCI+RELAY+COMMS]------------------+
| frame[SHIP|WORLD]        | [CARD|COMMS]    |
| .------ 12 ------.  <>A  | U3 ?? 40%       |
|9  U3?  (^)   H2*  3      | [SCAN] [HACK]   |
| '------ 6 -------' prb2  | weak: vent      |
| [LAUNCH PROBE] [ROUTE]   | K: "Who goes?"  |
| marks A B C  hazards 2   | 1 bluff 2 pay   |
| log: H2 changed course   | contracts 3     |
+--------------------------------------------+
```

**Flight (H+W) and Bridge (E+S+R+C), 2-player alternative.**

```
+-[FLIGHT = HELM+WEAPONS]--------------------+
| <H1    +lead  H2 4hi 2.3k     shld(ring)   |
|       ( reticle )                          |
| MNT 1RDY 2HOT 3 2/6  view[COCKPIT|GUNNERY] |
| THR[###] ASSIST [F][G]   .-12-. 9 * * 3    |
+--------------------------------------------+
+-[BRIDGE = ENG+SCI+RELAY+COMMS]-------------+
|[E|S|R|C] | .---- 12 ----.  | U3 [SCAN]     |
| E W S T  |9 U3? (^) H2* 3  | K: hail       |
| # # # #  | '---- 6 -----'  | crews A B     |
+--------------------------------------------+
```

**Solo Commander (all six).** Cockpit with one swappable right panel (E, S, R, C on F1–F4). Toasts are actionable: clicking "SNS 40%" opens the Engineering panel at that item. Scans and hacks keep their minigames (D17) with a "hold to continue" so the player can look up; conversations wait (NPCs repeat the last line) instead of timing out in combat.

```
+-[SOLO]------------------------[E|S|R|C]----+
| <H1    +lead  H2 4hi 2.3k  | ENG           |
|       ( reticle )          | E W S T       |
| compass(o)      shld(ring) | # # # #       |
| MNT 1RDY 2HOT 3 2/6        | crews A B     |
| THR[###] ASSIST [F][G]     |-------------- |
| .-12-. toast: SNS 40%  >   | hail K    >   |
| 9 * * 3 toast: scan done > | F1-F4 panel   |
+--------------------------------------------+
```

## Questions

### Q1. Which pair merges for crews of 5 and 4?

- **A (Recommended): Ops = Relay + Comms.** 5: H·W·E·S·Ops; 4: Tactical·E·S·Ops. One map with the story beside it; Science stays a dedicated seat for the minigames. Trade-off: Ops is quiet in heavy combat.
- **B: Sensors = Science + Relay.** 5: H·W·E·Sensors·C; 4: Tactical·E·Sensors·C. Probe coverage and scans in one seat (P13 becomes internal). Trade-off: both minigames plus the map on one player; Comms alone has little to do in combat.
- **C: Systems = Engineering + Science.** 5: H·W·Systems·R·C; 4: Tactical·Systems·R·C. Fault diagnosis becomes internal. Trade-off: the busiest combat seat (repairs plus scans).

```
A [H][W][E][S][R+C]   B [H][W][E][S+R][C]
  map+story together    scans+probes together
```

### Q2. Two-player split

- **A (Recommended): Ship (H+W+E) · Intel (S+R+C).** Action vs knowledge; balanced load; cooperation between seats runs through weak points, routes and clearances. Trade-off: P1 (the first-playable pair) happens inside one seat.
- **B: Flight (H+W) · Bridge (E+S+R+C).** Closest to EE's Tactical/Ops split; the pilot only flies and shoots. Trade-off: Bridge holds four stations including repair crews and both minigames.
- **C: Pilot (H+E) · Gunner-intel (W+S+R+C).** The gunner owns all knowledge, so weak points (P7) stay in one seat. Trade-off: turret camera, map and both minigames compete for one screen.

```
A [H W E] [S R C]   B [H W] [E S R C]
  act       know        fly   run the ship
```

### Q3. Solo form

- **A (Recommended): Cockpit + one swappable side panel** (wireframe above). Flying stays primary; toasts jump to the right panel. Trade-off: only one non-flight station visible at a time.
- **B: Map-first commander.** Relay world map in the centre, cockpit as an inset, panels around. Trade-off: good for planning, poor for manual aim (D25).
- **C: Full-screen tabs.** Each station's own screen, switched by F-keys; nothing shrinks. Trade-off: no overview while on a station; most context switching.

```
B +----------------------------+
  | [ENG]  world map   [COMMS] |
  | [SCI]   <>A  H2*  [cockpit]|
  |         (^)       [ inset ]|
  +----------------------------+
```

### Q4. Engineering + Comms under D57 (Comms decides alone)

- **A (Recommended): Status report.** Engineering pushes a one-key COND snapshot; contract and quote cards show exact ticks until the report ages. Trade-off: a small extra action for Engineering; Comms can still ignore it.
- **B: Shared repair quote.** Engineering ticks which repair line items Comms should buy in a station's quote; Comms haggles on that list. Trade-off: richer, but only matters while docked.
- **C: Both A and B.** Trade-off: most cooperation, most UI on two stations.
