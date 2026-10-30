# 8. Missions, director, progression and economy

## 8.1 Runs and encounters

A run is 4 to 6 encounters per ship in 20–40 minutes, the director closing it by pacing and budget (D31, D236, v0.3 §2). Each scenario has a single global open 3D map; there are no per-encounter maps and no sector map (D29, D77). An encounter is a self-contained situation (enemy wave, rescue, derelict, negotiation...) that the director places or activates at a site on that map, with its own triggers and outcome (D77). The scenario seeds some known sites at start; the director spawns more over time within its budget, and each spawn is logged for the debrief (D80). Named sites are points on that map; ships move between them by impulse flight and travel fast with the jump drive, and a site's position and radius serve callouts, encounter triggers, docking and the director (D77, D229, FT-SIM-035, §6). One encounter is active per ship at a time; it starts when the ship arrives at its site or after a data-defined timeout (D231). Initial scenarios: enemy waves, rescue and the Shakedown training scenario (D100); later exploration, branching encounters and negotiations, all built from reusable components (v0.3 §7).

## 8.2 Director

The director picks and parameterises scenario components by pacing and threat budget. It changes which events happen, never the rules (v0.3 §7). Every decision is logged with its reason and shown in the end-of-run debrief (D35). One difficulty (Easy, Normal, Hard) is chosen per session before start; it sizes the director's threat budget, a run total held per crew faction (the fleet's, in co-op), and the strength of each encounter, and presets the data-shortcut toggles (§7.2); no hidden stats (D33, D14, D81, D84). Death risk target: 5–10 % chance of losing the ship per encounter for an average crew, about 23–41 % per run of 4 to 6 encounters, tuned with headless bot batches and checked in playtests (D31, plan review CLASH-9).

## 8.3 Outcomes

Per-ship elimination: a destroyed ship's crew is out and its run progress resets; other ships carry on (D30). In an encounter, a ship wins once every ship of a hostile faction is destroyed or has retreated; a retreated ship stays in the world (D120). Each scenario defines what an eliminated crew does; by default its players become viewers of a surviving friendly ship's main screen, or return to the lobby with a live scoreboard when none survives (D79, D91). A co-op session with several allied ships is one fleet run: one director per crew faction, its encounters scaled to the faction's ship count, and one final objective that wins it (D30, D258). Each scenario sets a relaunch policy per side, none, N lives or unlimited; a relaunch is a fresh ship of the same slot with a fresh run state, by a vote of its crew (D259). PvP comes as three distinct scenario types (D78): a race through the same run, one seeded encounter list in the same order and strength for every ship, each ship at its own copy of each site, won by the first ship to complete the final objective (D262, D270); last ship standing, where the director sends raider waves of growing strength at every surviving ship and there is no time limit (D264); and two-faction teams, with co-op inside each faction, where the host picks last team standing or first team to finish and crews put their ship on team A or B (D82, D263). A holdout mode pits a small side with unlimited relaunches against a side with finite lives, scored by how long the finite side lasts (D259). In PvP each side starts at its own site (D269). A crew may flee an encounter at a cost or abandon the run (D36).

## 8.4 Economy

| Resource | Use | Decision |
|---|---|---|
| Credits | Trade, repairs, upgrades | D34 |
| Ammunition | Missiles, torpedoes, etc. | D34 |
| Propellant | Thrust and jumps, not coasting | D34 |
| Spare parts | Repairs, probe fabrication | D27, P11 |
| Probes | Relay coverage | D56 |
| Reputation per faction | Prices, clearances, contracts; changes drawn from per-interaction distributions | D34 |

Upgrades bought during a run create distinct ship builds (v0.3 §7). Upgrades are modules fitted to a ship's slots, each with a trade-off (for example more power, more heat), bought while docked through Comms and fitted at once (D86, plan review STN-9).

## 8.5 Requirements

