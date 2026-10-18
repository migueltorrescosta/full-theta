# Crew, stations and ships: D10–D13 against EE

Sources: decisions.md D10–D13; spec 02, 04, 06, 09; EE at ref/EmptyEpsilon (read only).

## What EE actually does

- **Shared stations are allowed and unarbitrated.** `CrewPositionSelection::onUpdate` (src/menus/shipSelectionScreen.cpp) only labels a button "Weapons [2]" and lists names; nothing blocks a second player. Every command is applied as it arrives (`PlayerInfo::onReceiveClientCommand`, e.g. `CMD_SET_TARGET` overwrites `Target.entity`), so conflicts resolve as last-writer-wins. Both screens show the same replicated state, so the second player sees the change, but there is no ownership, lock or split.
- **One player, several stations.** `CrewPositions` is a 64-bit mask per monitor (src/crewPosition.h); `PlayerInfo::spawnUI` adds one tab per selected position; multi-monitor clients get a mask per `monitor_index`. Any combination is allowed (subject to the ship's `allowed_positions`), not only the curated ones.
- **Curated combos** are just extra positions: Tactical (helm+weapons, no shields), Engineering+ (engineering+shields), Operations (science+relay comms/waypoints, no probes/hacking), Single Pilot (helm+weapons+shields+comms), plus extras (Damage Control, Power Management, Database, Alt Relay, Comms only, Ship's log). Self-destruct entry is mapped from combos back to the base stations.
- **Viewers.** "Main screen" is a crew option per monitor (and "Main screen (split)" alongside a station); unlimited clients may pick it. Main-screen controls are a separate grant. Spectator ("view all"), Cinematic and GM views are whole-map views gated only by the optional GM control code.
- **Multiple ships / PvP.** Any number of `PlayerControl` ships; the ship list shows filled positions per ship. PvP is pure scenario + faction (`scenario_81_pvp.lua`, `scenario_60_captureFlag.lua`, Category: PvP); radar/scan knowledge is per faction (`setScannedByFaction`). No balance or matchmaking support; a GM usually runs it.
- **No player cap.** No max-clients or max-ships constant in EE or SeriousProton; performance is left to the host.
- **Unstaffed = untouched, not off.** Systems keep defaults (`power_level = 1.0` in components/shipsystem.h), beams fire at whatever target was set, shields stay as left. Automation exists only as scenario options (`Coolant.auto_levels`, `auto_repair_per_second`, auto-repair crews), never triggered by staffing.

## D10 Station selection, sharing, viewers

Consequences: EE's last-writer-wins is tolerable because EE stations have few continuous inputs. Ours has manual aiming of several mounts: two people dragging the same aim reticle will fight. Sharing needs an ownership model: per-mount ownership (claim a mount; others see it locked with the owner's name) for Weapons, and per-system ownership or last-writer-wins with a visible "edited by X" cue for Engineering. Helm cannot be meaningfully shared (one stick); allow it but make the second player read-only by default.
Viewers: main-screen viewers cost one snapshot stream each; cheap if the server sends main-screen state at a reduced rate (no station-private data). A spectator "view all" is a cheat in PvP; gate it like EE (host code) or make it per-faction.
Player cap: replication cost scales with clients × replicated entities. A sensible LAN cap is 32 connections per server (6 ships × 6 stations = 36 is already over this if all stations are separate humans, so cap at ~40 seats including viewers, or treat viewers as a cheaper class with their own cap).

## D11 Up to 6 ships, co-op and PvP

Tensions: spec 2/6 says "cooperative" and "one shared spacecraft"; the director (spec 2: no human GM, adaptive director, 20–40 min runs, ship destruction resets the run) is designed per crew. With 6 ships: does destruction of one ship reset everyone? Does the director scale threat per ship or per session? PvP also breaks the pairwise design assumption that asymmetric information is within one crew; it adds per-faction knowledge (scans, comms, probes) everywhere, and the "fallback behaviour" of stations becomes exploitable by an opposing crew.
Milestone 9 asks for one ship and one enemy AI. Multi-ship and PvP should not enter it, but the data model should key everything by ship id and faction from day one (cheap now, expensive later). Balance for PvP needs symmetric ships and a human-free win condition; recommend deferring PvP to after co-op multi-ship.
Network load: 6 ships × full station state is fine on LAN if only station-relevant data goes to each client; the risk is browser (WebSocket, D8) clients, not desktop.

## D12 Unstaffed stations "simply off"

Problem: "off" is ambiguous. If an unstaffed Engineering means zero power, a 2-player crew (Helm + Weapons, the milestone's likely test) has no engines. EE does not switch systems off; it leaves them at default and untouched. Recommend "unstaffed = frozen at safe defaults" (power 100%, no repairs, no scans, no probes, no comms answers), which matches EE and keeps "no automation".
Captain: "never mandatory" is automatically satisfied, since the captain has no systems. Pair mechanics: with 3 players, the pairs involving missing stations simply do not occur; the cooperation failure rule (costs, not unplayable) is met only if defaults are safe.

## D13 Curated combos only

With a curated list, the combos must cover every crew size 1–6 with all six (five systemic) stations reachable, or a small crew loses capabilities entirely (under D12, unstaffed = unused). EE's curation leaves gaps on purpose (Operations has no probes/hacking; Tactical has no shields), which for us would drop the Relay+Science probe loop and the Weapons+Engineering shields loop in 3–4 player crews. Also, D10 lets one player hold several stations as tabs, which is already free combination; "curated only" then means only that curated combos get a merged single screen, while any set can still be held as tabs. Recommend: tabs for any set (EE behaviour) + a few curated merged screens (Tactical, Operations, Single Pilot) designed later; curated must not remove capabilities.

Suggested combo coverage (5 systemic stations + optional Captain):
- 1 player: Single Pilot (helm+weapons+shields+comms) + tabs for rest.
- 2: Helm+Weapons (Tactical) / Engineering+Science+Relay (tabs or Operations+Engineering).
- 3: Tactical / Engineering / Operations.
- 4: Helm / Weapons / Engineering / Operations.
- 5–6: full set, Captain optional.
