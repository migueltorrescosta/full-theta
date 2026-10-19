# 8. Missions, director, progression and economy

## 8.1 Runs and encounters

A run is about 5 encounters in 20–40 minutes (D31, v0.3 §2). Each scenario has a single global open 3D map; there are no per-encounter maps and no sector map (D29, D77). An encounter is a self-contained situation (enemy wave, rescue, derelict, negotiation...) that the director places or activates at a site on that map, with its own triggers and outcome (D77). The scenario seeds some known sites at start; the director spawns more over time within its budget, and each spawn is logged for the debrief (D80). Ships move between named sites by impulse flight and the jump drive; positions are site-local, and a jump changes the site (D77, D98, FT-SIM-035, §6). Initial scenarios: enemy waves, rescue and the Shakedown training scenario (D100); later exploration, branching encounters and negotiations, all built from reusable components (v0.3 §7).

## 8.2 Director

The director picks and parameterises scenario components by pacing and threat budget. It changes which events happen, never the rules (v0.3 §7). Every decision is logged with its reason and shown in the end-of-run debrief (D35). One difficulty (Easy, Normal, Hard) is chosen per session before start; it sizes the director's threat budget, held separately per ship, and presets the data-shortcut toggles (§7.2); no hidden stats (D33, D14, D81, D84). Death risk target: 5–10 % chance of losing the ship per encounter for an average crew, about 23–41 % per 5-encounter run, tuned with headless bot batches and checked in playtests (D31, plan review CLASH-9).

## 8.3 Outcomes

Per-ship elimination: a destroyed ship's crew is out and its run progress resets; other ships carry on (D30). Each scenario defines what an eliminated crew does; by default its players become viewers of a surviving friendly ship's main screen, or return to the lobby with a live scoreboard when none survives (D79, D91). Co-op wins on the final run objective (D30). PvP comes as three distinct scenario types (D78): a race through the same run, won by the first ship to complete the final objective; last ship standing; and two-faction teams, with co-op inside each faction (D82). A crew may flee an encounter at a cost or abandon the run (D36).

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

