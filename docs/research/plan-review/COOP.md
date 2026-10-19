# COOP review: are collaboration and communication between stations well explored?

Scope: 07-cooperation-pairs, 06-spatial-language-and-radar, 05-stations, research/pairs-and-combos, decisions D14, D44, D55–D61, D67–D69, D76, D82, D84, D90, issues #7, #9, #10, #11 (checked #13, 03-networking §3.3, 14-open-questions where a finding needed it).

### COOP-1: Joint views silently turn three pairs into solo work, including M1's only pair, and the spec never says how chips and toggles behave inside one seat
- Severity: major
- Evidence: D66 (minimum crew 3), D67/D76 and FT-NET-032 (any 2-station joint view, no 3+ views), 03-networking §3.3 ("a 3-player crew must be an exact partition"), FT-NET-008 (snapshot filtered to the stations a client holds), D72 and 11-milestone-1 (M1 = the Eng+Helm loop P1), §5.1 (Helm "Shift boost request"), FT-PAIR-009, #9 "Hard leaks nothing but marks and pings".
- Problem: With 3 players, the most common crew, exactly 3 of 15 pairs happen inside one head. The lobby accepts every one of the 15 partitions, so a crew that picks an H+E view with W+S and R+C makes P1 (the M1 milestone loop) and P7 (weak points) solo. Nothing tells the crew this. The spec also never says what a request chip from Helm to Engineering does when the same player holds both (a chip to yourself). It doesn't say whether the per-toggle Hard snapshot test applies between two stations of one seat either. An implementer following #9's "Hard leaks nothing" could strip a Systems seat's own diagnosed cause from its own Engineering panel.
- Proposal: Add one requirement to §5.9, FT-JNT-005: "A joint view gets the union of its stations' data; data shortcuts and request chips between its own stations don't apply: the data shows as if the toggle were on, and a request runs as the target station's own action (Boost in an H+E view overcharges directly)." Add a one-line lobby hint per joint view naming the pair it makes solo ("Tactical: Helm+Weapons arcs are yours alone"). Extend #9's snapshot-filter criterion with a joint-view case.
- Options:
  1. (Recommended) FT-JNT-005 plus the lobby hint. Trade-off: P1 can still go solo in M1, but the crew knows it.
  2. Also pin M1's 3-player crews to partitions that keep P1 across seats (the H+E view isn't offered in M1). Trade-off: amends D67's "players pick any" for M1 only.
- Affects: #7, #9

### COOP-2: P12 (Engineering + Comms) can't meet FT-PAIR-015, and its Easy summary contradicts D68
- Severity: major
- Evidence: FT-PAIR-015 (every pair: automated test, co-op beats solo), P12 test in §7.4 (it checks only that an offer can be accepted and that nothing leaks), FT-PAIR-010, D68; §7.2 "Summaries of other stations' data: all, exact on Easy" vs P12 "Comms buys on its own banded view of condition"; #10 criterion "pair tests for P5, P9, P12, P14 and P15 pass (co-op beats solo, solo completes); P12 tested without the data link".
- Problem: P12's only channel is speech, and a headless test has no speech. So "co-op beats solo" for P12 can only be faked by scripting Comms as if it had been told, which tests nothing. #10's criterion can't be met honestly. Separately, the summaries toggle says "all" pairs are exact on Easy, while P12 says Comms always sees a banded view. On Easy, either Comms sees exact condition and P12 has no reason to exist, or P12 is an unstated exception to FT-PAIR-019. P12 also flows one way: the spec never says that Comms' purchases (parts, ammo, propellant) land in Engineering's COND, which is the half that's testable.
- Proposal: Amend FT-PAIR-015 to exempt P12 from co-op beats solo, and replace it with two checks. (a) A sim test of the reverse flow: parts Comms buys appear in Engineering's spares, and a dock repair Comms buys clears an Engineering fault. (b) A P12 observation in #13. Add a line to FT-PAIR-019: "Comms' summary of COND is banded at every difficulty except Hard, where it is absent (D68)." Fix #10's criterion to match.
- Affects: #10, #13

