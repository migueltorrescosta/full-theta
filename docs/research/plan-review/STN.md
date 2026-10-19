# STN review: are the player stations clearly defined, without conceptual overlaps?

Scope: docs/spec/05-stations.md, README glossary, D46–D61, D86–D89 (plus D15/D16/D18/D20/D44/D68 where cited), docs/research/station-ui.md (skim), issues #7, #9, #10. Cross-checks: 03 §3.4 (claims), 06 §6.3 (marks), 07 §7.3 (pairs), 08 (travel, modules), 11 (M1).

Overall: the six role statements are mostly clean and D16/D56/D57/D68/D88 already settle the obvious overlaps (shield power vs facing, probes vs hacking, Comms vs Engineering on purchases, main-screen control). The real gaps are in input and ownership plumbing: joint views as specified can't keep every control without collisions, claims cover only part of each station, and a few verbs (jump destination, overflowing marks, pair actions) have no owner.

### STN-1: Joint views can't keep every control without collisions; FT-JNT-002 can't be met as written
- Severity: blocker
- Evidence: glossary "Joint view ... keeping every control of each"; D20; FT-JNT-001/002; §5.9 "Helm keeps the sticks, Weapons the mouse buttons"; §5.1 and §5.2 control lists; §5.3–5.6 control lists; #7 criteria "every control of each station reachable" and "Automated hotkey-collision check over all joint views passes"; #9 E04 criterion.
- Problem: the per-station bindings collide in all three M1 joint views. Tactical, KB/M: the mouse does Helm pitch/yaw and also Weapons aim, and C is both chase camera (FT-HLM-002) and claim/release mount. Tactical, controller: Helm uses both sticks, the triggers and the bumpers, and Weapons needs the right stick to aim, the triggers to fire and the bumpers to swap mounts, so if "Helm keeps the sticks" Weapons can't aim at all. Ops: Enter is both "accept oldest mark" (Relay) and "open card" (Comms), and controller X/Y means accept/decline on both. Systems, controller: A, X, the bumpers and the right stick all have different meanings on Engineering and Science. Later pairs collide too: in Helm+Engineering, Space is both all-stop and accept request. The "Ctrl/Alt chords" fallback doesn't exist on a controller. The #7 sub-agent will either fail its own collision check or quietly drop bindings.
- Proposal: define joint views as modal. A joint view has one focused panel, switched with F1/F2 (controller: hold View plus a bumper; touch: tap the panel). Station bindings act on the focused panel only, and a short global list (alert level, ping, panel switch) works everywhere. Reword FT-JNT-002 to "no collision among the focused panel's bindings and the globals", and the glossary to "every control reachable" (which already matches #7's wording). For Tactical, write down what the existing `view [COCKPIT|TURRET]` toggle means: in cockpit mode, Helm flies and the fire buttons fire claimed mounts at the selected target; in turret mode, Weapons aims and flight assist holds attitude. Amends the wording of D20 ("keeps every control" becomes "every control reachable, one panel focused at a time"), not its intent.
- Options:
  - A (recommended): modal focus as above. One rule covers all 15 views, and the collision check becomes testable.
  - B: hand-made chord maps per joint view. This keeps every binding live but needs 15 bespoke maps, and controllers still run out of buttons.
  - C: drop controller support for joint views. This is the cheapest option but contradicts FT-STN-005.
- Affects: #7, #9

### STN-2: In the M1 three-client crew the Ops player has nothing to do, and Comms stays a placeholder through M2
- Severity: major
- Evidence: FT-M1-005, FT-M1-006, 11-milestone-1 item 2 ("Science, Relay and Comms with station definitions and enough UI to be covered in the lobby"); #7 T054 placeholders and the T058 L4 test "Tactical, Systems, Ops"; #9 covers no FT-COM; #10 FT-COM-001–009.
- Problem: M1's crew is Tactical, Systems and Ops, and Relay and Comms are both placeholders, so one player in three sits at two empty panels for the whole first playtest (#8). M2 (#9, "Full crew") still ships Comms as a placeholder, so a six-player M2 crew has a seated Comms player with no gameplay.
- Proposal: the smallest fix is to give M1's Relay placeholder the mark-and-ping subset (FT-RLY-002/003, FT-SPA-012–015 are station-agnostic) so Ops can call targets. Alternatively, pick M1 pairs that give each client one real station.
- Options:
  - A (recommended): keep Tactical, Systems and Ops, but pull marks, pings and the Relay map read-out (FT-RLY-001–003, FT-SPA-006/012–015) from #9 into #7. Ops then becomes the spotter for the one-enemy fight, at a cost of about one more sub-agent area in #7.
  - B: build Helm+Science, Weapons+Relay and Engineering+Comms (P3, P8, P12) for M1 instead, so every client has one real station. Tactical, the EE-classic seat, then isn't playtested until M2.
  - C: accept an idle Ops seat in M1 and say so in #8's playtest brief.
  Also state in #9 that Comms is a placeholder in M2 (or move a stub hail/surrender card, P9, into M2) so the M2 playtest isn't misread.
- Affects: #7, #8, #9

### STN-3: Claims cover only some controls; the rest of every station has no ownership rule
- Severity: major
- Evidence: 03 §3.4 and FT-NET-022/023 (mounts, repair crews, scan/hack queue slots, probes, NPC conversations, Helm flight, Helm shield facing); glossary "Claim"; 03 item 3 ("Several players may pick the same station or joint view"); D18 "by analogy"; §5.3–5.6 control lists.
- Problem: two players can hold Engineering, for example one at Engineering and one at Systems, and nothing says who owns power pips, shield power, focus tightness or request-chip accept. They'll fight over the reactor cap with no lock or attribution. The same gap exists for Science passive/active (a ship-wide sensor mode), Relay routes, the mark inbox and the main-screen view, and Comms' contract Accept on a card whose conversation another player has claimed. It's also undefined whether Helm's dock, jump, Level and face controls fall under "Helm flight", whether ammo type falls under the mount claim, and who holds a claim when a second player joins (if claims start unclaimed, does nobody fly until someone presses claim?). There's also no input anywhere for claiming "scan/hack queue slots": the Science UI has no queue (§5.4).
- Proposal: add one rule to §3.4 (a new FT-NET id), with no new claim types: "A player alone on a station holds all its claims automatically. Controls not on the claimable list are ship-wide, last writer wins, and show who changed them last. Dock, jump, Level and face are part of Helm flight. Ammo type is part of the mount claim. A card's Accept/Decline follows its conversation claim when one exists." Drop "scan/hack queue slots" in favour of "the active scan or hack": one at a time, held by whoever started it.
- Affects: #6, #7, #9, #10

### STN-4: Nobody owns the jump or travel destination between sites
- Severity: major
- Evidence: FT-HLM-013 ("Helm shall offer dock and jump controls"); FT-SIM-034; FT-MIS-026; D77/D80 (sites on one global map); FT-HLM-003 (Helm selects "callsign or mark" only); FT-RLY-001/005 (sites appear only on Relay's map; routes are Easy-only ribbons).
- Problem: moving between about five sites is the spine of every run, but Helm's HUD can select only callsigns and marks, and sites aren't either. On Hard (no route ribbon), a Helm player who presses JUMP has no defined way to choose where. Comms knows the missions ("Rescue N4 at Bravo") and Relay sees the sites, so three stations hold part of the verb and none owns it.
- Proposal: add FT-HLM-014: "Jump targets Helm's selected mark or contact; impulse travel uses the compass." Add FT-RLY-011: "Relay shall place marks on sites; a site named in a mission card shows as a mark-ready location on Relay's map." This keeps Relay as the owner of where things are, Helm as the owner of movement, and Comms as the owner of why. No decision change.
- Affects: #9, #10

### STN-5: The 8-mark cap has no overflow rule for local placement, and Captain marks reach game mechanics
- Severity: major
- Evidence: FT-SPA-012/013, FT-SPA-022 (replacement rule only for received marks); D44; FT-SCI-010 (Science drops a scan-position mark); FT-CPT-002 and §5.7 ("long-press = place mark" on a mirror of the forward view); FT-CPT-003; P8 ("guided ordnance can fire at a Relay mark attached to a tracked contact"); P3.
- Problem: with 8 marks on the map, Science pressing M, or the Captain long-pressing, has undefined behaviour: refuse, evict, or replace which mark? Marks also feed mechanics (P3 scan geometry, P8 guided fire), so a Captain who moves or evicts an attached mark changes what Weapons can hit, which strains "no command that changes ship mechanics". Separately, a long-press on a 2D forward view has no defined depth for a world-anchored point.
- Proposal: extend FT-SPA-022 to every placement: "Placing a ninth mark is refused with a toast, except at Relay, which picks a mark to replace." Restrict FT-CPT-002 to "The Captain shall place free marks into empty slots, or attach a mark to a tapped contact, and shall not move or delete marks." On the forward view a tap must hit a contact; a free mark only in the tactical view. Write the same depth rule for Helm and Weapons (attach to the selected contact) once they get a mark input (see STN-6).
- Affects: #9

### STN-6: Station control lists leave out verbs that the pairs and FT-SPA-013 give them
- Severity: minor
- Evidence: FT-SPA-013 ("Any crew station ... shall place marks"), with no mark input in §5.1–5.3 or §5.6 control lists; request chips (P1, P2, P6), where only Helm has "Shift boost request" and Weapons' "[Weapons: torp power]" chip in §5.3 has no Weapons input; P11 (Engineering pre-hardens and fabricates probes), not in FT-ENG; P8 (guided fire at an attached mark; Relay flags friendly lanes), not in FT-WPN or FT-RLY; task-breakdown E06 lists them only as pair work.
- Problem: the station sub-agents in #7 and #9 build from §5 and its wireframes, so these actions will be missing from the UI or bolted on later, and pair tests will drive server commands that have no on-screen control. Tablet layouts (#9 touch criteria) will miss them too.
- Proposal: add one common line, FT-STN-009: "Every crew station shall place a mark at its selection or cursor and send the request chips its pairs define", with one binding per device. Add FT-ENG-008 (harden subsystem, fabricate probe), FT-WPN-008 (fire guided ordnance at an attached mark) and FT-RLY-012 (flag lanes crossing friendlies). Then show each in the wireframe.
- Affects: #7, #9

### STN-7: The Captain's "information only" seat is thinner than the crew's, and its fallbacks are undefined
- Severity: minor
- Evidence: D15 ("overview + main screen control"), D54 (C-B director), §5.7, FT-MSC-002 ("status" view not defined anywhere in §5.8), FT-MSC-005 ("when one is seated"), 03 §3.5 (Captain drops never pause).
- Problem: with C-B, the Captain sees only what the TV shows, has no mission objectives (those are on Comms' board), and the "status" view has no defined content. So the seat that is supposed to direct the crew knows the least about the mission. It's also unclear whether main-screen control passes to Relay during a Captain's reconnect grace or only after the Captain leaves. Captain doesn't duplicate Relay: its tactical view is a read-only copy of the world map. That separation works and should stay.
- Proposal: define the status view (FT-MSC-006: "hull, shields, subsystem health, active objectives and alert level"), which also gives the Captain the overview D15 promises without new UI. Amend FT-MSC-005 to "seated, including reconnect grace; Relay controls it otherwise".
- Affects: #9

### STN-8: Comms in a pure enemy wave and Weapons on long transits have nothing to do
- Severity: minor
- Evidence: role list in §5 intro; FT-COM-001–009 (all dialogue, trade or docked actions); P9 (the only combat Comms beat, and only if the NPC talks); P5 (docking); FT-MIS-003 (enemy-wave scenario); D77 (impulse and jump travel between sites); no FT-WPN that acts outside combat.
- Problem: in a six-player crew, an enemy-wave encounter with silent enemies leaves Comms with a static board for the whole fight. A long impulse leg leaves Weapons idle. Helm is busy but not overloaded: shield track (FT-HLM-010) and face-to-selected work on the same selection, so one target pick covers both. The overload is a smaller concern than the idle seats.
- Proposal: no new mechanics. Add a content rule to 10/08 (for example FT-MIS-037): "Every hostile encounter definition shall include at least one Comms beat (hail, taunt, surrender offer, distress call), and travel legs may carry debris or hazards that point-defence can engage." The scenario lint already checks metadata (FT-DAT-006–010), so it can enforce this.
- Affects: #10

### STN-9: Who fits a bought slot module, and whether it replaces one, is unowned
- Severity: minor
- Evidence: FT-MIS-035 ("modules fitted to a ship's slots"), FT-MIS-036, FT-COM-009, D86, D68 (Engineering guides by voice; Comms has the final say), Engineering role "systems" (D50).
- Problem: Comms buys "HX-2" while docked, but no station has a fit or replace control, and nothing says what happens when the slot is full. Without a rule, the #10 agent will invent one, either as an Engineering fitting UI (which grows Engineering) or as silent auto-fitting.
- Proposal: add one clause to FT-COM-009: "A bought module is fitted to its slot at once; buying for a full slot sells the old module as part of the same trade, shown on the offer card." Comms keeps the final say (D68), and Engineering stays verbal.
- Affects: #10

## Proposed one-line role definitions (for the §5 intro; no decision change)

| Station | Owns | Never does |
|---|---|---|
| Helm | the ship's motion and shield direction: flight, face, Level, dock, jump to the selected mark or contact | sets power or picks targets for fire |
| Weapons | damage: aiming, firing, ammo and mount claims | moves the ship or reveals contact facts |
| Engineering | the ship's internals: power, heat, shield power and tightness, repairs, hardening, probe fabrication | sees threats beyond the radar or trades |
| Science | what a contact is: scans, hacks, own-ship diagnosis, scan-position mark | launches probes or plans routes |
| Relay | where everything is: world map, marks (curator), probes, routes, mark inbox, main screen without a Captain | shows NPC text or identifies contacts |
| Comms | what is said, agreed, bought and sold: dialogue, contracts, trade, modules, reputation | sees exact ship condition (D68) |
| Captain | what the room looks at: main-screen view, pings, marks into empty slots | issues any command that changes ship mechanics |

Note: "Comms = story" (D53) understates it. Comms also owns the whole economy (FT-COM-004/005/009), so the one-liner above says so.

## Summary
Roles are mostly clean, but input and ownership plumbing isn't: as specified, joint views collide in all three M1 layouts (blocker, STN-1), and claims cover only part of each station (STN-3).
Unowned verbs: jump destination (STN-4), mark overflow and Captain marks (STN-5), pair actions missing from station control lists (STN-6), module fitting (STN-9).
Load: the M1 Ops seat is two placeholders and Comms stays a stub through M2 (STN-2). Comms and Weapons have idle stretches, fixable with a content rule (STN-8). The Captain seat needs a defined status view (STN-7).
