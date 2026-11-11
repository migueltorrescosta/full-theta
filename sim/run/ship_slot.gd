class_name ShipSlot
extends RefCounted
## One crewable ship of a session built from the multi-ship lobby (#11, FT-GEN-001, owner
## M4-Q3, 2026-10-28): its name and its lobby team. RunSetup.build() spawns one ship per
## slot, in slot order, so the i-th slot is ship id i, of the faction SessionRules.faction_for
## gives the slot: the one place a team becomes a faction (B5); past it the sim knows only
## factions. Allies share a faction (FT-ARC-018). The server drops the slots nobody picked
## before it builds (M4-Q3). Pure value.

## Shown in the lobby, on the scoreboard and in callouts (UTF-8, at most
## NetProtocol.MAX_NAME_BYTES).
var name: String = ""
## The lobby team: 0 in co-op, the team in TEAMS and HOLDOUT, the slot index in RACE and
## LAST_STANDING (every ship its own side).
var team: int = 0


static func of(ship_name: String, ship_team: int) -> ShipSlot:
	var s: ShipSlot = ShipSlot.new()
	s.name = ship_name
	s.team = ship_team
	return s
