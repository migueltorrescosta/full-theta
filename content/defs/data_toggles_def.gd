class_name DataTogglesDef
extends Resource
## The lobby's data-shortcut toggles and presets (spec §7.2, D84, D90, D92, D193): the list
## of toggles in display order, the preset a first launch starts on (FT-STN-016) and the
## split points of the banded summaries. One definition for the whole game, read-only at
## runtime (FT-ARC-020).

@export var id: StringName = &"toggles"
@export var toggles: Array[DataToggleDef] = []
## The preset a first launch starts on (FT-STN-016).
@export var default_preset: StringName = &"easy"
## Share of the maximum at which a banded summary steps down from ok to scratched, from
## scratched to damaged and from damaged to critical (dimensionless, descending, D193).
@export var band_edges: PackedFloat64Array = PackedFloat64Array()
## How long a shared shortcut reaches its partner after the source's press (s, D210): the
## partner sees the data until then, a newer press renews it.
@export var share_seconds: float = 30.0


func validate() -> Array[String]:
	var errors: Array[String] = []
	DefCheck.id(errors, "id", id)
	if toggles.is_empty():
		errors.append("toggles: must not be empty")
	var seen: Dictionary[StringName, bool] = {}
	for i: int in toggles.size():
		var t: DataToggleDef = toggles[i]
		if not DefCheck.required(errors, "toggles[%d]" % i, t):
			continue
		if seen.has(t.id):
			errors.append("toggles[%d].id: duplicate %s" % [i, t.id])
		seen[t.id] = true
		for e: String in t.validate():
			errors.append("toggles[%d].%s" % [i, e])
	if not [&"easy", &"normal", &"hard"].has(default_preset):
		errors.append("default_preset: must be easy, normal or hard, got %s" % default_preset)
	if band_edges.size() != 3:
		errors.append("band_edges: need 3 values, got %d" % band_edges.size())
	else:
		for i: int in 3:
			if not (band_edges[i] > 0.0 and band_edges[i] < 1.0):
				errors.append("band_edges[%d]: must be in (0, 1), got %s" % [i, band_edges[i]])
			if i > 0 and not band_edges[i] < band_edges[i - 1]:
				errors.append("band_edges[%d]: must be below the previous edge" % i)
	if not share_seconds > 0.0:
		errors.append("share_seconds: must be above 0, got %s" % share_seconds)
	return errors
