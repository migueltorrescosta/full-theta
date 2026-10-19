# Full Theta plan review (spec v0.4, issues #1–#13)

2026-10-19. Six reviewers, one per question: clashing requirements (CLASH), station definitions (STN), collaboration (COOP), 3D navigation (NAV), learnability and mastery (UX), technical consistency (TECH). They made 60 findings; merged, these are 14 enhancements. The coordinator checked each blocker against the spec text. The per-reviewer files with full evidence sit next to this file (`CLASH.md`, `STN.md`, `COOP.md`, `NAV.md`, `UX.md`, `TECH.md`).

Overall: the plan is coherent and the counts add up (330 FT ids, 15 pairs, 15 joint views, every 3-player crew can cover 6 stations). The spatial naming layer (callsigns, marks, pings) is strong, and so are the stations' skill ceilings. The gaps are where parts meet: two stations on one screen, two players on one station, a pause across six ships, a novice at the helm, and a laptop serving tablets.

## Answers to the six questions

| Question | Verdict | Main findings |
|---|---|---|
| 1. Clashing requirements | Yes, one blocker and four majors | The D83 pause can freeze a session for good; the 10 s grace clashes with refresh-to-rejoin and with getting claims back; the Easy summaries toggle leaks Engineering data to Comms against D68; a #8 criterion can't be met; D90–D94 aren't in the spec |
| 2. Stations clearly defined | Roles are clean; ownership plumbing isn't | Joint-view controls collide; claims cover only part of each station; nobody owns the jump destination, mark overflow or module fitting; Ops idles in M1 |
| 3. Collaboration explored | Pairs are designed, crews aren't | Joint views silently make 3 of 15 pairs solo; no chains of 3+ stations; on Hard, MARK becomes the only channel and is undefined; request chips go only to Helm and Engineering; tests never check that cooperation happens |
| 4. 3D navigation simple | Naming yes, moving no | Flight assist holds nothing defined; there's no way to stop at a place; the frame of "3 high" is undefined; jumps have no flow; the turret camera spins with the hull; controller Helm can't select a target |
| 5. Easy to learn, hard to master | Hard to master, not easy to learn | No tutorial, controls reference or crew pause; M1 gives one novice 6DOF flight plus manual aim; minigames repeat without scaling; no playtest measures learnability |
| 6. Technical choices consistent | Stack consistent; six risks not spiked | Float32 precision on one global map; WebSocket backpressure; tablets sleeping on http; 64-client Wi-Fi bandwidth; Piper and the web export missing from releases; a host crash ends the run |

## Enhancements, by when they must land

### Tier 1: decide before #2, #3, #5 and #7 start

