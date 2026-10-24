class_name Bindings
extends RefCounted
## The player's bindings: IntentTable's defaults plus this client's rebinds per intent
## and device (FT-STN-007) and the hold intents switched to toggles (FT-STN-014).
## Persisted by ClientSettings through to_dict()/from_dict(); `changed` fires after
## every edit so the Controls tab regenerates (FT-STN-011).

signal changed

## id -> {"kbm": PackedStringArray, "pad": PackedStringArray}: only the devices the
## player rebound.
var overrides: Dictionary = {}
## Hold intents the player switched to a toggle: id -> true.
var toggles: Dictionary = {}


## The bindings of `id` on `device` (IntentTable.KBM or PAD): the override, else the
## table's defaults.
func bindings(id: String, device: String) -> PackedStringArray:
	var o: Dictionary = overrides.get(id, {})
	if o.has(device):
		return PackedStringArray(o[device])
	return IntentTable.defaults(id, device)


## Replaces the bindings of `id` on `device`; an empty list unbinds it there.
func rebind(id: String, device: String, list: PackedStringArray) -> void:
	if not IntentTable.has(id):
		return
	var o: Dictionary = overrides.get_or_add(id, {})
	o[device] = PackedStringArray(list)
	changed.emit()


## Back to the table's defaults: one intent, or every intent with id "".
func reset(id: String = "") -> void:
	if id == "":
		overrides.clear()
		toggles.clear()
	else:
		overrides.erase(id)
		toggles.erase(id)
	changed.emit()


## Switches a hold intent between hold and toggle (FT-STN-014); ignored for others.
func set_toggle(id: String, on: bool) -> void:
	if IntentTable.row(id).get("kind", "") != IntentTable.HOLD:
		return
	if on:
		toggles[id] = true
	else:
		toggles.erase(id)
	changed.emit()


func is_toggle(id: String) -> bool:
	return toggles.has(id)


## The intents bound to `binding` on `device` (conflict display in Settings).
func intents_bound_to(binding: String, device: String) -> Array[String]:
	var out: Array[String] = []
	for r: Dictionary in IntentTable.INTENTS:
		if binding in bindings(r["id"], device):
			out.append(r["id"])
	return out


## Plain data for ClientSettings: {"overrides": {id: {device: [..]}}, "toggles": [ids]}.
func to_dict() -> Dictionary:
	var o: Dictionary = {}
	for id: String in overrides:
		var per: Dictionary = {}
		for device: String in overrides[id]:
			per[device] = Array(overrides[id][device])
		o[id] = per
	return {"overrides": o, "toggles": toggles.keys()}


## Restores to_dict() data; unknown intents and devices, and anything of the wrong
## type (a hand-edited file), are dropped.
func from_dict(data: Dictionary) -> void:
	overrides.clear()
	toggles.clear()
	var o: Variant = data.get("overrides", {})
	for id: Variant in o if o is Dictionary else {}:
		if not IntentTable.has(str(id)) or not o[id] is Dictionary:
			continue
		for device: Variant in o[id]:
			var list: Variant = o[id][device]
			if str(device) in IntentTable.DEVICES and _strings(list):
				var per: Dictionary = overrides.get_or_add(str(id), {})
				per[str(device)] = PackedStringArray(list)
	var t: Variant = data.get("toggles", [])
	for id: Variant in t if t is Array else []:
		if IntentTable.row(str(id)).get("kind", "") == IntentTable.HOLD:
			toggles[str(id)] = true
	changed.emit()


static func _strings(list: Variant) -> bool:
	if list is PackedStringArray:
		return true
	return list is Array and (list as Array).all(func(b: Variant) -> bool: return b is String)