- **FT-MIS-001** A run shall consist of about 5 encounters. (D31)
- ~~**FT-MIS-002**~~ Removed (D77): superseded by FT-MIS-024 to FT-MIS-026.
- **FT-MIS-003** The first scenarios shall include enemy waves and a rescue mission. (v0.3 §7)
- **FT-MIS-004** Missions shall offer consequential choices and clear outcomes. (v0.3 §7)
- **FT-MIS-005** The director shall change only which events occur and their parameters, never simulation rules or stats. (v0.3 §7)
- **FT-MIS-006** Every director decision shall be logged with its reason and shown in the end-of-run debrief. (D35)
- ~~**FT-MIS-007**~~ Removed (D81, D84): superseded by FT-MIS-028 and FT-MIS-029.
- **FT-MIS-008** Difficulty shall never change hidden stats. (D33)
- **FT-MIS-009** Encounter budgets shall be tuned so an average crew loses the ship in 5–10 % of encounters, measured by headless batches of scripted average-crew bots over at least 200 encounters and checked in playtests. (D31, plan review CLASH-9)
- **FT-MIS-010** The debrief shall report per-encounter ship losses, with fled encounters reported separately, so the death-risk target can be measured. (D31, D35, plan review CLASH-9)
- **FT-MIS-011** A destroyed ship's crew shall be out of the run, and that ship's run progress shall reset. (D30)
- **FT-MIS-012** Other ships shall continue after one ship is destroyed. (D30)
- **FT-MIS-013** A co-op session shall be won by completing the final run objective. (D30)
- **FT-MIS-014** A PvP session shall be won by the condition of its mode. (D30)
- **FT-MIS-015** A crew shall be able to flee an encounter at a data-defined cost. (D36)
- **FT-MIS-016** A crew shall be able to abandon the run. (D36)
- **FT-MIS-017** Run state shall be one object owned by the simulation; resetting it shall restore definitions exactly. (D30, D32)
- **FT-MIS-018** The economy shall track credits, ammunition by type, propellant, spare parts, probes and reputation per faction. (D34, D27, D56)
- **FT-MIS-019** Reputation changes shall be drawn from seeded, data-defined distributions specific to each interaction type. (D34)
- **FT-MIS-020** Comms shall show the range of a reputation change where the data marks it visible. (D34)
- **FT-MIS-021** Players shall earn credits, salvage, repairs and upgrades during a run. (v0.3 §7)
- **FT-MIS-022** Upgrades shall create distinct ship builds. (v0.3 §7)
- **FT-MIS-023** In multi-ship sessions, director, balance and run-reset rules shall be keyed per ship and faction. (D21)
- **FT-MIS-024** Each scenario shall take place on a single global open 3D map, with no per-encounter maps and no sector map. (D29, D77)
- **FT-MIS-025** An encounter shall be a self-contained situation with its own triggers and outcome, placed or activated by the director at a site on the scenario map. (D77)
- **FT-MIS-026** Ships shall move between named sites by impulse flight and the jump drive, with site-local positions (FT-SIM-035, §6). (D29, D77, D98)
- **FT-MIS-027** A scenario shall seed some known sites at start; the director shall spawn further sites over time within its budget and log each spawn for the debrief. (D35, D80)
- **FT-MIS-028** One difficulty (Easy, Normal or Hard) shall be chosen per session in the lobby before start; it shall size the director's threat budget and preset the data-shortcut toggles; changing single toggles shall keep the chosen difficulty's threat budget and show the preset as '<Preset> (custom)'. (D33, D81, D84, D92)
- **FT-MIS-029** The director shall hold a separate threat budget for each ship, sized by the session difficulty. (D81)
- **FT-MIS-030** Each scenario shall define what an eliminated crew does; by default its players shall become viewers of a surviving friendly ship's main screen, or, when no friendly ship survives, return to the lobby with a live scoreboard. (D79, D91)
- **FT-MIS-031** PvP shall be offered as three distinct scenario types: race the same run, last ship standing, and two-faction teams. (D78)
- **FT-MIS-032** A race scenario shall be won by the first ship to complete the final run objective; ship-to-ship combat stays allowed. (D37, D78)
- **FT-MIS-033** A last-ship-standing scenario shall be won by the last ship not destroyed. (D78)
- **FT-MIS-034** In a two-faction team scenario, the ships of each team shall share one faction and cooperate; the scenario shall define the winning condition per team. (D78, D82)
- **FT-MIS-035** Upgrades shall be modules fitted to a ship's slots, each defined in data with a trade-off. (D86)
- **FT-MIS-036** Modules shall be bought and sold only while docked, through Comms; a bought module shall be fitted at once, and buying for a full slot shall sell the old module in the same trade, shown on the offer card. (D86, plan review STN-9)
- **FT-MIS-037** On Easy, a first-time crew shall survive at least 3 of 5 encounters in most runs (proposed target, owner-tunable). (D31, plan review UX-7)
- **FT-MIS-038** The debrief shall log, per station, the time from run start to the first use of each of its core actions. (D35, plan review UX-7)
- **FT-MIS-039** A "Shakedown" training scenario shall have no director and no elimination, a drone target, and staged ship-computer lines with subtitles that teach each station's core actions, then one pair per step. (D100)
- **FT-MIS-040** In co-op sessions only, the host shall be able to pause the simulation, reusing the coverage-pause path (FT-NET-034). (D100)
- **FT-MIS-041** Every hostile encounter definition shall include at least one Comms beat (hail, taunt, surrender offer, distress call), checked by the scenario lint; travel legs may carry hazards that point-defence can engage. (plan review STN-8, UX-6)
- **FT-MIS-042** Contract target flags (disable, protect) shall be held in faction KNOW, so allied Weapons see them under the P9 toggle. (D82, plan review COOP-9)
