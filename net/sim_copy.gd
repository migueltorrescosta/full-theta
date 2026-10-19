class_name SimCopy
extends RefCounted
## A detached copy of a SimWorld's state for the snapshot encoder on the net thread
## (FT-NET-040, D111): the sim tick only hands the copy over, and the encoder reads it
## through the usual table API (Kinematics helpers, KnowledgeSystem.callsign) while the
## sim moves on. Every script variable of every table is duplicated: the columns()
## state and the derived indexes (DamageTable._first, KnowledgeTable._rows), so the copy
## shares nothing mutable with the live world. Packed arrays copy on write, so this is
## cheap until the sim writes. Definitions are shared: they are read-only (FT-ARC-020).
## RNG states are copied too, so the copy's state_hash() equals the world's when no
## command is queued. The copy has no queued commands, events or command log; don't
## step it.


static func of(world: SimWorld) -> SimWorld:
	var copy: SimWorld = SimWorld.new(world.seed_value, world.build_id, world.kin.period)
	copy.tick = world.tick
	copy.defs = world.defs.duplicate()
	for pair: Array in world.rng.states():
		copy.rng.stream(pair[0]).state = pair[1]
	copy.set("_relations", (world.get("_relations") as Dictionary).duplicate())
	var src: Array[SimTable] = world.tables()
	var dst: Array[SimTable] = copy.tables()
	for i: int in src.size():
		for p: Dictionary in src[i].get_property_list():
			if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
				var value: Variant = src[i].get(p["name"])
				if value is Array or value is Dictionary or _is_packed(value):
					value = value.duplicate()
				dst[i].set(p["name"], value)
	return copy


static func _is_packed(value: Variant) -> bool:
	var t: int = typeof(value)
	return t >= TYPE_PACKED_BYTE_ARRAY and t <= TYPE_PACKED_VECTOR4_ARRAY
