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


## Every .tres file under root, recursively, sorted (res:// paths).
static func list_tres(root: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		return out
	for sub: String in dir.get_directories():
		if not sub.begins_with("."):
			out.append_array(list_tres(root.path_join(sub)))
	for f: String in dir.get_files():
		# An export converts x.tres to x.tres.remap plus a binary resource;
		# load() follows the remap from the original path.
		var name: String = f.trim_suffix(".remap")
		if name.get_extension() == "tres":
			out.append(root.path_join(name))
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
