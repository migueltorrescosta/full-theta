# NAV review: Is 3D navigation simple? (question 4)

Scope read: spec 04, 06, 05 (§5.0–5.2, 5.5, 5.7–5.9), station-ui §1, §2.1, §2.2, §2.5, §2.7, §5; decisions D24, D25, D29, D42–D49, D52, D60, D61, D77, D80, D84, D94; issues #3, #4, #5, #7; task-breakdown T012, T013, T051.

Verdict: the *naming* layer (callsigns, marks, pings, D44/D45) is strong and frame-proof. The *moving* layer is underspecified: what assist actually holds, how to stop at a place, how to jump, and which frame a height word uses are all left to the implementer, and nothing tests them with novices before #5/#7 harden them.

### NAV-1: Height words have no frame rule; "3 high" means different things on Helm and Relay
- Severity: major
- Evidence: 06 §6.1 layer 2 (clock/height "ship frame, spoken"); FT-SPA-004; FT-SPA-006 ("grid squares and altitude" on world maps); FT-SPA-010 / D42 (Relay and Captain in world frame); 05 §5.5 wireframe `<>Charlie up2`; station-ui §1.2 (`grid D4, up 2`); FT-SPA-003 says every chip shows clock and height.
- Problem: Relay looks at an ecliptic map where H2's stem points up, while H2's chip (ship frame) may read "8 low" because Helm is rolled 90°. Relay says "H2 is high, go above it"; Helm, rolled, climbs along its own "up" and ends up beside H2. The spec never says which frame a spoken height word is in, nor what unit "up 2" is, so the two vocabularies collide exactly in the Relay-to-Helm call that P4 is built on.
- Proposal: add one rule to §6.1 and one requirement: "Clock and the words level/high/low/overhead/under are always ship frame, on every station including Relay and Captain. World height is only ever said as `up N` / `down N` after a grid square, N in grid-layer units shown on the map legend." Relay's chips keep showing the ship-frame clock (already FT-SPA-003), so Relay reads Helm's words straight off the chip. Define the grid square and layer size in FT-SPA-006 (data per scenario). Add the rule to #5 T034 table tests (word set per frame) and #7 chip tests.
- Affects: #5, #7, #9 (Relay)

### NAV-2: Flight assist has no defined behaviour, and there is no "safe path" to stop at a place
- Severity: blocker
- Evidence: 04 §4.1 and FT-SIM-004 (assist "acts only through thruster commands" but holds nothing named); FT-SIM-003; 05 §5.1 controls ("Space all-stop" appears only in the KB/M line, no FT id, no controller/touch binding); 06 §6.1 table "Bring us to Bravo → Select Bravo, face or follow route"; FT-HLM-005 (face only rotates); station-ui Q6 (autopilot C rejected, D47).
- Problem: a new Helm faces Bravo with F, pushes throttle, arrives at 300 m/s and overshoots by kilometres, because nothing says assist kills rotation on stick release, kills lateral drift, or holds a speed setpoint; and "all-stop" is not a requirement, so #5 T028 and #7 T051 can ship without it. Face assist plus Newtonian momentum with no braking aid is the classic way novices get lost. The 6.1 table promises "bring us to Bravo" but no control stops the ship there.
- Proposal: specify assist in FT-SIM-004 as three holds, all through real thrust: (a) zero angular rate when no rotation input; (b) zero lateral and vertical velocity when no strafe input; (c) forward speed tracks the throttle setpoint (throttle = speed, not force). Add FT-HLM-014 "All-stop (Space; controller and touch bindings) brings velocity relative to the map to zero through assist" and FT-HLM-015 "Hold-to-approach (KB/M hold X, a free key; controller and touch bindings added in §5.1): while held, assist faces the selected contact or mark and flies to a stand-off distance (data, default 500 m) and matches its velocity; releasing returns control". This is the D47 pattern (hold, real rates, no cheating) applied to translation, so it does not reopen Q6-C (a passive autopilot); say so in the decision text. Velocity-match targets the selected contact, which also fixes overshoot on moving targets.
- Options (owner decision, extends D47):
  1. Hold-to-approach plus all-stop as above (recommended): one safe path for novices, still hold-to-use, real thrust and propellant.
  2. All-stop only: smallest change; novices still overshoot and must learn retrograde burns.
  3. Toggle autopilot to a mark: easiest; Helm becomes passive (the Q6-C risk).
