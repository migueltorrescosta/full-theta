class_name SimTable
extends RefCounted
## Base of every simulation state container: each row is keyed by a ship id and that
## ship's faction (FT-ARC-012, FT-M1-014). Columns are packed arrays (S6 layout),
## appended in spawn order, so rows of per-ship tables follow ship id order
## (FT-ARC-009). Tables with several rows per ship (mounts, subsystems) or per faction
## (knowledge) keep the same two key columns.

## Ids below this share a key with the id above it: row_key packs two ids into one int.
const KEY_STRIDE: int = 65536

## The column registry (R04-14): every script variable the table declares, base class
## first and then in declaration order, is a state column unless its name starts with `_`
## (a derived index or cache) or not_columns() names it. So declaring a column is the one
## edit that puts it in state_hash(), reset_ship() and SimCopy; its spawn value is still
## appended in add_ship(). Per table script, script -> [all variables, column names],
## filled once under the mutex (any thread may hash or capture a world).
static var _registry: Dictionary = {}
static var _registry_lock: Mutex = Mutex.new()

var owner_ship: PackedInt32Array = PackedInt32Array()
var owner_faction: PackedInt32Array = PackedInt32Array()


## One int for an ordered pair of ids (faction and ship, or faction and faction), the key of
## the derived row indexes and of the world's relation table.
static func row_key(a: int, b: int) -> int:
	return a * KEY_STRIDE + b


func size() -> int:
	return owner_ship.size()


## Appends the key of a new row; subclasses append their own columns after it.
func add_key(ship_id: int, faction: int) -> int:
	owner_ship.append(ship_id)
	owner_faction.append(faction)
	return owner_ship.size() - 1


## First row of the ship, or -1.
func row_of(ship_id: int) -> int:
	return owner_ship.find(ship_id)


## Rows of the ship, in order.
func rows_of(ship_id: int) -> PackedInt32Array:
	var rows: PackedInt32Array = PackedInt32Array()
	for r: int in owner_ship.size():
		if owner_ship[r] == ship_id:
			rows.append(r)
	return rows


## Called by SimWorld.spawn_ship for every table, in table order; per-ship tables
## add their rows from the definition (FT-ARC-020: copies, never the definition).
func add_ship(_ship_id: int, _faction: int, _def: ShipDef) -> void:
	pass


## The state columns, as ordered [name, value] pairs, for hashing, copies and tests: the
## registry's columns, the two key columns first. The order is the hash order (D404).
func columns() -> Array:
	var out: Array = []
	for name: String in _registered()[1]:
		out.append([name, get(name)])
	return out


## Every script variable of the table, columns, derived state and the not_columns() alike
## (SimCopy copies them all), in registry order.
func variables() -> Array[StringName]:
	return _registered()[0]


## Public script variables that are not row columns (run data, flags, derived caches other
## code reads); subclasses that have any override this.
func not_columns() -> Array[StringName]:
	return []


func _registered() -> Array:
	var script: Script = get_script()
	_registry_lock.lock()
	var entry: Array = _registry.get(script, [])
	if entry.is_empty():
		# The list holds one group per script, the table's own first, each after a
		# category entry: reversed, the base class's variables come first.
		var groups: Array = []
		for p: Dictionary in script.get_script_property_list():
			if p["usage"] & PROPERTY_USAGE_CATEGORY:
				groups.push_front([])
			elif p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
				groups[0].append(StringName(p["name"]))
		var vars: Array[StringName] = []
		var cols: Array[String] = []
		var skip: Array[StringName] = not_columns()
		for group: Array in groups:
			for name: StringName in group:
				vars.append(name)
				if not String(name).begins_with("_") and not skip.has(name):
					cols.append(String(name))
		entry = [vars, cols]
		_registry[script] = entry
	_registry_lock.unlock()
	return entry


## Restores the ship's rows to their spawn values from the definition (per-ship run
## reset, FT-MIS-017), leaving other ships' rows alone. Works for tables whose
## add_ship() appends the same rows whatever else is in the table; others override.
func reset_ship(ship_id: int, def: ShipDef) -> void:
	var rows: PackedInt32Array = rows_of(ship_id)
	if rows.is_empty():
		return
	var fresh: SimTable = (get_script() as GDScript).new()
	fresh.add_ship(ship_id, owner_faction[rows[0]], def)
	assert(fresh.size() == rows.size(), "reset_ship: row count changed")
	for col: Array in fresh.columns():
		var name: String = col[0]
		var values: Variant = get(name)
		for i: int in rows.size():
			values[rows[i]] = col[1][i]
		set(name, values)