- **FT-MIS-001** A run shall consist of 4 to 6 encounters per ship, chosen by the director by pacing and threat budget; the director closes the run once the fewest are played and nothing fits the budget, or the most is reached. (D31, D236)
- ~~**FT-MIS-002**~~ Removed (D77): superseded by FT-MIS-024 to FT-MIS-026.
- **FT-MIS-003** The first scenarios shall include enemy waves and a rescue mission. (v0.3 §7)
- **FT-MIS-004** Missions shall offer consequential choices and clear outcomes. (v0.3 §7)
- **FT-MIS-005** The director shall change only which events occur and their parameters, never simulation rules or stats. (v0.3 §7)
- **FT-MIS-006** Every director decision shall be logged with its reason and shown in the end-of-run debrief. (D35)
- ~~**FT-MIS-007**~~ Removed (D81, D84): superseded by FT-MIS-028 and FT-MIS-029.
- **FT-MIS-008** Difficulty shall never change hidden stats. (D33)
- **FT-MIS-009** Encounter budgets shall be tuned so an average crew loses the ship in 5–10 % of encounters, measured by headless batches of scripted average-crew bots over at least 200 encounters and checked in playtests. (D31, plan review CLASH-9)
- **FT-MIS-010** The debrief shall report per-encounter ship losses, with fled encounters reported separately, so the death-risk target can be measured. (D31, D35, plan review CLASH-9)
- **FT-MIS-011** A destroyed ship's crew shall be out of the run, and that ship's run progress shall reset, unless the scenario's relaunch policy lets its crew relaunch by vote. (D30, D259)
- **FT-MIS-012** Other ships shall continue after one ship is destroyed. (D30)
- **FT-MIS-013** A co-op session shall be won by completing the final run objective, one for the whole fleet. (D30, D258)
- **FT-MIS-014** A PvP session shall be won by the condition of its mode. (D30)
- **FT-MIS-015** A crew shall be able to flee an encounter at a data-defined cost; jumping out while a ship of a hostile faction detects the ship is fleeing, and costs credits and a reputation draw from data besides the jump's propellant. (D36, D233)
- **FT-MIS-016** A crew shall be able to abandon the run, in PvP too, by the same majority vote or by the host at once. (D36, D241, D267)
- **FT-MIS-017** Run state shall be one object owned by the simulation; resetting it shall restore definitions exactly. (D30, D32)
- **FT-MIS-018** The economy shall track credits, ammunition by type, propellant, spare parts, probes and reputation per faction. (D34, D27, D56)
- **FT-MIS-019** Reputation changes shall be drawn from seeded, data-defined distributions specific to each interaction type. (D34)
- **FT-MIS-020** Comms shall show the range of a reputation change where the data marks it visible. (D34)
- **FT-MIS-021** Players shall earn credits, salvage, repairs and upgrades during a run. (v0.3 §7)
- **FT-MIS-022** Upgrades shall create distinct ship builds. (v0.3 §7)
- **FT-MIS-023** In multi-ship sessions, director, balance and run-reset rules shall be keyed per faction: one fleet director per crew faction in co-op, and per side in PvP. (D21, D258)
- **FT-MIS-024** Each scenario shall take place on a single global open 3D map, with no per-encounter maps and no sector map. (D29, D77)
- **FT-MIS-025** An encounter shall be a self-contained situation with its own triggers and outcome, placed or activated by the director at a site on the scenario map; it starts when the ship arrives at the site or after a data-defined timeout, with one active encounter per ship. (D77, D231)
- **FT-MIS-026** Ships shall move between named sites, points on the scenario's one map, by impulse flight and by the jump drive (FT-SIM-034, FT-SIM-035, §6). (D29, D77, D229)
- **FT-MIS-027** A scenario shall seed some known sites at start; the director shall spawn further sites over time within its budget and log each spawn for the debrief. (D35, D80)
- **FT-MIS-028** One difficulty (Easy, Normal or Hard) shall be chosen per session in the lobby before start; it shall size the director's threat budget and preset the data-shortcut toggles; changing single toggles shall keep the chosen difficulty's threat budget and show the preset as '<Preset> (custom)'; the difficulty shall also scale each encounter's strength (enemy count), and every encounter shall cost at least 1 of the budget, only the Shakedown being free. (D33, D81, D84, D92, D242)
- **FT-MIS-029** The director shall hold a separate threat budget for each crew faction, the fleet's total over the run, its encounters' strength scaled to the faction's ship count, sized by the session difficulty (starting values Easy 6, Normal 9, Hard 12, tuned in #13) and spent as encounters are picked, each encounter costing its scenario's threat cost. (D81, D242, D258)
- **FT-MIS-030** Each scenario shall define what an eliminated crew does; by default its players shall become viewers of a surviving friendly ship's main screen, or, when no friendly ship survives, return to the lobby with a live scoreboard; in PvP a crew that gives up goes to a friendly ship's viewer or the scoreboard. (D79, D91, D267)
- **FT-MIS-031** PvP shall be offered as three distinct scenario types: race the same run, last ship standing, and two-faction teams. (D78)
- **FT-MIS-032** A race scenario shall be won by the first ship to complete the final run objective; ship-to-ship combat stays allowed. Every ship plays the same seeded encounter list at its own copy of each site, and the director does not adapt to a crew. (D37, D78, D262, D270)
- **FT-MIS-033** A last-ship-standing scenario shall be won by the last ship not destroyed; the director sends raider waves of growing strength at every surviving ship, with no time limit. (D78, D264)
- **FT-MIS-034** In a two-faction team scenario, the ships of each team shall share one faction and cooperate; the host shall pick the win rule, last team standing or first team to finish, and crews shall put their ship on team A or B, any split with at least one ship a side. (D78, D82, D263)
- **FT-MIS-035** Upgrades shall be modules fitted to a ship's slots, each defined in data with a trade-off. (D86)
- **FT-MIS-036** Modules shall be bought and sold only while docked, through Comms; a bought module shall be fitted at once, and buying for a full slot shall sell the old module in the same trade, shown on the offer card. (D86, plan review STN-9)
- **FT-MIS-037** On Easy, a first-time crew shall survive at least 3 encounters and at least 60 % of the run's encounters in most runs (proposed target, owner-tunable; judged by the owner from the bot batch). (D31, D236, D252, plan review UX-7)
- **FT-MIS-038** The debrief shall log, per station, the time from run start to the first use of each of its core actions, listed per station in its StationDef. (D35, D232, plan review UX-7)
- **FT-MIS-039** A "Shakedown" training scenario shall have no director and no elimination, a drone target, and staged ship-computer lines with subtitles that teach each station's core actions, then one pair per step; each station follows its own track, and a step on a control without a sim command advances on Next; the crew shall cover every station to reach the pair steps, and the Captain's track counts only while a Captain is seated. (D100, D235, D240, D247) A player may also take one station's lesson alone, from Training in the main menu: the station plays its whole track while bots act at the other crew stations and a scripted partner plays the other half of the pair steps; the crew-coverage rule applies to the full crew drill only, and a web server runs a solo lesson only while it has no other crew (D303, D306).
- **FT-MIS-040** In co-op sessions only, the host shall be able to pause the simulation, reusing the coverage-pause path (FT-NET-034); when the host has not returned within the reconnect grace, the host pause shall lift by itself, the coverage-pause rules still applying. (D100, D246)
- **FT-MIS-041** Every hostile encounter definition shall include at least one Comms beat (hail, taunt, surrender offer, distress call), checked by the scenario lint; travel legs may carry destructible debris on the route that Weapons can shoot as point defence. (plan review STN-8, UX-6, D234)
- **FT-MIS-042** Contract target flags (disable, protect) shall be held in faction KNOW, so allied Weapons see them under the P9 toggle. (D82, plan review COOP-9)
