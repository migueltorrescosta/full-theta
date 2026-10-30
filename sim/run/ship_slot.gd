class_name ShipSlot
extends RefCounted
## One crewable ship of a session built from the multi-ship lobby (#11, FT-GEN-001, owner
## M4-Q3, 2026-10-28): its name, faction and team. RunSetup.build() spawns one ship per
## slot, in slot order, so the i-th slot is ship id i; the server drops the slots nobody
## picked before it builds (M4-Q3). Allies share a faction (FT-ARC-018); SessionRules
## assigns factions from teams (faction_for_team). Pure value.

## Shown in the lobby, on the scoreboard and in callouts (UTF-8, at most
## NetProtocol.MAX_NAME_BYTES).
var name: String = ""
var faction: int = M1Encounter.PLAYER_FACTION
## The side the ship plays on: 0 in co-op, the team in TEAMS and HOLDOUT, the slot index in
## RACE and LAST_STANDING (every ship its own side).
var team: int = 0


static func of(ship_name: String, ship_faction: int, ship_team: int) -> ShipSlot:
	var s: ShipSlot = ShipSlot.new()
	s.name = ship_name
	s.faction = ship_faction
	s.team = ship_team
	return s


func to_dict() -> Dictionary:
	return {"name": name, "faction": faction, "team": team}
