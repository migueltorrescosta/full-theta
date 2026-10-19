# CLASH review: clashing requirements

Scope: docs/decisions.md, spec README, 01, 03, 07, 08, 11, 14, issues #1–#13; greps of 02, 05, 06, docs/plan/task-breakdown.md for checks.
Checked and found consistent (not reported): requirement totals (330 active, per-file counts match the README index); 15 pairs and 15 joint views (P1–P15, FT-JNT-004 "12 not built in M1" = 15 − 3); pair tests split P1 (#5) + 9 (#9) + 5 (#10) = 15; S9 load mix 36 crew + 28 viewers = 64 = 6 × 6 + 28; D31 arithmetic (1 − 0.95^5 ≈ 23 %, 1 − 0.9^5 ≈ 41 %); eliminated-crew viewers reuse their existing connection, so they don't press the 64 cap; three players can always cover six stations (any of the 15 perfect matchings of 2-station views); D12/D13/D20 survive only in compatible parts (FT-NET-017/018 cite them for "curated" and "complete", both still true).

### CLASH-1: The universe pause has no exit for a ship that can no longer be covered
- Severity: blocker
- Evidence: FT-NET-034, FT-NET-035 (resume "once every ship's coverage check passes"), FT-GEN-004 (≥ 3 crew), FT-MIS-011/FT-MIS-012 (eliminated crew is out, others continue), FT-MIS-030 + D91 (eliminated crew become viewers or go to the lobby), FT-MIS-016 (abandon the run), D83; issues #6 (pause criterion), #11 (elimination, viewer handover).
- Problem: Three scenarios freeze a whole 6-ship session for good. (a) A 3-player crew loses one player who goes home: the remaining two can never pass the ≥ 3-crew check, and FT-NET-035 only lets "a player of that ship" restore coverage. (b) Ship A is destroyed in M4; its crew turns into viewers of ship B (FT-MIS-030), so ship A's coverage check now fails permanently; the next pause anywhere can never end, because "every ship's coverage check" includes A. (c) A crew abandons the run (FT-MIS-016) — nothing says whether that ship still counts. Mid-run catalogue changes without a disconnect (implied by FT-NET-024 "on station change") are also unspecified: does switching Tactical → Viewer pause the universe?
- Proposal: Add one rule to §3.5: the coverage check (FT-NET-019, FT-NET-034, FT-NET-035) applies only to ships still in play; a destroyed or abandoned ship leaves play. Add an "abandon ship" action available during a pause to that ship's remaining players and to the host, which eliminates the ship (FT-MIS-011 path, D91 lobby/viewers). Forbid mid-run catalogue changes that break coverage outside a pause (server rejects with `CommandRejected`). Changes FT-NET-034/035, FT-MIS-016, adds one FT-NET id; #6 gets a test for (a), #11 a test for (b).
- Options (amends D83):
  - A (recommended): ships out of play are excluded; a paused ship's crew or the host may abandon it (eliminated). Smallest change, keeps D83 for real dropouts.
  - B: also allow players of other ships, Captains and viewers of that ship to take over a station. More flexible, but pulls players off other ships and makes their ship pause in turn.
  - C: no new action; host must end the session. Simple, but one dropout ends a 6-ship evening.
- Affects: #6, #10, #11

### CLASH-2: 10 s grace contradicts "refresh and continue at your station" and the claims rule
- Severity: major
- Evidence: D6, FT-NET-026 (rejoin returns "the same ship, catalogue entry and claims"), FT-NET-024 (claims released when the grace period ends), FT-NET-033 (pick kept for 10 s), D83; #3 S4 criterion (headless client resumes "within 2 s"), #9 (browser stations, tablets over Wi-Fi), #6 reconnect and pause criteria.
- Problem: A tablet player refreshes a browser station (D6's headline case): reloading a Godot web export (tens of MB of wasm over Wi-Fi) and rejoining will routinely exceed 10 s, so every refresh pauses all six ships. Worse, after 10 s the claims and pick are released (FT-NET-024), yet FT-NET-026 promises the rejoiner the same pick and claims — both can't hold if someone else took the mount during the pause. The S4 spike measures a headless native client, so it won't reveal this.
- Proposal: Make FT-NET-026 conditional: restore the pick and claims if still free, else return the player to that ship's lobby pick screen. Measure browser refresh-to-rejoin time in the S3 spike (#3) and on tablets (#4) and set the grace from the measurement. Changes FT-NET-026; adds a criterion to #3 S3 and #4.
- Options (amends D83 only if B):
  - A (recommended): keep 10 s, make FT-NET-026 conditional, measure in S3/#4 and revisit if refresh > 10 s.
  - B: grace 30 s. Fewer pauses; a station sits uncontrolled longer mid-fight.
- Affects: #3, #4, #6, #9

### CLASH-3: The "summaries" toggle leaks Engineering data to Comms, which D68 forbids at every difficulty
- Severity: major
- Evidence: §7.2 row "Summaries of other stations' data | all | exact | banded | absent", FT-PAIR-019, FT-PAIR-010, D68, D84 ("Eng+Comms always verbal"), P12 detail ("Comms buys … on its own banded view of condition"; test "no Engineering data field … beyond its banded summary"); #10 criterion "No Engineering ↔ Comms data link exists at any difficulty (snapshot test, FT-PAIR-010)".
- Problem: On Easy the summaries toggle gives Comms an exact summary of Engineering's condition: that is the status snapshot D68 forbids. On Hard summaries are absent, yet P12 says Comms always has a banded view of condition. So the P12 test and FT-PAIR-019 contradict each other on Easy and Hard, and the #10 snapshot test can't be written to satisfy both.
- Proposal: Exclude Engineering → Comms from the summaries toggle in §7.2 and FT-PAIR-019, and define Comms' fixed view in P12 as what any outside observer knows (for example hull band only, the same at all difficulties), or drop it. Changes §7.2, FT-PAIR-019, P12 text; #10 criterion stays as is.
- Affects: #9, #10

### CLASH-4: The Quartermaster joint view (P12) defeats D68, and its note cites crews that can't exist
- Severity: minor
- Evidence: §3.3 table P12 note "one player sees both, so D68 binds only two-player crews"; D66 (no 2-player crews); D68, D76; FT-PAIR-010; #10 snapshot test for FT-PAIR-010.
- Problem: D76 offers every pair as a joint view, so a Quartermaster player holds both Engineering and Comms and receives both snapshots, which a literal FT-PAIR-010 snapshot test in #10 would flag. The note's "two-player crews" contradicts D66; it presumably means "crews where E and C are held by different players".
- Proposal: Reword the note and FT-PAIR-010: "Between different players holding Engineering and Comms, no data link … ; a Quartermaster player sees both by design (D76)." The #10 test checks two-client setups only. Changes §3.3 note, FT-PAIR-010.
- Affects: #10

### CLASH-5: #8 asks three players to try a single station, which coverage makes impossible
- Severity: major
- Evidence: #8 criterion "Each player tries at least one joint view (Tactical, Systems or Ops) and one single station"; FT-GEN-004, FT-GEN-005, FT-NET-032 (no 3+-station views), §3.3 "a 3-player crew must be an exact partition"; FT-M1-006 / #6 (M1 catalogue has only Tactical, Systems, Ops).
- Problem: With three people and only 2-station views, nobody can pick a single station and still launch; in M1 the only launchable crew is exactly Tactical · Systems · Ops. The owner can't tick this criterion without the dev flag, which removes the 3-player setup being tested.
- Proposal: Replace with "each player plays each of Tactical, Systems and Ops at least once (rotate between runs)". Single stations are tested in #13 (six players).
- Affects: #8

### CLASH-6: Spec and task breakdown not updated for D90–D94, but issues test against them
- Severity: major
- Evidence: §7.2 still shows "Q14" in three Normal cells and says "The Normal value … is open (§14)", while §14 lists Q14 → D90; README "decisions D1–D89", "§14 holds … Q14–Q16"; no FT id mentions D91 (FT-MIS-030 has no lobby/scoreboard fallback) or D92 ("<Preset> (custom)" label); task-breakdown.md E13 and T063 still in M4 (D94 moved browser stations to M2); #9 criterion "presets match spec §7.2 (incl. D90)", #11 criterion cites D91 directly; CLAUDE.md says to use the task breakdown's criteria.
- Problem: #9's agent is told to match §7.2, which still has placeholders; FT-PAIR-018 then can't be traced to a test with defined values. #11 tests a D91 behaviour no FT id requires, so the traceability gate can't see it. An agent following the breakdown would plan browser stations for M4.
- Proposal: One docs PR (or fold into #9) that fills the three §7.2 Normal cells per D90, adds D91 to FT-MIS-030, adds D92 to FT-PAIR-017 / FT-MIS-028, updates the README to D1–D94 and §14 to "none open", and moves E13/T063 deps in the breakdown to M2. No decision changes.
- Affects: #9, #11

### CLASH-7: #9 restricts M2 pair mechanics to four shared systems, but request chips live in CUE
- Severity: minor
- Evidence: #9 criterion "Each pair mechanic uses only the PWR, COND, KNOW and MARK shared systems (FT-PAIR-003)"; FT-PAIR-003 (six systems incl. CUE); §7.1 CUE holds request chips; §7.2 request chips for P2, P6; #9 criterion "request chips expire silently".
- Problem: P2 ("bring mount N to bear") and P6 (power chip) need CUE; read literally the checklist fails these pairs or pushes the agent to build chips outside CUE, a per-pair mechanism FT-PAIR-003 forbids.
- Proposal: Reword to "uses only the shared systems of §7.1 (PWR, COND, KNOW, MARK, CUE; STORY arrives in #10)".
- Affects: #9

### CLASH-8: Issue criteria cite the wrong FT ids, so the traceability gate passes on mislabelled tests
- Severity: minor
- Evidence: #6 "Connection 65 refused … (FT-NET-003, FT-GEN-003)" — the cap is FT-NET-014, while the Host criterion cites FT-NET-014 for spawning (FT-NET-001/003); #6 Ready criterion cites FT-M1-015 (the dev flag); #6 pause criterion cites FT-NET-027 (convergence after rejoin); #7 alert-level criterion cites FT-STN-001–003 instead of FT-STN-008, and the palette criterion cites FT-STN-008; #7 client-shell criterion cites FT-STN-005 (input devices/touch) for interpolation.
- Problem: FT-TST-016 only checks that tagged ids exist, so a test tagged FT-STN-008 for colour-blind palettes marks the alert-level rule as traced while nothing tests it.
- Proposal: Fix the six citations in #6 and #7 bodies (no spec change).
- Affects: #6, #7

### CLASH-9: #13 can't measure the D31 death-risk target from 5 runs
- Severity: minor
- Evidence: D31, FT-MIS-009, FT-MIS-010; #13 M3 criterion "debrief data from ≥ 5 runs … accepts the 5–10 % loss".
- Problem: Five runs give at most 25 encounters (fewer, since a loss ends that ship's run, FT-MIS-011). At a true 7.5 % rate that is about 2 losses, and 2/25 has a 95 % interval of roughly 2–25 %, so the owner can't tell 5 % from 20 %. Fled encounters (FT-MIS-015) also need a rule: count as survived or excluded.
- Proposal: Have #10 add a headless batch run with scripted "average crew" bots that reports the per-encounter loss rate over ≥ 200 encounters for tuning, and keep #13 as a feel check. State in FT-MIS-010 that fled encounters are reported separately.
- Affects: #10, #13

### CLASH-10: More than one Captain makes main-screen control ambiguous
- Severity: minor
- Evidence: FT-NET-016 (any number may pick the same entry), FT-MSC-005 ("only by the Captain when one is seated"), FT-CPT-001; #9 main-screen criterion.
- Problem: Two players pick Captain on one ship and press different view buttons; FT-MSC-005 assumes one Captain, so the server has no rule and the test in #9 can't be written.
- Proposal: Simplest: allow one Captain per ship (lobby greys it out once taken); or "last command wins". Changes FT-NET-016 or FT-MSC-005.
- Affects: #6, #9

Summary
1 blocker: the D83 universe pause can freeze a multi-ship session for good, because destroyed, abandoned or shrunken ships never pass coverage again (CLASH-1).
4 major: grace vs refresh and claims (2), summaries toggle vs D68 (3), an impossible #8 criterion (5), spec not updated for D90–D94 (6); counts, pairs and joint views otherwise add up.
5 minor: Quartermaster note (4), CUE omitted in #9 (7), mis-cited FT ids in #6/#7 (8), death-risk sample too small (9), multiple Captains (10); all small text fixes.
