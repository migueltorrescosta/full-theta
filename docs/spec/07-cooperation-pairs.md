# 7. Cooperation pairs

Six functional stations make 15 pairs; each has a cooperative mechanic built on shared simulation systems, not private minigames (v0.3 §6, D55). The Captain sits outside the pairs (D23, D55). Every pair has a no-partner path that is slower, costlier or less precise, never blocked (v0.3 §6).

## 7.1 Shared systems

| Id | System | Holds | Written by |
|---|---|---|---|
| PWR | Power bus | reactor output, pips, heat, overcharge | E |
| COND | Ship condition | subsystem health, faults, crews, parts, ammo, propellant, probe stock, mount arcs | damage, E, W, R |
| KNOW | Contact knowledge (per faction) | detection, scan level, class, intent, weak points, resistances, hack access, tracks | S, R (probes), C (intent) |
| MARK | Marks and pings | marks, pings, routes, approach lanes, hazard zones, scan positions | any station; R curates |
| STORY | Story state | conversations, contracts, missions, opportunities, clearances, reputation per faction | C, director |
| CUE | Requests and cues | request chips, acknowledgements, audio cues, debrief log | any station |

## 7.2 Difficulty and data shortcuts (D14, D33, D68, D69, D84)

Each cross-station data shortcut is an individual toggle, set in the lobby before start for the whole session (D81, D84). Easy, Normal and Hard are presets of these toggles; players may change single toggles afterwards. Engineering ↔ Comms is always verbal and has no toggle (D68).

| Toggle | Pairs | Easy | Normal | Hard |
|---|---|---|---|---|
| Summaries of other stations' data | all | exact | banded | absent |
| Request chips (boost, power, bring to bear) | P1, P2, P6 | on | on | off |
| Routes (ribbon on Helm) | P4 | on | on | off |
| Approach lanes and countdowns on Helm | P5 | on | on | off |
| Hazard countdowns on Engineering | P11 | on | on | off |
| Weak points and ammo ratings on Weapons | P7 | on | voice | off |
| Track feeds and quality bar on Weapons | P8 | on | voice | off |
| Diagnosed causes pre-filled on Engineering | P10 | on | voice | off |
| Contract flags on the Weapons reticle | P9 | on | Q14 | off |
| Science icons and verify chip on dialogue options | P14 | on | Q14 | off |
| Mission mark icon | P15 | on | Q14 | off |
| Marks and pings | all | on | on | on |
| Engineering ↔ Comms | P12 | verbal | verbal | verbal |

"voice" means the toggle is off and the data travels by speech. The Normal value of the three Q14 toggles is open (§14).

Game rules (a probe enabling a remote scan, a scan fact unlocking a dialogue option, an intent change renaming a callsign) apply at every difficulty; D69 governs only how data reaches another station's screen.

## 7.3 Pair table

| # | Pair | Mechanic | Systems | Shortcut (toggle on) | Toggle off (verbal) |
|---|---|---|---|---|---|
| P1 | E+H | Thrust envelope, boost, shield power vs direction | PWR | boost chip | "Boost!" called out |
| P2 | H+W | Arcs and firing solution | COND | "bring mount N to bear" chip | called out |
| P3 | H+S | Scan position geometry | KNOW, MARK | scan-position mark (all levels) | mark only |
| P4 | H+R | Routes and intercepts | MARK, KNOW | route ribbon on Helm | marks as waypoints |
| P5 | H+C | Clearance and approach lanes | STORY, MARK | lane and countdown on Helm | Comms calls the lane, marks |
| P6 | W+E | Firepower on the power bus | PWR, COND | power chip | called out |
| P7 | W+S | Weak points, resistances, hack windows | KNOW | brackets and ammo ratings on Weapons | called out |
| P8 | W+R | Over-the-horizon targeting, firing lanes | KNOW, MARK | track feed and quality bar | guided fire at an attached mark |
| P9 | W+C | Intent, surrender, contract targets | STORY, KNOW | contract flags on reticle | called out |
| P10 | E+S | Fault diagnosis, sensor power | COND, PWR | cause pre-filled on repair | Engineering picks the cause |
| P11 | E+R | Hazard forecast, probe logistics | MARK, PWR, COND | hazard countdown on Engineering | called out |
| P12 | E+C | Condition vs offers (verbal only) | COND, STORY | none (D68) | none (D68) |
| P13 | S+R | Probe-assisted scan and hack | KNOW, MARK | coverage on Science disc | coverage shown (game rule) |
| P14 | S+C | Scan facts unlock dialogue | KNOW, STORY | Science icon on options, verify chip | options unlock, no icon |
| P15 | R+C | Locating missions, discoveries | STORY, MARK | mission gains mark icon | Relay places marks |

## 7.4 Pair detail

"(Easy)" below marks a shortcut shown when its toggle is on (§7.2). Each entry: mechanic; alone; info asymmetry; feedback; failure cost; test (headless server, scripted inputs, seeded RNG; "co-op beats solo" plus "solo completes").

