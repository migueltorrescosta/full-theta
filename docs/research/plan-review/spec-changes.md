# Spec v0.5 change lists (per editor)


# Change list A (02, 03, 10, 12)

## 02-architecture-and-tech.md
- FT-ARC-008 changed: command log records each accepted command with its applied tick, in order (TECH-10)
- FT-ARC-010 changed: architecture lint resolves class_name declarations to their folders (TECH-6)
- FT-ARC-016 changed: director and scenarios get only ids and value copies; writes are queued commands (TECH-7)
- FT-ARC-017 changed: macOS signing and notarisation risk covers the bundled Piper helper too (TECH-4)
- FT-ARC-019 changed: closed set synthesised and cached at Start; fragments for numbers; runtime only free text (D101)
- FT-ARC-020 added: definitions read-only at runtime; sim/ never calls load, preload, ResourceLoader (TECH-6)
- FT-ARC-021 added: pure helpers live in shared/, depending on nothing, passing sim/ purity lint (TECH-6)
- FT-ARC-022 added: desktop release packages bundle same-commit web export and Piper with voices, licences (TECH-4)
- Non-id: §2.2 diagram and dependency rules add shared/ and scenarios/; §2.4 R3 (S3: refresh-to-rejoin, 10 min idle, 6 joins, 1 ms HTTP), R4 (S4: stalled reader, chunking), R5 (S5: NAV-3 widgets, novice drill), R8 (S7b: persistent Piper, combined load, Windows Piper), R10 (real-device Wi-Fi snapshot age in #4), R15 (S9: bytes/s budget ≤ 10 Mbit/s, view-key encode, combined Piper burst); new row R16 (S6 precision check at 10^8 m, site-local D98). 02 does not state the sim's numeric representation, so no stack-table change for TECH-1.

## 03-networking-and-sessions.md
- FT-NET-003 changed: relaunched host offers rejoin of orphaned server; idle server exits after N minutes (D96, TECH-8)
- FT-NET-016 changed: any number share a station or joint view; one Captain per ship (CLASH-10)
- FT-NET-022 changed: "scan and hack queue slots" becomes "the active scan or hack" (STN-3)
- FT-NET-026 changed: rejoin restores pick and claims only if still free, else ship's pick screen (D96, CLASH-2)
- FT-NET-033 changed: grace timed on wall clock outside sim/; 10 s until S3/#4 measurement (D96, TECH-3)
- FT-NET-034 changed: pause triggers only for a ship still in play failing coverage (D96)
- FT-NET-035 changed: resume once every ship still in play passes coverage (D96)
- FT-NET-037 added: on send failure or full queue, stop deltas, resync with full snapshot; never drop events (TECH-2)
- FT-NET-038 added: large messages chunked; voice chunks lower priority than snapshots (TECH-2)
- FT-NET-039 added: static HTTP server never delays a simulation tick by more than 1 ms (TECH-3)
- FT-NET-040 added: encode each snapshot once per distinct view key, shared by matching clients (TECH-9)
- FT-NET-041 added: during a pause, the ship's remaining players or host may abandon it (D96)
- FT-NET-042 added: other ships' players, Captains, viewers may take over unless it breaks their coverage (D96)
- FT-NET-043 added: outside a pause, reject mid-run catalogue changes that break coverage with CommandRejected (D96, CLASH-1)
- FT-NET-044 added: lone player holds all claims; unclaimable controls ship-wide, last writer, attributed (STN-3)
- FT-NET-045 added: dock/jump/Level/face under Helm flight; ammo under mount; Accept under conversation claim (STN-3)
- Non-id: §3.4 prose uses "the active scan or hack" and points to FT-NET-044; §3.5 adds abandonment as a pause exit and "coverage counts only ships still in play" (D96).
- Not applied (not in my assignment): E2's tablet 10-min idle / keep-awake requirement (TECH-3) has no FT-NET id; it appears only as an S3 criterion in 02 R3.

## 10-content-and-data-formats.md
- FT-DAT-006 changed: scenarios live in one scenarios/ folder, extending the Scenario API (TECH-6)
- FT-DAT-009 changed: world actions are queued sim commands; queries return only ids and value copies (TECH-7)
- Non-id: format table row names `scenarios/`.

## 12-testing-ci-and-traceability.md
- FT-TST-009 changed: golden replays apply each logged command on its recorded tick (TECH-10)
- FT-TST-019 added: L6 serves bundled web export and synthesises a line with bundled Piper (TECH-4)
- FT-TST-020 added: baselines record Mesa/llvmpipe version; L5 fails "baseline environment changed" on mismatch (TECH-11)
- FT-TST-021 added: Playwright smoke screenshot of a touch layout from the web build (TECH-11)
- FT-TST-022 added: headless bot batch of ≥ 200 encounters reports per-encounter loss rate (D31, CLASH-9)
- Non-id: L5 and L6 rows in §12.1 mention the Mesa tag and bundled web export/Piper.

## Active requirement counts (no struck-through ids in these files)
- 02-architecture-and-tech.md: 22
- 03-networking-and-sessions.md: 45
- 10-content-and-data-formats.md: 14
- 12-testing-ci-and-traceability.md: 22

# Changes B: 04 and 06

## 04-simulation-flight-combat-damage.md
- FT-SIM-004 changed: assist holds zero rotation, zero drift, forward speed at throttle setpoint (D97 / NAV-2)
- FT-SIM-034 changed: jump targets selected site or mark; data spool time and stand-off (D98 / NAV-4)
- FT-SIM-035 added: positions are site id plus float32 offset, max 200 km; jump changes site (D98 / TECH-1)
- FT-SIM-036 added: all-stop zeroes site-relative velocity through assist thrust (D97 / NAV-2)
- FT-SIM-037 added: hold-to-approach faces target, flies to stand-off (default 500 m), matches velocity (D97 / NAV-2)
- FT-SIM-038 added: integrator uses x += vΔt + ½aΔt², exact for constant thrust (TECH-10)
Prose §4.1: all-stop/approach as assist modes pointing to Helm's controls (§5.1); site-local positions with 200 km largest local coordinate.
Level (NAV-8) not touched: 04 doesn't cover Level (FT-HLM-007 is in 05).

## 06-spatial-language-and-radar.md
- FT-SPA-003 changed: range bands close/mid/far split at 1 and 10 km; clock dropped above ±60° (NAV-7)
- FT-SPA-006 changed: grid square and layer size are scenario data, shown on map legend (D97 / NAV-1)
- FT-SPA-012 changed: cap is 8 named marks; sites, scan positions, hazard zones excluded (D98 / COOP-6)
- FT-SPA-013 changed: Captain fills only empty mark slots, never moves or deletes marks (STN-5)
- FT-SPA-014 changed: mark may attach to a contact's scanned subsystem (COOP-6)
- FT-SPA-015 changed: sites selectable like contacts and marks on every station (D98)
- FT-SPA-022 changed: ninth mark refused with toast on every placement except Relay, which replaces (STN-5)
- FT-SPA-024 added: radar zoom steps 2/10/50 km; off-scale contacts as rim-clamped arrows (NAV-7)
- FT-SPA-025 added: selected contact's stem drawn on top of all others (NAV-7)
- FT-SPA-026 added: clock and height words ship frame everywhere; up/down N world frame after grid (D97 / NAV-1)
- FT-SPA-027 added: sites have shared scenario names as a callout layer for all stations (D98 / NAV-4)
- FT-SPA-028 added: scan positions and hazard zones are MARK items outside cap, survive Hard (COOP-6)
- FT-SPA-029 added: "marks" in FT-PAIR-008 and presets means MARK minus routes and lanes (COOP-6)
- FT-SPA-030 added: forward-view mark must attach to a tapped contact, else nothing placed (STN-5)
- FT-SPA-031 added: pinging an item another station is pinging counts as silent "copy" (COOP-8c)
Prose: §6.1 range bands, fourth layer (sites), frame rule paragraph, grid size from scenario, callout table rows (approach, all-stop, jump), NAV callout grammar block; §6.2 zoom steps, rim arrows, selected stem on top; §6.3 subsystem marks, scan positions/hazard zones outside the cap, ping-as-copy.

## Active requirement counts
- 04-simulation-flight-combat-damage.md: 37 active (1 removed)
- 06-spatial-language-and-radar.md: 30 active (1 removed)

# Change list C: docs/spec/05-stations.md

Also changed (no id): §5.0 gains the common-actions table and the always-live set with bindings; §5.9 intro rewritten to modal focus ("every control reachable, one panel focused at a time"); every station's KB/M, controller and touch lines rebound to avoid common and always-live keys (Weapons C→K claim, R→Q ammo; Comms A/D→Enter/Backspace, open = O; Relay R→G route, F2→N rename, S→X send; Science S→E scan, A→P active ping; Engineering Space→Enter; Helm Shift→B boost, chase on controller moves to the Helm radial); wireframes updated (Helm site/stop/approach, Weapons claim key, out-of-arc direction and guided fire, Engineering harden/probe, Science keys and scan axes, Relay lane flag, Comms accept keys, Captain chips and cards, joint-view focus markers).

- FT-STN-006 changed: allegiance and alert level also encoded by letter or shape (UX-8)
- FT-STN-009 added: common actions bound identically; station keys never reuse common or always-live keys (D95 / UX-5)
- FT-STN-010 added: every crew station places marks and sends its pairs' request chips (D44 / STN-6)
- FT-STN-011 added: controls overlay on ?, View or i, generated from input map, translated (D100 / UX-1)
- FT-STN-012 added: first-run tooltips explain controls only; dismissable, once per client and station (D100)
- FT-STN-013 added: per-client UI scale 75–150 %, persisted like bindings (UX-8)
- FT-STN-014 added: every hold input switchable to a toggle in the bindings (UX-8)
- FT-STN-015 added: lobby catalogue shows light/busy/intense load tag per station and joint view, from StationDef (D99 / E7)
- FT-STN-016 added: lobby defaults to Easy on first launch; toggles behind Customise with two-station descriptions (UX-9)
- FT-STN-017 added: per-client comfort toggle, horizon-locked roll and reduced FOV, for cockpit, turret, main screen (NAV-6, NAV-9)
- FT-HLM-002 changed: chase camera on controller moves from View to the Helm radial (D95)
- FT-HLM-003 changed: target compass also shows a selected site (D98)
- FT-HLM-007 changed: Level rolls first; a second press also pitches onto the ecliptic (D97 / NAV-8)
- FT-HLM-014 added: all-stop zeroes velocity and rotation through real thrust, one input per device (D97 / NAV-2)
- FT-HLM-015 added: hold-to-approach faces selected item, flies to stand-off, matches its velocity (D97 / NAV-2)
- FT-HLM-016 added: JUMP targets selected site or mark once faced; sites selectable on Helm (D98 / NAV-4)
- FT-HLM-017 added: every Helm action, including select, Level, decoupled, all-stop, approach, has controller binding (NAV-5)
- FT-WPN-005 changed: out-of-arc indicator shows the clock and height direction into arc (NAV-6)
- FT-WPN-008 added: Weapons fires guided ordnance at a mark attached to a tracked contact (P8 / STN-6)
- FT-WPN-009 added: mount holds aim in world space at traverse rate; camera roll follows aim horizon (NAV-6)
- FT-ENG-008 added: Engineering pre-hardens a chosen subsystem and fabricates probes from spare parts (P11 / STN-6)
- FT-SCI-012 changed: minigames also take at most 45 s for a first-time player (UX-4)
- FT-SCI-014 added: scan minigame rotation axes grow with noise, 1 when clean to 3 (UX-4)
- FT-SCI-015 added: a class fully scanned this run starts later scans pre-aligned on two axes (UX-4)
- FT-SCI-016 added: match quality above lock threshold raises scan result confidence (UX-4)
- FT-RLY-011 added: Relay flags lanes crossing friendlies; Weapons warned before a shot along one (P8 / STN-6)
- FT-CPT-004 added: Captain sees read-only open request chips and Comms' mission and contract cards (COOP-10, STN-7)
- FT-CPT-005 added: Captain ping on a mission or contract card shows it on the main screen (COOP-10)
- FT-MSC-001 changed: forward camera horizon-stabilised; switches to chase while decoupled or rolling fast (NAV-9)
- FT-MSC-005 changed: Captain's reconnect grace counts as seated for main-screen control (STN-7)
- FT-MSC-006 added: status view shows hull, shields, subsystem health, active objectives, alert level (STN-7)
- FT-JNT-001 changed: station bindings route to the one focused panel of a joint view (D95 / STN-1)
- FT-JNT-002 changed: a station's bindings identical in every view; always-live set collides with none (D95 / UX-2)
- FT-JNT-005 added: joint view gets union of data; its internal shortcuts on, requests direct actions (COOP-1)
- FT-JNT-006 added: lobby shows a one-line hint per joint view naming the pair made solo (COOP-1)
- FT-JNT-007 added: always-live set (alert, ping, panel switch, Helm translation, face, all-stop) ignores focus (D95)
- FT-JNT-008 added: Tactical cockpit mode on Helm focus, turret mode on Weapons focus, defined (D95 / STN-1)

Active requirements: 05-stations.md 106 (was 79; none removed).

Notes for the coordinator:
- README glossary "Joint view ... keeping every control of each" should become "every control reachable, one panel focused at a time" (D95). Not my file.
- FT-STN-015 (load tags) and FT-STN-016 (lobby Easy default, Customise, toggle descriptions) are lobby behaviour; I put them in 05 as FT-STN. If 03 (lobby) or 07 (§7.2 toggles) gains an equivalent line, keep one and point the other to it.
- FT-JNT-006 (lobby hint per joint view) is also lobby behaviour; same note.
- D95 says the panel switch is "a bumper"; since RB is the common cycle-target button, the controller panel switch is hold View + LB/RB (STN-1's proposal). Controller Helm translation can't be always-live (the focused panel owns the sticks), so the always-live Helm translation is KB/M only; stated in §5.0.
- Science "queue" wording: §5.4 had none (the only "queue" in 05 is Engineering's repair queue); nothing to remove here.
- FT-HLM-016 leaves spool time and stand-off to data and §6/§4 (E4); 06 defines site names; 04 may hold the jump mechanics (FT-SIM-034).
- FT-CPT-005 doesn't set how long a pinged card stays on the main screen; add to §14 if the owner wants it fixed.

# Changes D (07, 08, 09, 11)

## 07-cooperation-pairs.md
Prose: §7.2 heading cites D90, D92; '<Preset> (custom)' sentence; summaries row excludes Engineering → Comms; request-chips row points to the per-station list and covers P1, P2, P3, P6, P9, P10, P11; three Q14 cells filled per D90 (voice, voice, on) and the "open (§14)" sentence replaced by: verbal means same-room speech, remote players need external voice, callout grammar §6.1, callout card `docs/callout-card.md` (M2, #9). §7.3 gains one sentence pointing to FT-JNT-005 (joint views make their own pair a direct action). P7 hack window ≥ 8 s. P12 rewritten: different players only, Quartermaster sees both (D76), purchases land in COND, Comms' fixed view is hull band only at every difficulty, test exempt from co-op beats solo and replaced by the reverse-flow sim test. New §7.4 paragraphs: "Request chips" (data list of 7 chips) and "Plays" table (Over-horizon strike R→S→W, Hack alpha S→H+E+W, Bluff call C→S→C→W).

- FT-PAIR-008 changed: "marks" means MARK items except routes and approach lanes, per FT-SPA-029 (D69 / COOP-6)
- FT-PAIR-010 changed: no E↔C link between different players; Comms sees hull band only; Quartermaster sees both (D68, D76 / CLASH-3, CLASH-4)
- FT-PAIR-012 changed: player-initiated chips and no "talk to X" prompts apply outside training scenarios (D100)
- FT-PAIR-013 changed: debrief also counts cooperative events per pair (COOP-4)
- FT-PAIR-015 changed: co-op beats solo by per-pair `pair_min_gain` (25 % start); P12 exempt, tests purchases reach COND (COOP-2, COOP-3)
- FT-PAIR-017 changed: changed toggles show the preset as '<Preset> (custom)' (D92 / CLASH-6)
- FT-PAIR-018 changed: justification adds D90 now that Normal values are filled (D90 / CLASH-6, COOP-11)
- FT-PAIR-019 changed: summaries toggle excludes Engineering's data on Comms at every difficulty (D68 / CLASH-3)
- FT-PAIR-021 added: request chips are a data-defined list per station, including four new chips (COOP-7)
- FT-PAIR-022 added: each named play has an end-to-end full-chain-beats-broken-chain test (COOP-5)
- FT-PAIR-023 added: hack window is a data value of at least 8 s (COOP-5)

## 08-missions-director-progression-economy.md
Prose: §8.1 named sites, site-local positions and jumps change the site (D98, FT-SIM-035, §6); Shakedown listed among initial scenarios; §8.2 death risk tuned with headless bot batches; §8.3 D91 lobby + live scoreboard; §8.4 bought modules fitted at once.

- FT-MIS-009 changed: loss rate tuned with headless average-crew bot batches of ≥ 200 encounters (D31 / CLASH-9)
- FT-MIS-010 changed: debrief reports fled encounters separately from losses (D31 / CLASH-9)
- FT-MIS-026 changed: travel between named sites with site-local positions, referencing FT-SIM-035 and §6 (D98)
- FT-MIS-028 changed: custom toggles keep difficulty's threat budget, shown as '<Preset> (custom)' (D92 / CLASH-6)
- FT-MIS-030 changed: with no surviving friendly ship, eliminated crew returns to lobby with live scoreboard (D91 / CLASH-6)
- FT-MIS-036 changed: bought module fitted at once; full slot sells old one in same trade, on offer card (STN-9)
- FT-MIS-037 added: Easy target, first-time crew survives at least 3 of 5 encounters, owner-tunable (UX-7)
- FT-MIS-038 added: debrief logs each station's time to first use of core actions (UX-7)
- FT-MIS-039 added: Shakedown training scenario: no director, no elimination, drone, staged subtitled lines, one pair per step (D100)
- FT-MIS-040 added: host pause in co-op sessions only, reusing the coverage-pause path FT-NET-034 (D100)
- FT-MIS-041 added: every hostile encounter has a Comms beat (lint-checked); travel legs may carry point-defence hazards (STN-8, UX-6)
- FT-MIS-042 added: contract target flags (disable, protect) held in faction KNOW for allied Weapons under P9 (D82 / COOP-9)

## 09-audio-tts-languages.md
Prose: §9.1 closed set synthesised at Start and cached per language, numbers from fragments, runtime only for free text, one persistent Piper process off the sim thread (D101).

- FT-AUD-003 changed: dynamic lines voiced with Piper as in FT-AUD-018 and FT-AUD-019 (D101)
- FT-AUD-015 changed: 1 s latency target now applies to free-text lines only (D101)
- FT-AUD-018 changed: closed set synthesised at Start, cached per language; numbers from fragments; runtime only free text (D101 / TECH-5)
- FT-AUD-019 added: one persistent Piper process on the host, off the sim thread, streams clips to one client (D85, D101 / TECH-5)

## 11-milestone-1.md
Prose: intro adds marks, pings and Relay's map read-out (D99); §11.1 scope items for assist holds, all-stop, approach and site-local positions (D97, D98), Relay's map read-out, modal joint views and load tags (D95, D99), marks and pings, controls overlay and first-run tooltips (D100), seat-rotating playtest (D99); list renumbered 1–16 (prose list, no ids).

- FT-M1-003 changed: M1 flight includes assist holds, all-stop and hold-to-approach (D97)
- FT-M1-006 changed: M1 joint views are modal with one focused panel (D95)
- FT-M1-017 added: M1 includes marks, pings and Relay's map read-out (FT-RLY-001–003, FT-SPA-006/012–015) (D99)
- FT-M1-018 added: M1 lobby shows a load tag per station and joint view (D99)
- FT-M1-019 added: M1 includes the controls overlay from the input map and first-run tooltips (D100)
- FT-M1-020 added: M1 stores positions as site id plus local offset, per FT-SIM-035 (D98)
- FT-M1-021 added: M1 playtest rotates every player through Tactical, Systems and Ops (D99)

## Active requirement counts
- 07-cooperation-pairs.md: 22 (+1 removed)
- 08-missions-director-progression-economy.md: 40 (+2 removed)
- 09-audio-tts-languages.md: 19
- 11-milestone-1.md: 21

## Notes for the coordinator
- §3.3's P12 note ("D68 binds only two-player crews", 03) is not in my files; FT-PAIR-010 and the P12 detail now carry the CLASH-4 wording, so 03's note should match.
- FT-PAIR-007 (Easy share buttons) and 05's FT-COM-009 were left as they are; the module-fitting rule lives in FT-MIS-036.
- README index counts for 07, 08, 09, 11 need the numbers above.