**E1. Joint views are modal, with one common-actions table** (blocker; STN-1, UX-2, UX-5, NAV-5; amends D20's wording, not its intent)
In Tactical, `C` is both chase camera and mount claim, and on a controller Helm and Weapons both need the right stick. Ops and Systems collide too, and §5.9's "Ctrl/Alt chords" don't exist on a controller. Proposal: a joint view has one focused panel (F1/F2, a bumper, or a tap). Station bindings act on the focused panel only, so a station's keys are the same in every view. A short always-live set works everywhere: alert, ping, panel switch, Helm translation, face and all-stop. Add a common-actions table to §5.0 (select, cycle target `T`, select pinged `Y`, ping, place mark, accept/decline, claim, help `?`). This also gives Helm target selection on KB/M and controller. Reword FT-JNT-002 so the #7 collision check tests one table instead of 15.

**E2. The pause has an exit** (blocker; CLASH-1, CLASH-2, TECH-3, TECH-8; amends D83)
FT-NET-035 resumes only when every ship passes coverage. A 3-player crew that loses a player, or a destroyed ship whose crew became viewers, never passes again, so all six ships freeze. Proposal:
- Coverage applies only to ships still in play.
- During a pause, a ship's remaining players or the host can abandon that ship.
- Mid-run catalogue changes that break coverage are refused outside a pause.
- FT-NET-026 restores pick and claims only if they're still free.
- The grace length comes from browser refresh times measured in S3 and on tablets in #4.
- A tablet idling 10 minutes must not drop, using a keep-awake workaround or a documented auto-lock setting.
- A relaunched host client rejoins its orphaned server instead of killing it.

**E3. Flight assist defined, with a safe novice path** (blocker; NAV-2, NAV-1, NAV-8; extends D47)
FT-SIM-004 says assist acts through thrusters but not what it holds. A novice faces Bravo, pushes throttle and overshoots by kilometres. Proposal:
- Assist holds three things through real thrust: no rotation without input, no drift without strafe input, and forward speed tracking a throttle setpoint.
- Add all-stop (FT-HLM-014, all devices) and hold-to-approach (FT-HLM-015). While held, approach faces the selected item, flies to a stand-off distance and matches its velocity.
- One frame rule: clock and the words high/low/overhead are always ship frame, on every station; "up N/down N" is world frame, said only after a grid square.
- Level rolls only on the first press and pitches onto the ecliptic on a second press.

**E4. Site-local coordinates and named sites** (blocker; TECH-1, NAV-4, STN-4)
Official Godot `Vector3` is float32. At $10^7$ m from the origin it resolves only about 1 m, so on one global map (D77) projectiles tunnel and ships jitter at distant sites. Proposal: store positions as a site id plus a local offset (FT-SIM-035), and make a jump change the site. Sites get shared names as a fourth callout layer, outside the 8-mark cap. JUMP targets the selected site or mark, with data-defined spool time and stand-off (FT-HLM-016). Relay proposes, Helm executes, Comms explains why. One change fixes both precision and the unowned jump destination. An S6 criterion checks that an intercept $10^8$ m out behaves exactly like one at the origin.

**E5. Spikes test what M1 would otherwise harden** (NAV-3, TECH-2, TECH-5, TECH-9, TECH-10)
- **#3 S5 (flight):** add the target compass, the disc radar, chips with clock and height, one mark, all-stop and approach.
- **#4 T013 (navigation drill):** a timed drill for the owner plus one novice: face H2, stop within 1 km of Bravo, "shields 4 high", Level, and a recovery from a roll.
- **#3 S4 (WebSocket):** a stalled-reader client that must recover through a full resync, plus chunking for large messages (FT-NET-037/038).
- **#3 S9 (load):** add a bytes/s budget for 64 connections, and encode one snapshot per distinct view key (FT-NET-040). In #4, measure snapshot age with 4–8 real devices on the owner's Wi-Fi.
- **#3 S7b (Piper):** a persistent Piper process, measured under combined host load.
- **#5 T027 (integrator):** fix the criterion. Semi-implicit Euler can't match the analytic result within $10^{-6}$; its error is $1/n$.

**E6. Module boundaries enforced by structure, not only by lint** (TECH-6, TECH-7)
In Godot, `class_name` is global, so a path lint misses most violations, and the Weapons reticle needs the lead math from `sim/`. Proposal:
- A `shared/` folder of pure helpers (callouts, lead intercept, units).
- The lint resolves `class_name` to its folder.
- One `scenarios/` folder.
- Definitions are read-only at runtime, with no `load()` in `sim/` (FT-ARC-020).
- The Scenario API hands out only ids and value copies.
Lands in #2 and #5.

### Tier 2: decide before #7 and #9 (M1 and M2 scope)

**E7. A real job for every M1 seat** (STN-2, UX-3, CLASH-5)
In M1, Ops is two placeholders, and one novice gets 6DOF flight plus manual aim. Proposal: pull marks, pings and Relay's map read-out into #7, so Ops spots targets in the fight. Show load tags (light, busy, intense) in the lobby. In #8, players rotate through all three seats; the current criterion "each player tries a single station" is impossible with three players. #9 says plainly that Comms stays a placeholder in M2, or adds a stub surrender card.

**E8. Joint views say which pair they make solo** (COOP-1, CLASH-4)
Add FT-JNT-005: a joint view gets the union of its stations' data, and requests between its own stations run as direct actions. The lobby shows a one-line hint ("Systems: Engineering+Science work is yours alone"). Reword the P12 note: D68 binds different players, and Quartermaster sees both by design.

**E9. One ownership rule for shared stations** (STN-3, STN-5, STN-6, STN-9, CLASH-10)
One new FT-NET rule:
- A player alone on a station holds all its claims.
- Unclaimable controls are ship-wide, last writer wins, and show who changed them last.
- Dock, jump, Level and face belong to the Helm flight claim; ammo type belongs to the mount claim.
- "Scan/hack queue slots" becomes "the active scan or hack".

Smaller ownership fixes:
- Placing a ninth mark is refused, except at Relay, which picks one to replace.
- The Captain fills only empty mark slots and never moves a mark.
- Every station gets a mark input and its pairs' request chips (FT-STN-009).
- A bought module is fitted at once; buying for a full slot sells the old module in the same trade.
- One Captain per ship.

**E10. Hard preset keeps the pairs playable** (COOP-6, COOP-7, COOP-8)
- Scan positions and hazard zones sit outside the 8-mark cap and survive Hard.
- Marks can attach to a scanned subsystem, so "engines are the weak point" can be aimed at on Hard.
- Request chips become a short per-station list in data: add sensor power (Science to Engineering), to scan mark (Science to Helm), fabricate probe (Relay to Engineering) and hold fire on a callsign (Comms to Weapons).
- State that "verbal" means same-room speech.
- Add a one-page callout card, from NAV's grammar `<who>, <verb> <object> [<qualifier>]`.
- A ping on an item someone else pinged counts as a silent "copy".

**E11. Onboarding and accessibility** (UX-1, UX-4, UX-8, UX-9; amends FT-PAIR-012 for training only)
- **In #7:** a controls overlay on `?`, generated from the live input map; per-client UI scale (75–150 %); a toggle alternative for every hold input; allegiance shown by letter, not colour alone.
- **In #9:** the lobby defaults to Easy, toggles sit behind "Customise", each with a one-line description; minigames scale their axes with noise; "familiar class" pre-alignment; match quality sets confidence.
- **In #10:** a "Shakedown" training scenario with no director and no elimination, which may prompt cooperation, plus a host pause for co-op.

### Tier 3: before M3 and later, or text fixes

**E12. Verify that cooperation happens, not just that it pays off** (COOP-2–5, CLASH-3, CLASH-9, UX-7)
- Each pair test asserts a data-defined minimum gain (`pair_min_gain`, starting at 25 %), not just "beats solo".
- P12 is exempt from co-op-beats-solo. Instead, test that what Comms buys reaches Engineering, and keep the summaries toggle off Engineering-to-Comms at every difficulty (CLASH-3).
- The debrief counts cooperative events per pair, and logs each station's time to first use of its core actions.
- Name 2–3 chains (Over-horizon strike R→S→W, Hack alpha S→H+E+W, Bluff call C→S→C→W) and test each one end to end. Give the hack window a floor in data, so a spoken relay fits.
- Death risk is tuned by headless bot batches of 200+ encounters; five playtest runs can't tell 5 % from 20 %.
- #8 and #13 include first-time players, with an Easy survival target for first crews.

**E13. Captain, idle seats, multi-ship** (STN-7, STN-8, COOP-9, COOP-10, UX-6, NAV-6, NAV-9, NAV-7)
- **Captain:** a defined status view (hull, shields, objectives, alert), plus read-only views of open chips and mission cards.
- **Idle seats:** a content rule that every hostile encounter has a Comms beat, and that travel legs may carry hazards for point defence.
- **Multi-ship:** contract flags go into faction KNOW, so allied Weapons see them.
- **Cameras:** the turret holds its aim in world space, and the main screen and turret are horizon-stabilised, with a comfort toggle.
- **Radar:** zoom steps, off-scale contacts drawn as arrows on the rim, a near-pole rule, and a mid/far band boundary at 10 km.

**E14. Release, tests and documentation** (TECH-4, TECH-11, CLASH-6, CLASH-7, CLASH-8, COOP-11)
- **Release packages (#12):** the web export of the same commit, Piper with its voices and licence files, and an L6 smoke test; Piper runs on Windows in #2/#3; the source offer names Piper and espeak-ng.
- **Screenshot baselines:** record the Mesa version with the baselines.
- **Spec hygiene:**
  - Fill the D90 cells in §7.2.
  - Add D91 and D92 to their FT ids.
  - Move the browser station tasks to M2 in the task breakdown.
  - Fix CUE in #9 and the six mis-cited FT ids in #6 and #7.
  - Mark `pairs-and-combos.md` as historical.

## Owner decisions (D95–D102)

| # | Question | Answer | Decision |
|---|---|---|---|
| 1 | Joint-view input (E1) | Modal focus with a common-actions table | D95 |
| 2 | Pause exit (E2) | Abandon a ship, exclude ships out of play, and allow cross-ship takeover | D96 |
| 3 | Novice flight (E3) | Assist holds, all-stop and hold-to-approach | D97 |
| 4 | Coordinates (E4) | Site-local frames with named sites | D98 |
| 5 | M1 seats (E7) | Marks, pings and Relay read-out in #7; load tags; seat rotation | D99 |
| 6 | Onboarding (E11) | Overlay in M1; Shakedown and host pause in M3; also per-station first-run tooltips | D100 |
| 7 | Runtime Piper (TECH-5) | Pre-synthesise the closed set at Start | D101 |
| 8 | Landing | Fold into #1 as spec v0.5, all tiers included | D102 |
