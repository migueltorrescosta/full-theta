class_name DefLibrary
extends RefCounted
## Loads every .tres definition under a root folder and indexes the ones with an id
## by class and id. For tests, tools and the server; sim/ never calls it and receives
## definitions already loaded (FT-ARC-020). Validation is the load gate's job
## (tools/check_defs.gd, FT-DAT-002).

## Files that failed to load (res:// paths).
var load_failures: PackedStringArray = PackedStringArray()
## Class name (for example &"ShipDef") -> id -> definition.
var _by_class: Dictionary[StringName, Dictionary] = {}


func _init(root: String = "res://content") -> void:
	for path: String in list_tres(root):
		var res: Resource = load(path)
		if res == null:
			load_failures.append(path)
			continue
		var script: Script = res.get_script()
		if script == null or not ("id" in res):
			continue
		var cls: StringName = script.get_global_name()
		if not _by_class.has(cls):
			_by_class[cls] = {}
		_by_class[cls][res.get("id")] = res


## Every .tres file under root, recursively, sorted (res:// paths). ResourceLoader's
## listing also finds them in an export, where they are stored as .tres.remap.
static func list_tres(root: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for f: String in ResourceLoader.list_directory(root):
		if f.ends_with("/"):
			if not f.begins_with("."):
				out.append_array(list_tres(root.path_join(f.trim_suffix("/"))))
		elif f.get_extension() == "tres":
			out.append(root.path_join(f))
	out.sort()
	return out


## The definition of class cls with the given id, or null.
func get_def(cls: StringName, id: StringName) -> Resource:
	return _by_class.get(cls, {}).get(id) as Resource


func ship(id: StringName) -> ShipDef:
	return get_def(&"ShipDef", id) as ShipDef


func weapon(id: StringName) -> WeaponDef:
	return get_def(&"WeaponDef", id) as WeaponDef


func enemy(id: StringName) -> EnemyDef:
	return get_def(&"EnemyDef", id) as EnemyDef


func hazard(id: StringName) -> HazardDef:
	return get_def(&"HazardDef", id) as HazardDef


## The two hazards of the M1 encounter (D220): a dust cloud beside the line of fire and a
## radiation front sweeping in from behind the enemy.
func m1_hazards() -> Array[HazardDef]:
	return [hazard(&"m1_dust_cloud"), hazard(&"m1_radiation_front")]


func science(id: StringName = &"science") -> ScienceDef:
	return get_def(&"ScienceDef", id) as ScienceDef
