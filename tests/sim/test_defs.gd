class_name TestDefs
extends RefCounted
## Loaded M1 definitions for sim tests (tests may load; sim/ never does, FT-ARC-020).


static func corvette() -> ShipDef:
	return load("res://content/ships/m1_corvette.tres") as ShipDef


static func raider() -> ShipDef:
	return load("res://content/ships/m1_raider.tres") as ShipDef


static func raider_enemy() -> EnemyDef:
	return load("res://content/enemies/m1_raider.tres") as EnemyDef


## Every definition file under content/, loaded, by path. Hold the result while a test
## runs: load() keeps a resource cached only while something references it, so a
## definition nobody holds would be reloaded fresh and hide a change made to it
## (FT-ARC-020).
static func all_defs() -> Dictionary[String, Resource]:
	var out: Dictionary[String, Resource] = {}
	for path: String in DefLibrary.list_tres("res://content"):
		out[path] = load(path)
	return out


## def_hash of each definition, by path.
static func hashes(defs: Dictionary[String, Resource]) -> Dictionary[String, String]:
	var out: Dictionary[String, String] = {}
	for path: String in defs:
		out[path] = def_hash(defs[path])
	return out


## SHA-256 over a resource's stored properties, recursing into sub-resources, arrays
## and dictionaries (the script itself is skipped; its path is hashed instead).
static func def_hash(res: Resource) -> String:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(var_to_bytes(_plain(res)))
	return ctx.finish().hex_encode()


## The value with every Resource replaced by [script path, [name, value]...].
static func _plain(value: Variant) -> Variant:
	if value is Resource:
		var res: Resource = value
		var script: Script = res.get_script()
		var out: Array = [script.resource_path if script != null else res.get_class()]
		for p: Dictionary in res.get_property_list():
			var usage: int = p["usage"]
			if usage & PROPERTY_USAGE_STORAGE == 0 or p["name"] == "script":
				continue
			out.append([p["name"], _plain(res.get(p["name"]))])
		return out
	if value is Array:
		return (value as Array).map(func(v: Variant) -> Variant: return _plain(v))
	if value is Dictionary:
		var d: Dictionary = value
		var keys: Array = d.keys()
		keys.sort()
		return keys.map(func(k: Variant) -> Variant: return [k, _plain(d[k])])
	return value