- Affects: #3 (S5 prototype), #5 (T028), #7 (T051)

### NAV-3: No playtest of 3D navigation by novices or with the callout language before M1 hardens it
- Severity: major
- Evidence: #3 S5 criteria (one ship, one target, assist, decoupled, face, no HUD compass, no disc radar, no chips); task-breakdown T012/T013; #4 Helm criterion ("the owner intercepts the target in < 60 s"); D29 owner note ("3D navigation is essential... communicate 3D angles and coordinates smoothly").
- Problem: the only human check is the owner, who designed the game, intercepting a target. Nobody tests whether a second person can say "H2, 4 high" and have Helm turn the right way, whether a novice can stop at a mark, or whether Level/face behave when rolled. Those choices get baked into T028, T034 and T051 before any feedback, and D29 names exactly this as the essential risk.
- Proposal: extend S5 (T012) with the target compass, a minimal disc radar with stems, chips with clock/height, one free mark and all-stop/approach (NAV-2); extend T013 in #4 with a 10-minute drill for the owner plus one novice: "face H2", "bring us to Bravo and stop within 1 km", "shields 4 high" (called by the other person), "Level", each timed, plus a 30 s roll-then-face recovery. Record times and confusions in #4. Keeps the spike throwaway; widget code can be promoted to T050.
- Affects: #3, #4, #5, #7

### NAV-4: Jump drive and travel between sites have no player flow
- Severity: major
- Evidence: FT-SIM-034 (jump moves within the global map, costs propellant), FT-HLM-013 ("dock and jump controls", nothing more), FT-MIS-026/027 (sites seeded and spawned), D77, D80; 06 has no name type for sites; marks are capped at 8 (FT-SPA-012); Helm has no map (D46), Relay does (D52).
- Problem: on a map with ~5 sites plus spawns, Relay says "jump to the derelict". Helm has no map and no list of sites; sites have no callsign, so Relay must burn one of 8 marks per site; nothing says who picks the jump target, whether Helm must face it, how long it spools, how accurately it lands or what stops a jump into a hazard. #10 will invent all of this late.
- Proposal: give sites shared names in §6 (a fourth callout layer, e.g. scenario names like "Kestrel Yard", not counting toward the 8 marks, selectable like marks under FT-SPA-015). Add FT-HLM-016: "JUMP jumps to the selected site or mark: Helm must face it (F), the drive spools for a data-defined time, and the ship arrives at a data-defined stand-off; Relay's route to a site selects it on Helm (Easy/Normal routes toggle)". Destination choice stays a crew conversation; Relay proposes, Helm executes.
- Affects: #10 (E07), #9 (Relay)

### NAV-5: Controller Helm cannot select a target, Level, decouple or all-stop
- Severity: major
- Evidence: 05 §5.1 controller line (no select/cycle target, no Level, no decoupled toggle, no all-stop, no ping, no dock/jump); FT-STN-005 (every station usable with controller); FT-HLM-005 (face needs a selected target); Weapons has "X cycle target" (§5.2).
- Problem: a controller Helm told "face H2" has no way to select H2, so face assist and shield track are dead on controller; Level and decoupled are unreachable. #7 T051 tests F and L "through intents" and would pass with KB/M bindings only.
- Proposal: add to the §5.1 controller line: X cycle target (Y select pinged, as Weapons), hold LB+RB Level, click L3 decoupled, B all-stop, View-hold radial for dock/jump/ping/chase. Add an #7 criterion: the hotkey-collision check (FT-JNT-002) also asserts every Helm intent has a controller binding.
- Affects: #7

### NAV-6: Turret camera yanks with every Helm turn; no aim stabilisation or comfort option
- Severity: major
- Evidence: D49 / FT-WPN-001 (full-screen camera from a hull mount), FT-SIM-014 (lead indicator), FT-HLM-005 (face assist rotates the ship), D25; station-ui §2.2 W-B ("weakest awareness"); no comfort requirement anywhere (grep for motion/comfort finds none).
- Problem: the gunner's camera is rigidly on the hull, so when Helm rolls 90° or snaps to face, the whole view spins and the crosshair is dragged off the lead mark. That is both a hit-rate killer and a motion-sickness trigger, and the Tactical joint view (Helm+Weapons in one seat) makes it the default solo experience too.
- Proposal: add FT-WPN-008 "The mount holds its aim point fixed in world space while the ship rotates, slewing at the mount's real traverse rate; the camera's roll follows the aim direction's horizon, not the hull" and FT-WPN-009 "Out-of-arc shows the clock/height direction to bring the target into arc" (so Weapons can call "Helm, 4 high" straight from the screen, which W-A did and W-B lost). Add a per-client comfort toggle (horizon-locked roll, reduced FOV) for Helm cockpit, turret and main screen.
- Affects: #5 (T032 aim model), #7 (T052)

