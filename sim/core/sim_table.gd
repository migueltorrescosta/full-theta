class_name SimTable
extends RefCounted
## Base of every simulation state container: each row is keyed by a ship id and that
## ship's faction (FT-ARC-012, FT-M1-014). Columns are packed arrays (S6 layout),
## appended in spawn order, so rows of per-ship tables follow ship id order
## (FT-ARC-009). Tables with several rows per ship (mounts, subsystems) or per faction
## (knowledge) keep the same two key columns.

var ship_ids: PackedInt32Array = PackedInt32Array()
var factions: PackedInt32Array = PackedInt32Array()


func size() -> int:
	return ship_ids.size()


## Appends the key of a new row; subclasses append their own columns after it.
func add_key(ship_id: int, faction: int) -> int:
	ship_ids.append(ship_id)
	factions.append(faction)
	return ship_ids.size() - 1


## First row of the ship, or -1.
func row_of(ship_id: int) -> int:
	return ship_ids.find(ship_id)


## Rows of the ship, in order.
func rows_of(ship_id: int) -> PackedInt32Array:
	var rows: PackedInt32Array = PackedInt32Array()
	for r: int in ship_ids.size():
		if ship_ids[r] == ship_id:
			rows.append(r)
	return rows


## Called by SimWorld.spawn_ship for every table, in table order; per-ship tables
## add their rows from the definition (FT-ARC-020: copies, never the definition).
func add_ship(_ship_id: int, _faction: int, _def: ShipDef) -> void:
	pass


## The state, as ordered [name, value] pairs, for hashing, copies and tests. Each name
## is the property holding the column; subclasses append their columns to the keys.
func columns() -> Array:
	return [["ship_ids", ship_ids], ["factions", factions]]


## Restores the ship's rows to their spawn values from the definition (per-ship run
## reset, FT-MIS-017), leaving other ships' rows alone. Works for tables whose
## add_ship() appends the same rows whatever else is in the table; others override.
func reset_ship(ship_id: int, def: ShipDef) -> void:
	var rows: PackedInt32Array = rows_of(ship_id)
	if rows.is_empty():
		return
	var fresh: SimTable = (get_script() as GDScript).new()
	fresh.add_ship(ship_id, factions[rows[0]], def)
	assert(fresh.size() == rows.size(), "reset_ship: row count changed")
	for col: Array in fresh.columns():
		var name: String = col[0]
		var values: Variant = get(name)
		for i: int in rows.size():
			values[rows[i]] = col[1][i]
		set(name, values)
