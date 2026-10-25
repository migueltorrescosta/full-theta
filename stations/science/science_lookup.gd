class_name ScienceLookup
extends RefCounted
## What the Science card needs from content/ to read the section's hashed ids
## (ScienceView.code): ship classes, damage types, the ScienceDef thresholds. Loaded once.

const SHIPS_DIR: String = "res://content/ships/"
const WEAPONS_DIR: String = "res://content/weapons/"
const DEF_PATH: String = "res://content/science/science.tres"

static var _classes: Dictionary = {}
static var _damage: Dictionary = {}
static var _def: ScienceDef = null


## The ShipDef whose id hashes to `code`, or null (class not known yet).
static func ship_class(code: int) -> ShipDef:
	if _classes.is_empty():
		for def: ShipDef in _load_all(SHIPS_DIR, ShipDef):
			_classes[ScienceView.code(def.id)] = def
			for type: StringName in def.resistances:
				_damage[ScienceView.code(type)] = String(type)
	return _classes.get(code, null)


## The damage type's id for a hashed code ("kinetic"), or "?".
static func damage_name(code: int) -> String:
	ship_class(0)
	if _damage.is_empty() or not _damage.has(code):
		for w: Resource in _load_all(WEAPONS_DIR, Resource):
			var type: Variant = w.get("damage_type")
			if type != null:
				_damage[ScienceView.code(StringName(type))] = String(type)
	return _damage.get(code, "?")


## The science tuning (reveal thresholds, lock threshold), or null.
static func science_def() -> ScienceDef:
	if _def == null and ResourceLoader.exists(DEF_PATH):
		_def = load(DEF_PATH) as ScienceDef
	return _def


## The reveal threshold of a card part (ScienceKnowledge's names), 2.0 when unknown.
static func threshold(part: StringName) -> float:
	var d: ScienceDef = science_def()
	if d == null:
		return 2.0
	match part:
		&"class":
			return d.reveal_class
		&"identity":
			return d.reveal_identity
		&"intent":
			return d.reveal_intent
		&"weak_points":
			return d.reveal_weak_points
		&"resistances":
			return d.reveal_resistances
		&"hack":
			return d.reveal_hack
	return 2.0


static func _load_all(dir: String, type: Variant) -> Array:
	var out: Array = []
	for f: String in DirAccess.get_files_at(dir):
		var name: String = f.trim_suffix(".remap")
		if name.ends_with(".tres"):
			var r: Resource = load(dir + name)
			if r != null and is_instance_of(r, type):
				out.append(r)
	return out
