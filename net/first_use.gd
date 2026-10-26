class_name FirstUse
extends RefCounted
## The first time each station used each of its core actions in a run (FT-MIS-038, D35,
## D232): the debrief lists, per station, the seconds from the run's start to that first
## use, or -1 for an action never used. The core actions are data, StationDef.core_actions
## ("action=source", see StationDef). Every one is either an accepted crew command, fed by
## ServerSession through NetCoop.on_command, or a net-side crew op, Relay's mark placed and
## route added, fed by NetCrewState; so no client reports an intent (D235).

## Ship -> "station.action" -> tick of the first use.
var _first: Dictionary[int, Dictionary] = {}
## Station -> [{action, kinds: PackedStringArray, field, op}], parsed once from the defs.
var _table: Dictionary = {}


func _init() -> void:
	for station: String in StationViews.CREW:
		var rows: Array[Dictionary] = []
		var d: StationDef = StationViews.def(station)
		for entry: String in d.core_actions:
			rows.append(_parse(entry))
		_table[station] = rows


## An accepted crew command of `ship` at `tick`. The station is the one the command kind
## belongs to; a command no core action names counts nothing.
func on_command(ship: int, c: SimCommand, tick: int) -> void:
	var station: String = StationViews.station_of_command(c.kind())
	for row: Dictionary in _table.get(station, []):
		if row["op"] == "" and (row["kinds"] as PackedStringArray).has(String(c.kind())):
			var field: String = row["field"]
			if field == "" or bool(c.get(field)):
				_mark(ship, station, row["action"], tick)


## A net-side crew op of `ship` at `tick` ("mark_place", "route_add") by `station`.
func on_crew_op(ship: int, station: String, op: String, tick: int) -> void:
	for row: Dictionary in _table.get(station, []):
		if row["op"] == op:
			_mark(ship, station, row["action"], tick)


## {station: {action: seconds or -1}} for every core action of every station, the seconds
## from tick 0.
func for_ship(ship: int) -> Dictionary:
	var out: Dictionary = {}
	var seen: Dictionary = _first.get(ship, {})
	for station: String in StationViews.CREW:
		var actions: Dictionary = {}
		for row: Dictionary in _table[station]:
			var key: String = "%s.%s" % [station, row["action"]]
			actions[row["action"]] = seen[key] * SimWorld.DT if seen.has(key) else -1.0
		out[station] = actions
	return out


func reset() -> void:
	_first.clear()


func _mark(ship: int, station: String, action: String, tick: int) -> void:
	var seen: Dictionary = _first.get_or_add(ship, {})
	var key: String = "%s.%s" % [station, action]
	if not seen.has(key):
		seen[key] = tick


## "action=a|b.field" or "action=op:name" as {action, kinds, field, op}.
static func _parse(entry: String) -> Dictionary:
	var action: String = entry.get_slice("=", 0)
	var source: String = entry.get_slice("=", 1)
	if source.begins_with("op:"):
		return {"action": action, "kinds": PackedStringArray(), "field": "", "op": source.substr(3)}
	var kinds: PackedStringArray = PackedStringArray()
	var field: String = ""
	for part: String in source.split("|"):
		kinds.append(part.get_slice(".", 0))
		if part.contains("."):
			field = part.get_slice(".", 1)
	return {"action": action, "kinds": kinds, "field": field, "op": ""}