**P1 Engineering + Helm (milestone loop).** Helm's maximum thrust and turn rate follow Engineering's pips on engines and thrusters, their health and heat; a boost is a short overcharge that builds heat. Shields: Engineering sets power and focus tightness, Helm sets direction (D16). Alone: nominal envelope; Engineering works without Helm input. Info: Helm sees the envelope and shield ring, not the reactor; Engineering sees reactor, heat and per-face strength, not threats. Feedback: envelope gauge glows, engine note rises; heat bar ticks. Failure: nominal thrust; overheating creates a thruster fault. Test: 90° turn plus 2 km sprint faster with boost; heat past threshold creates a fault; zero Engineering input still completes; hull damage ordered correct-tight < spread < wrong-tight.

**P2 Helm + Weapons.** Mounts have limited arcs; Helm brings the right side to bear; matching velocity tightens lead, evasion widens it. Alone: Weapons fires any claimed mount with the target in arc. Info: Weapons sees which mounts reach; Helm sees arc cones for the selected target. Feedback: arc cones light on Helm's HUD; reticle shrinks with a rising tone. Failure: fewer mounts in arc, lower DPS. Test: hit rate stable > random > 0; a bring-to-bear turn raises in-arc mounts from 0 to ≥ 1.

**P3 Helm + Science.** Scan and hack noise depend on range, aspect and occlusion; Science places a scan-position mark; Helm flies there (D58). Alone: noisier, longer scan. Info: Science sees the noise field; Helm sees the mark and its facing arrow. Feedback: mark glows as Helm closes; noise meter steps down. Failure: lower confidence, some aspect-only data missing. Test: denser cloud and higher confidence at the mark; off-aspect scan completes within the time cap.

**P4 Helm + Relay.** Relay plans 3D routes around known hazards and intercept points from tracks. Alone: Helm navigates by compass, marks and near hazards. Info: Relay sees hazards and far contacts in the world frame; Helm sees the near field. Feedback: ribbon and gate chimes (Easy); Relay sees actual vs planned track. Failure: hazard damage, tail chases, wasted propellant. Test: route run takes less damage and propellant than straight line; straight line still arrives.

**P5 Helm + Comms.** An accepted clearance creates an approach lane with a time window. Alone: Helm may approach anything; Comms negotiates alone. Info: Comms knows terms; Helm sees the lane (Easy) or hears it. Feedback: lane amber to green; countdown ticks; NPC tone changes on Comms if the ship strays. Failure: refused docking, reputation loss, missed bonus. Test: cleared approach docks and keeps reputation; uncleared loses reputation within the data range; both runs survive.

**P6 Weapons + Engineering.** Beams draw power and heat per mount; reload scales with pips; guns and shields share the reactor. Alone: nominal cycle times. Info: Weapons sees mount heat and ammo; Engineering sees budget and shield drain. Feedback: boosted mounts pulse; overheated mounts hiss and grey. Failure: slower fire, locked mounts, thin shields. Test: damage with weapon pips 3 > 1; overheat locks for the specified cooldown; zero Engineering input gives non-zero damage.

**P7 Weapons + Science.** Scans reveal weak points and resistances; a hack opens a window on a subsystem. Alone: nearest-subsystem hits with any ammo. Info: Science sees layout and resistances with confidence; Weapons sees only what is shared (Easy) or told. Feedback: brackets (Easy), crit sound, hack-window timer. Failure: longer fights. Test: shots on the weak point damage the named subsystem; time-to-disable with knowledge < without; correct ammo > resisted ammo.

**P8 Weapons + Relay.** Probes keep tracks beyond own sensors; guided ordnance can fire at a Relay mark attached to a tracked contact; Relay flags lanes crossing friendlies (D37). Alone: engagement within own sensor range. Info: Relay sees the whole picture; Weapons a ship-centred view. Feedback: track-quality bar (Easy); red lane overlay and tone before a friendly-fire shot. Failure: shorter range, friendly fire, wasted ordnance. Test: target at 1.5× own sensor range is engageable only with an attached mark; hit probability rises with track quality; friendly-lane warning fires before the shot.

**P9 Weapons + Comms.** Conversation sets intent (hostile, neutral, surrendering, bluffing) in KNOW; contracts mark targets "disable, do not destroy" or "protect". Alone: Weapons fires at anything; Comms talks to anything. Info: Comms knows terms; Weapons sees the callsign and, on Easy, contract flags. Feedback: reticle chip turns white for surrendering; NPC line on Comms only (D39). Failure: reputation and reward loss; avoidable fights continue. Test: surrender probability with prior engine damage > without; destroying a surrendered contact reduces reputation within range and logs a debrief line.

**P10 Engineering + Science.** Unknown faults need a cause; Science's internal scan names it; the right repair is fast. Engineering's sensor pips set scan noise and range. Alone: slow brute-force repair. Info: Engineering sees symptoms; Science sees causes. Feedback: "?" becomes a named cause (Easy) or Science calls it; noise bar drops with sensor pips. Failure: slow repairs, wasted parts. Test: repair time with correct cause < brute force; noise at pips 3 < pips 1; brute force still repairs.