### COOP-3: "Co-op beats solo" with no effect-size floor makes every pair optional
- Severity: major
- Evidence: FT-PAIR-004 (every pair has a no-partner path), FT-PAIR-015 and every §7.4 test ("faster", "less damage", "<", ">"), #9 and #10 pair criteria, D31 (death-risk target is measured only per encounter).
- Problem: A 1 % gain passes every pair test, so a crew can ignore P5, P11, P14 or P15 and still win, and tuning has no target. Example: the P11 test passes if hardening on the forecast saves one hull point in an ion storm. No Engineering player will listen to Relay's countdown for that. The design promise ("cooperation is the way to win") lives nowhere in the requirements.
- Proposal: Have each pair test assert a data-defined minimum gain, `pair_min_gain` per pair in the balance Resource, starting at 25 % on the pair's metric. #13 tunes it. Change FT-PAIR-015 to "beats solo by at least its data-defined margin". Keep FT-PAIR-004 as is.
- Affects: #9, #10, #13

### COOP-4: Nothing checks that cooperation actually happens with people
- Severity: major
- Evidence: §7.4 tests use "scripted inputs" for both partners, so they check the payoff, not whether players communicate; FT-PAIR-013 (only unanswered chips reach the debrief); #13 M2 criterion "feedback recorded here (FT-PAIR-001)"; CUE holds a "debrief log".
- Problem: After M2 the owner plays six-player sessions, but no criterion says whether P3, P13 or P15 ever happened. A pair that's never used (say, nobody places a scan-position mark) can't be told apart from one that works. FT-PAIR-001 is "verified" by a feedback note.
- Proposal: Extend FT-PAIR-013 into "The debrief shall count, per pair, the cooperative events that occurred (chip sent and answered, shortcut shared, mark placed by one station and used by another, probe-enabled scan, scan-unlocked dialogue option)." The CUE debrief log already exists, so this is a counter, not a system. Change #13's M2 criterion to: "per-pair event counts from ≥ 3 sessions recorded; every pair with zero events gets a tuning issue".
- Affects: #9, #10, #13

### COOP-5: Only pairs are designed; the 3–4-station plays that make combat interesting have no design, timing or test
- Severity: major
- Evidence: §7.3–7.4 (15 isolated pairs), FT-SCI-008 ("limited window", no length), P7 (hack window), P8 (guided fire at a Relay mark), P13, P14, P9; §7.2 Hard (all of these by voice).
- Problem: The best moments are chains. Relay probes a nebula, Science scans through the probe (P13), the weak point goes to Weapons (P7), and Weapons fires guided at Relay's mark (P8). Or Science hacks engines, and the window needs Helm to bring mounts to bear (P2) and Engineering to put power on weapons (P6) before it closes. On Hard each hop is a spoken sentence, and no requirement makes the hack window outlast a three-hop voice chain. So a window tuned per pair on Easy could close before the shot on Hard. No test checks a chain end to end, so pairs that pass alone can still break when combined.
- Proposal: Name 2–3 "plays" in §7.4 (Over-horizon strike R→S→W, Hack alpha S→H+E+W, Bluff call C→S→C→W). Give each one L2 scripted test in the issue that ships its last pair: the full chain beats any chain with a link removed. Make the hack window a data value with a floor stated in the spec (for example ≥ 8 s so a spoken relay fits) instead of "limited".
- Affects: #9 (Over-horizon, Hack alpha), #10 (Bluff call)