### NAV-7: Disc radar breaks down at range, near the poles and with many contacts
- Severity: minor
- Evidence: FT-SPA-007/008/009; station-ui §1.5 (rings 1/3/10 km); 06 §6.1 range bands ("close < 1 km, mid, far": no mid/far boundary); FT-SPA-004 (clock always shown); D77 (one global map, so contacts can be far beyond 10 km).
- Problem: contacts 40 km out pile on the rim; a contact directly overhead has its stem foot on the ship icon and a meaningless, flickering clock ("H2 · 7 overhead" one tick, "1 overhead" the next); ten blips in one sector overlap stems. The mid/far boundary is undefined, so chips and callouts disagree across clients only if implementers pick different numbers.
- Proposal: in §6.2: radar range is zoomable with fixed steps (e.g. 2/10/50 km) and off-scale contacts are clamped to the rim as arrows; set mid/far at 10 km in FT-SPA-003; above ±60° chips drop the clock and say only "overhead"/"under" (clock appears on hover); selected contact's stem is drawn on top. Small table tests in #5 T034.
- Affects: #5, #7

### NAV-8: Level both pitches and rolls, fighting face assist and changing heading
- Severity: minor
- Evidence: FT-HLM-007 ("roll and pitch the ship onto the map's ecliptic"), D42, station-ui §1.5 ("in calm moments both frames coincide").
- Problem: Helm faces H2 at 40° above the ecliptic, presses L, and the nose pitches off the target; pressing F pitches back and the frames diverge again. Players learn to avoid L, and the "frames coincide" promise never holds in combat.
- Proposal: Level = roll only, so the ship's up is as close to ecliptic up as the current heading allows (aircraft wings-level); a second press (or hold) also pitches onto the ecliptic. Change FT-HLM-007 and the #5 T028 criterion.
- Affects: #5, #7

### NAV-9: Forward main screen spins with the ship for viewers
- Severity: minor
- Evidence: D60 / FT-MSC-001 (default forward view), FT-MSC-004 (any number of read-only viewers), D79 (eliminated crews become viewers), station-ui §2.7 M-B.
- Problem: spectators and the room look at a cockpit that rolls and snaps with every face command; they cannot follow what is happening and some will feel sick. Crews in the room use it as the shared reference, so the problem is not cosmetic.
- Proposal: keep D60, but make the main-screen forward camera horizon-stabilised (roll follows Level's ecliptic up, smoothed) and default to chase when the ship is decoupled or rolling faster than a data threshold. One line in FT-MSC-001; reuse the comfort camera of NAV-6.
- Affects: #7

## Minimal callout grammar (proposed §6.1 addition)

```
<who>, <verb> <object> [<qualifier>]
who:     Helm | Weapons | Shields | Science | Relay | Engineering | All
verb:    face | approach | stop | jump to | track | shields to | scan | mark | level
object:  callsign (H2) | mark (Bravo) | site (Kestrel Yard) | clock-height (4 high)
qual.:   range (2 km) | grid (D4 up 2) | "on my ping"
Rules:   clock + level/high/low/overhead/under = ship frame, always (any station)
         up N / down N = world frame, only after a grid square
         prefer names over directions; directions only for unnamed space
```

## Simplest set of navigation aids

Already decided and enough: callsigns, marks, pings, target compass, face assist, disc radar with stems. Add only: assist holds (NAV-2a–c), all-stop, hold-to-approach with velocity match, named sites, horizon-locked comfort camera, roll-only Level. No new station, no autopilot.

## Summary
3D naming (callsigns, marks, pings) is sound, but movement is underspecified: assist behaviour, stopping at a place, jump flow and the frame of height words are undefined (NAV-1, NAV-2 blocker, NAV-4).
Controller Helm can't select targets or Level, and the turret camera spins with Helm turns (NAV-5, NAV-6); radar, Level and main-screen issues are minor.
Smallest fix: one frame rule, three assist holds plus all-stop and hold-to-approach, named sites, and a novice callout drill added to S5/T013 before M1 (NAV-3).
