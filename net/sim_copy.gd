class_name SimCopy
extends RefCounted
## A detached copy of a SimWorld's state for the snapshot encoder on the net thread
## (FT-NET-040, D111), made in two halves so the sim thread does as little as possible:
## capture() on the sim thread takes the state, and restore() on the net thread builds
## a SimWorld from it, which the encoder reads through the usual table API (Kinematics
## helpers, KnowledgeSystem.callsign) while the sim moves on.
##
## capture() duplicates every script variable of every table: the columns() state and
## the derived indexes and caches (DamageTable._first, _eff_health and _eff;
## PowerTable._env_in and _env), so the capture shares nothing mutable with the live
## world. Packed arrays copy on write, so duplicating them costs no element
## copies until the sim writes; the other containers hold only values, so a shallow
## duplicate is enough. KnowledgeTable._rows is left out (a Dictionary is the slowest
## variable to duplicate): restore() rebuilds it from the key columns. Definitions are
## shared: they are read-only (FT-ARC-020). RNG states are copied too, so the copy's
## state_hash() equals the world's when no command is queued. The copy has no queued
## commands, events or command log; don't step it.

## Leading entries of a capture, before the tables.
enum { SEED, BUILD, TICK, DEFS, RNG, RELATIONS, SCIENCE_DEF, HAZARDS, STORY_DATA, HEADER }

## Table script -> Array[StringName] of its script variables but KnowledgeTable._rows
## (get_property_list is slow, so each class is listed once). Main thread only; each
## capture carries the lists restore() needs.
static var _vars: Dictionary = {}


## A copy of the world's state on its own (capture() then restore()).
static func of(world: SimWorld) -> SimWorld:
	return restore(capture(world))


## Takes the world's state (sim thread): the header entries, then for each table its
## variable names and one value per name. Hand it to restore() once.
static func capture(world: SimWorld) -> Array:
	var out: Array = [
		world.seed_value,
		world.build_id,
		world.tick,
		world.defs.duplicate(),
		world.rng.states(),
		(world.get("_relations") as Dictionary).duplicate(),
		world.science_def,
		world.hazards.duplicate(),
		# The read-only data the COMMS section reads (shared, never changed).
		[
			world.base_defs.duplicate(),
			world.conversations,
			world.hail_conversations,
			world.markets,
			world.site_markets,
			world.module_defs,
			world.rep_dists,
		],
	]
	for table: SimTable in world.tables():
		var names: Array[StringName] = _vars_of(table)
		out.append(names)
		for name: StringName in names:
			var value: Variant = table.get(name)
			var t: int = typeof(value)
			if t == TYPE_ARRAY or t == TYPE_DICTIONARY or t >= TYPE_PACKED_BYTE_ARRAY:
				value = value.duplicate()
			out.append(value)
	return out


## Builds the SimWorld a capture describes (any thread). The world takes the capture's
## containers as they are.
static func restore(state: Array) -> SimWorld:
	var copy: SimWorld = SimWorld.new(state[SEED], state[BUILD])
	copy.tick = state[TICK]
	copy.defs = state[DEFS]
	for pair: Array in state[RNG]:
		copy.rng.stream(pair[0]).state = pair[1]
	copy.set("_relations", state[RELATIONS])
	copy.science_def = state[SCIENCE_DEF]
	copy.hazards = state[HAZARDS]
	var data: Array = state[STORY_DATA]
	copy.base_defs.assign(data[0])
	copy.conversations = data[1]
	copy.hail_conversations = data[2]
	copy.markets = data[3]
	copy.site_markets = data[4]
	copy.module_defs = data[5]
	copy.rep_dists = data[6]
	var k: int = HEADER
	for table: SimTable in copy.tables():
		var names: Array[StringName] = state[k]
		k += 1
		for name: StringName in names:
			table.set(name, state[k])
			k += 1
	_index_knowledge(copy.knowledge)
	return copy


## Rebuilds KnowledgeTable._rows, its row by faction * 65536 + contact id (row_for).
static func _index_knowledge(table: KnowledgeTable) -> void:
	var rows: Dictionary[int, int] = {}
	for r: int in table.size():
		rows[table.factions[r] * 65536 + table.ship_ids[r]] = r
	table.set("_rows", rows)


static func _vars_of(table: SimTable) -> Array[StringName]:
	var script: Script = table.get_script()
	if not _vars.has(script):
		var names: Array[StringName] = []
		for p: Dictionary in table.get_property_list():
			if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
				names.append(StringName(p["name"]))
		if table is KnowledgeTable:
			names.erase(&"_rows")
		_vars[script] = names
	return _vars[script]