### COOP-6: On Hard, MARK becomes the only data channel, but its cap, scope and subsystem targeting are undefined
- Severity: major
- Evidence: FT-PAIR-008 ("except marks and pings"), §7.1 (MARK holds marks, pings, routes, lanes, hazard zones, scan positions), §7.2 (scan-position mark "all levels", routes off, P4 "marks as waypoints"), FT-SPA-012 (8 marks), FT-SPA-014 (attached to a contact only), D26 (hit location = nearest subsystem), P7 Hard "called out".
- Problem: (a) On Hard a Relay routing through a minefield uses marks as waypoints (say 4). The mission is one mark, the guided-fire target one, Science's scan position one and the Captain's one: Alpha–Hotel are full mid-fight. It's also unclear whether scan-position marks and hazard zones count against the 8 or survive Hard, so the Hard snapshot test in #9 has to guess. (b) P7 on Hard: Science says "engines are the weak point", but Weapons can't see brackets. Nothing in the spec makes subsystems visible on a target's model, so aiming "at the engines" depends on art that nobody specified. That makes P7 degenerate (not just harder) on Hard.
- Proposal: (a) State in §6.3 that scan-position marks and hazard zones are MARK items separate from the 8 named marks, that both survive Hard, and that FT-PAIR-008's "marks" means everything in MARK except routes and lanes. (b) Extend FT-SPA-014: "a mark may attach to a contact or to one of its scanned subsystems". Weapons then sees a diamond on the engine, which survives Hard and reuses existing code.
- Options (for a):
  1. (Recommended) Scan positions and hazard zones outside the 8-mark cap. Trade-off: two more kinds of item on screen.
  2. Everything counts; raise the cap on Hard. Trade-off: amends D44 (8 marks).
- Affects: #9

### COOP-7: Request chips cover only 3 of 15 pairs, all aimed at Helm or Engineering; Science, Relay and Comms can't ask for anything
- Severity: major
- Evidence: §7.2 "Request chips (boost, power, bring to bear) P1, P2, P6"; P11 ("Engineering fabricates probes from spare parts on request", no request mechanism); P10 (sensor pips); P3 (Science wants Helm at the mark); P9 (Comms needs "hold fire on H2" during a surrender); FT-PAIR-012.
- Problem: Requests only go to Helm and Engineering. The stations that depend most on others have no quiet way to ask. Science needs sensor power or Helm at the scan mark, Relay needs a probe fabricated, Comms needs Weapons to hold fire while H2 surrenders. Several pairs (P3, P4, P11, P13) are one-way flows that the receiving station can ignore, and the sending station can only shout. The worst case is P9: Weapons destroying a surrendering contact costs reputation, and Comms' only tool is voice, even on Easy.
- Proposal: Make request chips a small data-defined list per station under the existing toggle, adding four: "sensor power" (S→E), "to scan mark" (S→H), "fabricate probe" (R→E), "hold fire on <callsign>" (C→W). Same CUE mechanics, same expiry, still player-initiated (FT-PAIR-012). No new system.
- Affects: #9, #10

### COOP-8: No voice protocol, and the spec assumes but never states that crews share one room
- Severity: minor
- Evidence: 13-licensing (voice chat omitted), D69/D84 Hard ("verbal only except marks and pings"), D45 (callout grammar covers content, not who speaks), D39/FT-AUD-005 (Comms hears NPC TTS while the crew talks), request chips off on Hard (FT-PAIR-009).
- Problem: Hard turns every shortcut into speech exactly when chips go away, so six players in a fight all talk at once. Meanwhile the Comms player tries to hear an NPC's terms and the ship computer speaks on several stations' speakers. Nothing supports turn-taking. Since there's no voice chat, a tablet player in another room can't play Hard at all, and the spec never says so.
- Proposal: (a) Add a co-location assumption to spec §1/§7: "verbal" means same-room speech, and remote players need external voice. (b) Add a one-page callout card to `docs/` (station → subject → action, answered by "copy"; Captain or Relay breaks ties). (c) Let a ping on a callsign or mark that someone else pinged act as an acknowledgement (shows "✓ Weapons"). That gives Hard a silent "copy" through the one channel D69 keeps. No new system.
- Affects: #9, #12 (docs)

