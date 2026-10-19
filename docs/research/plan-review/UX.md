# UX review: question 5, "Are interfaces easy to learn, hard to master?"

Scope read: spec 05, 07, 08, 09 (plus 01, 03, 04, 06, 11, 14 for checks), research/station-ui.md, research/pairs-and-combos.md §2, research/emptyepsilon.md (checks), decisions D14–D94, issues #4, #7–#10, #12, #13.

Headline: the stations themselves are well designed for mastery (manual aim, 6DOF, power juggling, two server-scaled minigames), but the plan has no onboarding at all, the M1 joint views put first-time players on the hardest seats with key bindings that collide, and no playtest measures whether a new crew can learn the game.

### UX-1: The plan has no onboarding: no tutorial, practice mode, control reference or first-run hints
- Severity: major
- Evidence: a grep of docs/spec, docs/decisions.md, docs/plan/task-breakdown.md and issues #1–#13 for tutorial/training/practice/onboard/hint/tooltip finds nothing. EE ships tutorials (`scripts/tutorial/`, research/emptyepsilon.md §Scenarios), and FT drops them without a decision. FT-MIS-001 and §8.1 set a 20–40 min run, FT-MIS-009/D31 set a 5–10 % loss risk per encounter, and FT-MIS-011/D79 make a lost crew viewers for the rest of the run. FT-PAIR-012 forbids game-generated "talk to X" prompts, and the research's scan tip ("Helm to <>ScanPos cuts noise", station-ui §4.1) was dropped from FT-SCI's wireframe. The only pause is the coverage pause (FT-NET-034); the crew has no pause of its own.
- Problem: three friends sit down for their first run. Helm has about 18 KB/M bindings (§5.1), and nothing on screen lists them. Science meets the silhouette minigame for the first time under fire. Nobody can pause to explain. Twenty minutes in, the ship dies to an avoidable mistake, and the crew watches a main screen until the run ends. Because FT-PAIR-012 bans cooperative prompts, the pair mechanics (scan position, weak points, boost) can only be learnt by reading the docs.
- Proposal: three cheap aids, smallest first.
  (a) Add FT-STN-009: every station has a controls overlay (hold `?` or the controller View button, touch: an `i` button) generated from the live input map. It shows the bindings as rebound and is translated by the existing i18n gate. Since it is generated, it costs one widget and never drifts. Add it to #7 (T049/T050) so the #8 playtest benefits.
  (b) Add FT-MIS-037: a "Shakedown" training scenario built on the Scenario API (#10). It has no director, no elimination (the hull floors at 1 %, or the ship respawns), a drone target, and staged ship-computer lines with subtitles that teach each station's core actions, then one pair per step (P1 boost, P3 scan position, P7 weak point). FT-PAIR-012 is amended to "outside training scenarios" so the training scenario may prompt cooperation.
  (c) Add FT-MIS-038: in co-op sessions the host may pause the universe from the lobby menu, reusing the coverage-pause path (FT-NET-034). PvP is excluded.
- Options (amends FT-PAIR-012 and adds a scenario type):
  1. (Recommended) (a) in M1 (#7), (b) and (c) in M3 (#10). The controls overlay is nearly free. The training scenario costs one scenario script plus about 30 subtitle/voice lines per language.
  2. Only (a) and (c). This is the cheapest option, but the pair mechanics stay undiscoverable.
  3. Add per-station first-run tooltips on top of option 1. This gives the most guidance, but it adds a hint state machine per station and clutters the HUD.
- Affects: #7, #10, #13

### UX-2: Bindings collide inside all three M1 joint views, and the fix rule makes keys change between views
- Severity: blocker (it must be settled before #7 builds the input map)
- Evidence: §5.1–5.6 bindings. In Tactical, Helm uses `C` for the chase camera and Weapons uses `C` to claim a mount; Helm uses `R` for up and Weapons uses `R` for ammo type; on KB/M both stations use the mouse (pitch/yaw versus aim). In Systems, Engineering's "number keys select subsystem" collide with Science's "1–3 share". In Ops, Relay's `Enter` accepts a received mark and Comms' `Enter` opens a card. §5.9 and pairs-and-combos §2 resolve collisions by moving "the rest" to "Ctrl/Alt chords". FT-JNT-002 and the #7 collision check only require no collision per joint view. D66 makes 3-player crews the minimum, and FT-M1-001 runs M1 only as Tactical, Systems and Ops.
- Problem: a player learns Weapons alone (`C` claims), then joins a 3-player crew on Tactical, where claiming becomes something like `Ctrl+C`. Skills don't transfer between single and joint views, and with 15 joint views (D76) a station's keys can differ in up to 6 layouts. On KB/M the Tactical player also can't steer and aim at once without toggling `view [COCKPIT|TURRET]`.
- Proposal: replace the chord rule with focus routing. In a joint view, a station's keys act on the focused panel (F1–F2 or a bumper switch focus, as §5.9 already does). Only a short always-live set ignores focus: Helm translation, face, all-stop, ping and the alert level. A station's bindings are then identical in every view. Reword FT-JNT-002 to "a station's bindings shall be the same in every view that contains it, and the always-live set shall not collide with any station". The #7 hotkey check then tests one table instead of 15. For Tactical on KB/M, state that in turret view the mouse aims and Helm keeps translation plus hold-F face. This is already possible, but it should be the documented flight model for that seat.
- Options (amends the pairs-and-combos §2 rule behind D20/FT-JNT-002):
  1. (Recommended) Focus routing with a small always-live set. This keeps one binding per action and costs one focus indicator.
  2. A single global collision-free table for all six stations. There is no focus to manage, but it uses about 70 bindings with many chords, and it is hard to learn.
  3. Keep Ctrl/Alt chords per joint view. This is the existing design, with keys that change per view.
- Affects: #7, #9

### UX-3: M1 forces 6DOF flight plus manual turret aim on one novice
- Severity: major
- Evidence: D72/FT-M1-001 and FT-JNT-003 fix M1 to Tactical (H+W), Systems and Ops. D25/FT-SIM-015 give KB/M no aim assist. D66 sets 3 players as the minimum, so every player of a minimum crew holds two stations. #8 asks each player to try one joint view. pairs-and-combos §2 lists other 3-player partitions, but the lobby (D67) offers no guidance on which split suits newcomers.
- Problem: the #8 playtest, and every later 3-player crew, gives one person the two highest-skill stations. A first-timer must fly Newtonian 6DOF and lead targets manually with the mouse while the Ops player has a quiet board between hails. The playtest will report that "combat is hard" when the real issue is seat load, and the H+E boost loop that M1 exists to test (FT-M1-010) loses its partner whenever the Systems player is busy scanning.
- Proposal: keep D72's three joint views, which are already designed. In the lobby catalogue (D67), show a one-word load tag per station and joint view ("light", "busy", "intense"; data in StationDef) and a "suggested for first crews" marker. Add a #8 criterion that one run swaps seats so that the most experienced player takes Tactical. Record in the spec that Comms and Relay are the gentle seats for newcomers. Comms in particular plateaus as an interface, and its depth comes from content (see UX-6).
- Options (only if the owner wants a different M1 split; it amends D72):
  1. (Recommended) Keep Tactical/Systems/Ops, add load tags and the seat-swap criterion. This adds no new layouts.
  2. Build Flight (H+E), Fire (W+S) and Ops (R+C) for M1 instead. Combat load balances better, but it moves the P1 pair into one head, so the M1 pair test can't be playtested across two people.
- Affects: #7, #8

### UX-4: Mandatory minigames on every scan and hack will become a chore after a few runs
- Severity: major
- Evidence: FT-SCI-004 and FT-SCI-006 require the minigame on every scan and hack (D17). FT-SCI-009 makes own-ship fault diagnosis a scan too. FT-SCI-012 sets 5–20 s at nominal noise for an average player. FT-SCI-005 scales difficulty only with noise. EE has a server option for scan complexity (None/Simple/Normal/Advanced, research/emptyepsilon.md §Scanning and §Server options), and FT dropped it with no decision. No requirement links minigame skill to a better result: P3 ties confidence to noise, not to the quality of the match.
- Problem: a 5-encounter run with a few contacts per site, scan levels, hacks and fault diagnoses means dozens of minigames per run. By the tenth run, the same rotate-the-wireframe puzzle on a known frigate class at close range is busywork. A skilled Science player gains only seconds, and the 5–20 s target never grows harder for a skilled player. Novices, meanwhile, have no time target at all.
- Proposal: keep the minigames mandatory (D17), but make them scale and reward skill.
  (a) Add FT-SCI-014: the number of degrees of freedom grows with noise (1 axis when the contact is clean and close, 3 axes when noisy), so easy scans take about 3 s.
  (b) Add FT-SCI-015: a class the crew has already fully scanned in this run starts its later scans pre-aligned on two axes ("familiar class").
  (c) Add FT-SCI-016: match quality above the lock threshold raises the confidence of the result, which gives the station a skill ceiling.
  (d) Extend FT-SCI-012 with "and at most 45 s for a first-time player", checked in #13.
  This needs no new UI and stays server-computed (FT-SCI-011).
- Options (adds to D17; it does not amend it):
  1. (Recommended) (a) to (d). Minigames stay mandatory, scale with skill, and repetition shrinks.
  2. An EE-style lobby toggle for minigame complexity, part of the D84 presets. It is familiar, but it adds a toggle and makes balance diverge per preset.
  3. As specified now. This is the simplest option, but it risks a chore.
- Affects: #9, #13

### UX-5: Common gestures aren't consistent across stations, and Helm has no way to select a target on KB/M
- Severity: major
- Evidence: D44 says any station places marks, but only Relay (drag), Captain (Shift+click) and Science (`M`, scan-position marks only) have mark bindings in §5.1–5.7. FT-STN-003 covers only select and ping. "Accept" is `Space` on Engineering, `A` on Comms and `Enter` on Relay. "Cycle target" is `T` on Weapons, the bumpers on Science, and absent on Helm. Helm KB/M uses the mouse for pitch/yaw, so there is no cursor to click a chip, yet F face (FT-HLM-005), G shield track (FT-HLM-010) and the callout table (spec 06: "Select H2, hold F") all depend on a selected target. `S`, `A`, `R` and `H` mean different things on different stations.
- Problem: when the Captain calls "Helm, face H2", the Helm player has no key to select H2 without leaving mouse-look. A player who moves from Comms to Relay presses `A` to accept a mark and nothing happens. Pings can mark a spot from any station, but only some stations can turn that spot into a persistent mark, which contradicts D44.
- Proposal: add a common-actions table to §5.0 as FT-STN-010. It covers select under the cursor (click/tap), cycle target (`T` / a bumper), select the last pinged item (`Y`), ping (middle-click / long-press), place a mark (Shift+middle-click / long-press then drag), accept/decline (`Enter`/`Backspace`, controller X/Y), claim (one key on every station that has claimables) and help (`?`, UX-1). Station-specific bindings then avoid these keys. This also gives Helm `T`/`Y` selection, and it combines well with UX-2's always-live set.
- Affects: #7, #9, #10

### UX-6: Comms and Relay have no stated skill ceiling, and Captain is spectator-only by design
- Severity: minor
- Evidence: the Comms layout is a card board with A/D accept and 1–4 replies (§5.6, D87). Relay depth sits in probes, routes and the mark inbox (§5.5). Captain is "information only" (D54, FT-CPT-003). Mastery for Comms comes from the STORY/reputation systems (FT-MIS-019/020, P5, P9, P14), but no requirement makes the board itself reward skill. In combat, Comms acts only through hails and surrender (P9).
- Problem: after two runs a Comms player has mastered the interface, and during a 3-minute firefight they wait for a hail. This is fine for a newcomer seat (UX-3) and dull for a veteran. Mastery comes from content volume (dialogue JSON in #10), so a thin first content set leaves Comms flat.
- Proposal: no new mechanics. In #10, state that the M3 content for enemy-wave encounters must include at least one combat-time Comms decision per wave (surrender demand, bluff, third-party hail), testable as a scenario-data lint. Label Comms "light" in the UX-3 load tags so that crews pick it knowingly.
- Affects: #10

### UX-7: No playtest measures learnability, and the death-risk target ignores first-time crews
- Severity: major
- Evidence: #8 criteria record only "feedback: flight feel, information split, alert clarity". #13 records feedback (M2) and loss rate and run length (M3) "for an average crew" (FT-MIS-009, D31). Easy only sizes the budget and presets toggles (FT-MIS-028), with no death-risk target of its own. Neither issue requires a first-time player. The #4 Helm criterion (intercept in < 60 s) is the only time-to-competence measure, and the owner, who designed the game, takes it.
- Problem: every playtester will be the owner or friends who were briefed. The game could ship with Easy tuned for experienced crews, and the first public crew would lose their first ship in encounter 2.
- Proposal:
  (a) Add FT-MIS-039: the debrief records, per station, the time from run start to each core action's first use (first hit, first pip change, first scan lock, first mark, first accepted card). This is a few log lines on the existing debrief (FT-MIS-006) and gives free time-to-competence data.
  (b) Add to #8: at least one player has never seen the game; record their per-station first-action times from the debrief.
  (c) Add to #13 M3: at least two runs by a crew of first-timers at Easy. Add a target to FT-MIS-009: on Easy, a first-time crew survives at least 3 of 5 encounters in most runs (proposed, owner-tunable). Add a minigame time for first-timers (UX-4d).
- Options (only if the owner wants a different target; it extends D31):
  1. (Recommended) A separate Easy target for first-time crews as above.
  2. Keep one target for the average crew and accept harsh first runs, relying on the training scenario (UX-1).
- Affects: #8, #10, #13

### UX-8: Accessibility is audited only at M5, and text scale and hold inputs have no requirement
- Severity: minor
- Evidence: FT-STN-005 to FT-STN-007 cover controller and touch, colour-blind safety and rebinding. Text size, contrast and subtitles are audited in #12 (M5), after the L5 baselines of every station and joint view are set in #7 and #9. No FT id covers UI scale, which matters for tablets (D94) and for a main screen read across a room (FT-MSC-004). Hold inputs (hold F face, FT-HLM-005; R3 hold) have no toggle alternative. Allegiance is encoded by letter as well as colour (H/U/F/N, station-ui §1.2), which is good, but FT-STN-006 doesn't require it. D41/FT-AUD-013 force one language per session for UI text as well as voice.
- Problem: in M5 the audit finds that a 10-inch tablet can't read the contact card. Fixing it then rebaselines every L5 screenshot from M1 to M4. A player with limited hand mobility can't hold F through a long turn.
- Proposal: in #7, add FT-STN-011 (a per-client UI scale of 75–150 %, persisted like bindings, with an L5 baseline at 150 % for each station) and FT-STN-012 (every hold input can be switched to a toggle in the bindings). Extend FT-STN-006 with "and allegiance and alert level shall also be encoded by letter or shape, not colour alone". Keep the M5 audit as the final check. Leave per-client UI language out of scope: D41 is reasonable for a same-room game, and callsigns are language-neutral.
- Affects: #7, #9, #12

### UX-9: There is no first-play path into the lobby's difficulty and toggles
- Severity: minor
- Evidence: §7.2 lists 13 toggles, set in the lobby and locked at start (FT-PAIR-017, D81, D84). D92 adds "(custom)" labelling. No requirement says the lobby explains what a toggle does, or which preset suits first-timers. The labels ("Track feeds and quality bar on Weapons", "voice") assume the player knows the pair mechanics.
- Problem: the host of a new group faces 13 toggles named after mechanics nobody in the room has seen yet, and may pick Hard "for the challenge". The crew then has neither shortcuts nor the knowledge to use voice in their place.
- Proposal: default the lobby preset to Easy on first launch (persisted per host). Hide the individual toggles behind "Customise". Give each toggle a one-line description that names both stations ("Science's weak points appear on Weapons' reticle"), using the existing i18n strings. This is a small lobby change in #9 (E05) and needs no new decision.
- Affects: #9

Summary
- The stations have real skill ceilings (6DOF, manual lead, power juggling, server-scaled minigames). Learnability is the gap: the plan has no tutorial, control reference, pause or novice metric (UX-1, UX-7), and the minigames lack skill scaling (UX-4).
- One blocker: per-station bindings collide inside all three M1 joint views, and the chord rule makes keys change between views. Fix it with focus routing and a common-actions table (UX-2, UX-5) before #7.
- The cheapest wins are a controls overlay generated from the input map, a Shakedown training scenario, load tags in the lobby, and debrief time-to-first-action logs. None of them needs a new system.
