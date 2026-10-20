class_name S4Snapshot
extends RefCounted
## Entity-level snapshot deltas. A state is {entity_id: {field: value}}; a delta
## holds the changed fields of each entity and the ids that left. Values are
## replaced, never mutated in place, so shallow copies are safe.


static func delta(base: Dictionary, current: Dictionary) -> Dictionary:
	var changed: Dictionary = {}
	for id: Variant in current:
		var cur: Dictionary = current[id]
		if not base.has(id):
			changed[id] = cur
			continue
		var old: Dictionary = base[id]
		var fields: Dictionary = {}
		for key: Variant in cur:
			if not old.has(key) or old[key] != cur[key]:
				fields[key] = cur[key]
		if not fields.is_empty():
			changed[id] = fields
	var gone: Array = []
	for id: Variant in base:
		if not current.has(id):
			gone.append(id)
	return {"set": changed, "gone": gone}


static func apply(base: Dictionary, change: Dictionary) -> Dictionary:
	var out: Dictionary = base.duplicate()
	var changed: Dictionary = change["set"]
	for id: Variant in changed:
		var fields: Dictionary = changed[id]
		var entity: Dictionary = (out[id] as Dictionary).duplicate() if out.has(id) else {}
		entity.merge(fields, true)
		out[id] = entity
	for id: Variant in change["gone"]:
		out.erase(id)
	return out