### COOP-9: Allied ships share reputation but not contracts, so one ship's Weapons can wreck another ship's deal
- Severity: major
- Evidence: D82 (faction knowledge and reputation shared, marks per ship), §7.1 (KNOW per faction holds intent; STORY holds contracts, with no keying stated), P9 (contract flags on Weapons' reticle), FT-SPA-021 (Relay-to-Relay marks are the only ship-to-ship tool), #11 (tests only knowledge and callsign sharing).
- Problem: Ship A's Comms accepts "disable H2, do not destroy". Ship B, same faction, sees H2 as hostile and destroys it. The shared faction reputation drops, and ship B never had a flag on its reticle. Ship-to-ship cooperation is just Relay sending marks. Nothing lets allied Comms stations coordinate who takes which contract, or lets allied Weapons focus or hold fire.
- Proposal: Put contract target flags ("disable", "protect") into faction KNOW next to intent, so allied Weapons see them under the same P9 toggle. Add to FT-SPA-021's inbox flow: "Comms may send a contract card to an allied Comms (read-only, Accept to co-sign)". Or, as the lazy minimum, just the KNOW change and leave the rest verbal. Add a #11 criterion: an allied ship sees a contract flag and loses no reputation for honouring it.
- Options:
  1. (Recommended) Contract flags in faction KNOW only. Trade-off: allied Comms still coordinate by voice.
  2. Also allow allied Comms to share contracts. Trade-off: more UI; brushes against D57 (Comms decides alone) for multi-ship.
- Affects: #10, #11

### COOP-10: The Captain seat delivers less than D15's "overview"
- Severity: minor
- Evidence: D15 ("information only (overview + main screen control)"), §5.7 (mirror of the main screen, ping, mark only), FT-CPT-001–003, FT-PAIR-002.
- Problem: The Captain is meant to coordinate, but sees only what the viewers see. That means no open request chips, no mission or contract board and no station summaries, so they can't prioritise ("ignore the hail, finish H2") any better than a viewer. For a sixth or seventh player that's a dull seat.
- Proposal: Give the Captain read-only views of the CUE feed (open chips per station) and of Comms' mission and contract cards. Let a Captain ping on a card put it on the main screen. Both are reads and pings, so FT-CPT-003 holds. Add them as FT-CPT-004/005 in #9.
- Affects: #9

### COOP-11: Stale text the implementing agents are told to read
- Severity: minor
- Evidence: §7.2 still shows "Q14" in three Normal cells and says "The Normal value of the three Q14 toggles is open (§14)", though D90 settled them. research/pairs-and-combos.md §1 P12 still describes the one-key Status report (removed by D68), and §2 still lists 1–2-player and 3-station combos (removed by D66, D76). #7 and #9 tell agents to read that research file.
- Problem: An agent following #9's instructions may build the P12 status report or a 3-station Ship seat. Or it may leave the D90 toggles unset because the spec still calls them open.
- Proposal: In §7.2, replace the Q14 cells with D90's values (contract flags: voice, Science icons: voice, mission mark icon: on) and delete the "open" sentence. Add a header line to pairs-and-combos.md: "Superseded by spec 07 and D66–D90; P12 and §2 are historical."
- Affects: #7, #9, #10

## Summary
The 15 pairs are well specified one at a time. Gaps appear where pairs meet real crews: joint views make three pairs solo silently, chains of 3+ stations and Hard's mark-only channel are undesigned, and requests flow only to Helm and Engineering.
Tests check each mechanic's payoff with no minimum gain and never check that cooperation happens. P12 can't meet FT-PAIR-015 as written.
Multi-ship cooperation is thin (contracts don't cross allied ships) and the Captain gets less than D15's overview. Most fixes are one requirement or one data value, not new systems.
