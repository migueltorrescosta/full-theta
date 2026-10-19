class_name DamageTable
extends SimTable
## Hull, subsystem health, spare parts and repair crews (T033, FT-SIM-020, FT-SIM-021,
## FT-SIM-024). Each ship owns a contiguous block of rows: first its hull row (part
## &"hull"), then one row per subsystem in ShipDef.subsystems order. The hull row's
## health is the hull (J) and its spare_parts is the ship's stock; subsystem rows keep
## spare_parts at 0. Repair crews are numbered 0..repair_crews-1 and identified by bit
## index: crews[row] on a subsystem row is the mask of crews working there (always 0 on
## the hull row); a crew in no mask is idle.

const HULL: StringName = &"hull"
## Crews are bits of a 32-bit mask (ShipDef.validate caps repair_crews at this).
const MAX_CREWS: int = 31

## &"hull" on the hull row, the subsystem id on subsystem rows.
var part_ids: Array[StringName] = []
## Hull or subsystem health (J), 0..its maximum in the definition.
var health: PackedFloat64Array = PackedFloat64Array()
## Spare parts in stock (count) on the hull row; 0 on subsystem rows.
var spare_parts: PackedInt32Array = PackedInt32Array()
## Mask of repair crews assigned to a subsystem row (bit c = crew c).
var crews: PackedInt32Array = PackedInt32Array()

## Derived index, not state: first (hull) row by ship id. Rebuilt when stale.
var _first: PackedInt32Array = PackedInt32Array()


func add_ship(ship_id: int, faction: int, def: ShipDef) -> void:
	var r: int = add_key(ship_id, faction)
	_index(ship_id, r)
	part_ids.append(HULL)
	health.append(def.hull_max)
	spare_parts.append(def.spare_parts)
	crews.append(0)
	for s: SubsystemDef in def.subsystems:
		add_key(ship_id, faction)
		part_ids.append(s.id)
		health.append(s.health_max)
		spare_parts.append(0)
		crews.append(0)


func columns() -> Array:
	return (
		super()
		+ [
			["part_ids", part_ids],
			["health", health],
			["spare_parts", spare_parts],
			["crews", crews],
		]
	)


## The ship's hull row, or -1.
func hull_row(ship_id: int) -> int:
	if ship_id >= 0 and ship_id < _first.size():
		var r: int = _first[ship_id]
		if r >= 0 and r < size() and ship_ids[r] == ship_id:
			return r
	var found: int = row_of(ship_id)
	if found >= 0:
		_index(ship_id, found)
	return found


## Row of the ship's subsystem with that index in ShipDef.subsystems, or -1.
func subsystem_row(ship_id: int, index: int) -> int:
	var h: int = hull_row(ship_id)
	if h < 0 or index < 0:
		return -1
	var r: int = h + 1 + index
	if r >= size() or ship_ids[r] != ship_id:
		return -1
	return r


## Row of the ship's subsystem with that id, or -1 (never the hull row).
func find_subsystem(ship_id: int, subsystem_id: StringName) -> int:
	var h: int = hull_row(ship_id)
	if h < 0 or subsystem_id == HULL:
		return -1
	var r: int = h + 1
	while r < size() and ship_ids[r] == ship_id:
		if part_ids[r] == subsystem_id:
			return r
		r += 1
	return -1


## Mask of every crew assigned anywhere on the ship.
func busy_crews(ship_id: int) -> int:
	var mask: int = 0
	var h: int = hull_row(ship_id)
	if h < 0:
		return 0
	var r: int = h + 1
	while r < size() and ship_ids[r] == ship_id:
		mask |= crews[r]
		r += 1
	return mask


func _index(ship_id: int, row: int) -> void:
	while _first.size() <= ship_id:
		_first.append(-1)
	_first[ship_id] = row
