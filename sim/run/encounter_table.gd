class_name EncounterTable
extends SimTable
## The run's encounters (E07, FT-MIS-025, FT-MIS-027, D231): one row per encounter, added by
## BeginEncounterCommand and never removed, so an encounter's id is its row. The key is the
## first crewed ship of the encounter and its faction (FT-ARC-012).
## It lives in SimWorld like every table, so the state hash covers it and a replay of the
## command log rebuilds it. A ship reset leaves it alone: encounters are run history.

## PENDING: opened, waiting for the ship to arrive at the site or for the arrival timeout.
## ACTIVE: running. WON, LOST, FLED and ABANDONED end it.
enum Result { PENDING, ACTIVE, WON, LOST, FLED, ABANDONED }

## Most ship bits a mask holds (an int64 mask; crewed ships take the first ids).
const MAX_SHIP_BITS: int = 62

## Index of the scenario in the world's scenario list (SimWorld.scenario_ids).
var scenario_ix: PackedInt32Array = PackedInt32Array()
## Site id the encounter happens at, or -1.
var site: PackedInt32Array = PackedInt32Array()
## Bit per crewed ship id in the encounter (ids below MAX_SHIP_BITS).
var ships_mask: PackedInt64Array = PackedInt64Array()
var result: PackedByteArray = PackedByteArray()
## Tick it was opened, the tick it turned ACTIVE (-1 while PENDING) and the tick it ended (-1).
var open_tick: PackedInt32Array = PackedInt32Array()
var start_tick: PackedInt32Array = PackedInt32Array()
var end_tick: PackedInt32Array = PackedInt32Array()
## Threat cost the director charged (points).
var cost: PackedInt32Array = PackedInt32Array()
## Ships destroyed or abandoned in the encounter, and ships that fled it (bits like ships_mask).
var losses_mask: PackedInt64Array = PackedInt64Array()
var fled_mask: PackedInt64Array = PackedInt64Array()


func add_ship(_ship_id: int, _faction: int, _def: ShipDef) -> void:
	pass


## Adds a PENDING encounter keyed by its first crewed ship; returns its id.
func add_encounter(
	first_ship: int, faction: int, scenario: int, at_site: int, mask: int, threat: int, tick: int
) -> int:
	var row: int = add_key(first_ship, faction)
	scenario_ix.append(scenario)
	site.append(at_site)
	ships_mask.append(mask)
	result.append(Result.PENDING)
	open_tick.append(tick)
	start_tick.append(-1)
	end_tick.append(-1)
	cost.append(threat)
	losses_mask.append(0)
	fled_mask.append(0)
	return row


## Whether the encounter is PENDING or ACTIVE.
func is_open(id: int) -> bool:
	return id >= 0 and id < size() and result[id] <= Result.ACTIVE


## Whether the ship's bit is in the mask.
static func has_bit(mask: int, ship: int) -> bool:
	return ship >= 0 and ship < MAX_SHIP_BITS and (mask >> ship) & 1 == 1


func columns() -> Array:
	return (
		super()
		+ [
			["scenario_ix", scenario_ix],
			["site", site],
			["ships_mask", ships_mask],
			["result", result],
			["open_tick", open_tick],
			["start_tick", start_tick],
			["end_tick", end_tick],
			["cost", cost],
			["losses_mask", losses_mask],
			["fled_mask", fled_mask],
		]
	)


## Encounters are run history, like cards: a ship reset leaves them alone.
func reset_ship(_ship_id: int, _def: ShipDef) -> void:
	pass