**P11 Engineering + Relay.** Probes measure hazard fronts and forecast arrival; Engineering pre-hardens; Engineering fabricates probes from spare parts. Alone: react on impact; finite probes. Info: Relay sees where and when; Engineering sees what breaks and parts left. Feedback: countdown chip (Easy); hardened systems rimmed blue; fabrication bar. Failure: hazard damage, probe shortage. Test: damage with hardening on forecast < without; fabrication consumes the specified parts and adds one probe.

**P12 Engineering + Comms (verbal only, D68).** Comms sees what can be bought and sold (repairs, parts, ammo, propellant) and contract requirements; Engineering knows exact condition and describes it by voice; Comms decides alone (D57). No status snapshot or share button at any difficulty. Alone: Comms buys and accepts on its own banded view of condition. Info: Engineering has exact COND; Comms has prices, deadlines and terms. Feedback: none beyond each station's own view. Failure: overspending, infeasible contracts and reputation loss, never a hard block. Test: an offer requiring tractor power 2 while the tractor is damaged can be accepted; failing it reduces reputation within range; no Engineering data field appears in Comms' snapshot beyond its banded summary.

**P13 Science + Relay.** Science scans and hacks contacts inside a probe's bubble as if in own range, with noise from probe distance; nebulae and planets block the ship but not a probe inside them (D56). Alone: own range only. Info: Relay sees coverage volumes; Science sees signal quality. Feedback: coverage volumes; "probe link" icon. Failure: wait for range or ask Helm (P3). Test: contact outside range in a nebula is scannable only with a probe; hack trace is slower with coverage.

**P14 Science + Comms.** Scan facts (transponder, manifest, hidden weapons) unlock dialogue options; conversations create verify objectives. Alone: base options. Info: Science knows physical truth; Comms knows claims. Feedback: Science icon on options and verify chip (Easy). Failure: lies go undetected, bad deals. Test: "call the bluff" exists only after a cargo scan; choosing it yields the scripted outcome distribution.

**P15 Relay + Comms.** Missions arrive with vague places; Relay resolves them to marks and routes; probe discoveries open Comms opportunities. Alone: Comms reads and accepts; Relay maps. Info: Comms knows what and why; Relay knows where. Feedback: mission mark icon (Easy); "new contact to hail" chime on Comms. Failure: lost time, lapsed timed missions, missed opportunities. Test: time to objective with a Relay mark < search; a probe discovery creates a Comms opportunity.

## 7.5 Requirements

- **FT-PAIR-001** Each of the 15 pairs of functional stations shall have the cooperative mechanic in §7.3. (v0.3 §6, D55)
- **FT-PAIR-002** The Captain shall not be part of any required pair mechanic. (D23, D55)
- **FT-PAIR-003** Pair mechanics shall be built on the shared systems PWR, COND, KNOW, MARK, STORY and CUE, not on per-pair minigames. (v0.3 §6)
- **FT-PAIR-004** Each pair shall have a no-partner path that completes, at a cost in time, resources or precision. (v0.3 §6)
- **FT-PAIR-005** Information asymmetry shall be enforced by the server's per-station snapshot filter. (v0.3 §6, D14)
- ~~**FT-PAIR-006**~~ Removed (D84): superseded by FT-PAIR-019.
- **FT-PAIR-007** On Easy, share buttons and data links shall deliver weak points to Weapons, routes to Helm and probe tracks to Weapons. (D69)
- **FT-PAIR-008** On Hard, no cross-station data shall reach another station's screen except marks and pings. (D69)
- **FT-PAIR-009** Request chips shall be disabled on Hard. (D69)
- **FT-PAIR-010** Engineering and Comms shall share no data link, status snapshot or share button at any difficulty. (D68)
- **FT-PAIR-011** Comms shall have the final say on purchases, sales and contracts. (D57, D68)
- **FT-PAIR-012** Request chips shall be player-initiated only; the game shall never generate "talk to X" prompts. (v0.3 §6)
- **FT-PAIR-013** An unanswered request chip shall expire silently and appear in the debrief. (v0.3 §6, D35)
- **FT-PAIR-014** Game rules that depend on another station's work (probe-enabled scans, dialogue unlocks, intent tags) shall apply at every difficulty. (D69)
- **FT-PAIR-015** Each pair shall have an automated test asserting the co-op variant beats the solo variant on its metric and the solo variant completes. (v0.3 §11)
- **FT-PAIR-016** In PvP each ship's pair mechanics shall use only its own faction's knowledge and its own marks. (D21)
- **FT-PAIR-017** Each cross-station data shortcut in §7.2 shall be an individual toggle, set in the lobby before start, applying to every ship of the session and locked once the run starts. (D81, D84)
- **FT-PAIR-018** The Easy, Normal and Hard presets shall set the toggles to the values in §7.2. (D84)
- **FT-PAIR-019** Summaries of other stations' data shall be exact, banded or absent per their toggle: exact on Easy, banded on Normal, absent on Hard. (D14, D84)
- **FT-PAIR-020** Where a requirement grants or withholds a data shortcut by difficulty (for example FT-WPN-007, FT-ENG-006, FT-RLY-005, FT-PAIR-007 to FT-PAIR-009, FT-NET-009), the difficulty names the preset value; at run time the shortcut's toggle decides. (D84)
