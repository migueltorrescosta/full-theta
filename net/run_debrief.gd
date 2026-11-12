class_name RunDebrief
extends RefCounted
## The end-of-run record of a ship (FT-MIS-006, FT-MIS-010, FT-MIS-038, FT-PAIR-013, D31,
## D35, D232): what the director decided and why, how each encounter ended with ship losses,
## fled encounters and a crippled ship's limp home (gp-09) told apart, when each station
## first used each core action, and the cooperative events per pair, and the card's three
## highlights (RunHighlights, ux-20). Built
## on the server from the world and the sessions' own
## counters; sent as the `debrief` notify with `ship_outcome`, written to the server log and
## read by the bot batch.

## The highlights the server kept (NetRunReset), or null: none in the record.
var highlights: RunHighlights = null

var _world: SimWorld
var _decisions: Array
var _coop: CoopEvents
var _first_use: FirstUse


## `decisions` are the director's DirectorDecision objects.
func _init(world: SimWorld, decisions: Array, coop: CoopEvents, first_use: FirstUse) -> void:
	_world = world
	_decisions = decisions
	_coop = coop
	_first_use = first_use


## The record for one crewed ship:
## {time, result "win|loss|abandoned|open", encounters: [{id, scenario, site, site_name_key,
## result, lost, fled, limped, time}], losses, fled, decisions, first_use, coop, highlights}
## (highlights: RunHighlights.for_ship, {} without them).
func for_ship(ship: int) -> Dictionary:
	var rows: Array = []
	var losses: int = 0
	var fled: int = 0
	var t: EncounterTable = _world.encounters
	for id: int in t.size():
		if not EncounterTable.has_bit(t.ships_mask[id], ship):
			continue
		var row: Dictionary = _row(id, ship)
		losses += 1 if row["lost"] else 0
		fled += 1 if row["fled"] else 0
		rows.append(row)
	var coop: Array = _coop.debrief()
	var destroyed: bool = DamageSystem.hull_fraction(_world, ship) <= 0.0
	return {
		"ship": ship,
		"time": _world.tick * SimWorld.DT,
		"result": _result(ship),
		"encounters": rows,
		"losses": losses,
		"fled": fled,
		"decisions": _decisions_of(ship),
		"first_use": _first_use.for_ship(ship),
		"coop": coop,
		"highlights": highlights.for_ship(ship, coop, destroyed) if highlights != null else {},
	}


func _row(id: int, ship: int) -> Dictionary:
	var t: EncounterTable = _world.encounters
	var ix: int = t.scenario_ix[id]
	var site: int = t.site[id]
	var end: int = t.end_tick[id] if t.end_tick[id] >= 0 else _world.tick
	var start: int = t.start_tick[id] if t.start_tick[id] >= 0 else t.open_tick[id]
	return {
		"id": id,
		"scenario": _world.scenario_ids[ix] if ix >= 0 and ix < _world.scenario_ids.size() else "",
		"site": site,
		"site_name_key": _world.sites.name_key_of(site),
		"result": EncounterTable.Result.keys()[t.result[id]].to_lower(),
		"lost": EncounterTable.has_bit(t.losses_mask[id], ship),
		"fled": EncounterTable.has_bit(t.fled_mask[id], ship),
		"limped": EncounterTable.has_bit(t.limped_mask[id], ship),
		"time": (end - start) * SimWorld.DT,
	}


## The decisions about this ship, and the ones about no ship (a site opened on schedule).
func _decisions_of(ship: int) -> Array:
	var out: Array = []
	for d: Variant in _decisions:
		var dict: Dictionary = (d as DirectorDecision).to_dict()
		if dict["ship"] == ship or dict["ship"] < 0:
			out.append(dict)
	return out


func _result(ship: int) -> String:
	match _world.ships.ship_outcome[ship]:
		ShipStateTable.ShipOutcome.WIN:
			return "win"
		ShipStateTable.ShipOutcome.LOSS:
			return (
				"abandoned"
				if _world.ships.status[ship] == ShipStateTable.Status.ABANDONED
				else "loss"
			)
	return "open"
