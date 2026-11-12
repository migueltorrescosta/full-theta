class_name ContentPacks
extends RefCounted
## Data-only content packs (FT-DAT-015, FT-DAT-016, D472 to D474): every *.json file in the
## host's `--packs` folder adds NPC ships and encounters. A pack is JSON only, never a .pck,
## .tres or script, so it cannot run code; it only adds (its ids are namespaced, so it
## never replaces built-in content) and only the host reads it (clients need nothing).
## Each pack is checked like the content definitions: unknown keys, types and ranges, and
## every NPC through NpcDef/ShipDef.validate(); any error names the file and field, and the
## server refuses to start. The format is in docs/packs.md.

const FORMAT: int = 1
## Largest pack file read (bytes).
const MAX_BYTES: int = 256 * 1024
const ID_PATTERN: String = "^[a-z][a-z0-9_]{0,31}$"
const PACK_KEYS: Array[String] = [
	"format", "id", "name", "author", "licence", "ships", "encounters"
]
## A pack ship copies a built-in NPC (`base`) and may change these numbers: ShipDef fields,
## then NpcDef fields (SI units, D403).
const SHIP_FIELDS: Array[String] = ["hull_max", "sensor_range", "identify_range"]
const NPC_FIELDS: Array[String] = [
	"engage_range_min", "engage_range_max", "retreat_hull_fraction", "fire_cone"
]
## Encounter numbers and their inclusive ranges (PackWave.DEFAULTS has the defaults).
const ENCOUNTER_RANGES: Dictionary[String, Vector2] = {
	"count": Vector2(1, 6),
	"threat_cost": Vector2(1, 9),
	"second_after": Vector2(0, 600),
	"next_every": Vector2(1, 600),
	"taunt_after": Vector2(0, 600),
	"time_limit": Vector2(30, 1800),
}
const WHOLE: Array[String] = ["count", "threat_cost"]
const MAX_NAME: int = 40

## "<file>: <field>: <problem>" per error; empty when every pack loaded.
var errors: PackedStringArray = PackedStringArray()
## Pack NPCs by key ("<pack>.<ship>"), for the run's catalogue.
var npcs: Dictionary[StringName, NpcDef] = {}
## One PackWave per pack encounter (meta id "<pack>.<encounter>"), for the director.
var scenarios: Array[Scenario] = []
## "<id> (<file>)" per loaded pack, for the server's start line.
var loaded: PackedStringArray = PackedStringArray()

var _id_re: RegEx = RegEx.create_from_string(ID_PATTERN)


## Reads every *.json in `dir` (other files are ignored). `builtin` holds the built-in NPCs a
## pack ship copies and an encounter may name.
static func load_dir(dir: String, builtin: Dictionary[StringName, NpcDef]) -> ContentPacks:
	var p: ContentPacks = ContentPacks.new()
	if not DirAccess.dir_exists_absolute(dir):
		p.errors.append("%s: (folder): not found" % dir)
		return p
	var files: PackedStringArray = DirAccess.get_files_at(dir)
	files.sort()
	for f: String in files:
		if f.get_extension() == "json":
			p.add_file(dir.path_join(f), builtin)
	return p


## Checks and adds one pack file.
func add_file(path: String, builtin: Dictionary[StringName, NpcDef]) -> void:
	var file: String = path.get_file()
	if FileAccess.get_size(path) > MAX_BYTES:
		errors.append("%s: (file): larger than %d bytes" % [file, MAX_BYTES])
		return
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		errors.append(
			"%s: line %d: %s" % [file, json.get_error_line() + 1, json.get_error_message()]
		)
		return
	add_pack(file, json.data, builtin)


## Checks and adds one parsed pack; `file` names it in errors.
func add_pack(file: String, data: Variant, builtin: Dictionary[StringName, NpcDef]) -> void:
	var before: int = errors.size()
	var err: Callable = func(field: String, problem: String) -> void:
		errors.append("%s: %s: %s" % [file, field, problem])
	if not data is Dictionary:
		err.call("(pack)", "must be an object")
		return
	var pack: Dictionary = data
	_unknown_keys(pack, PACK_KEYS, "", err)
	if pack.get("format") != float(FORMAT):
		err.call("format", "must be %d" % FORMAT)
	var id: String = _id(pack, "id", "", err)
	for other: String in loaded:
		if other.begins_with(id + " "):
			err.call("id", "pack %s is already loaded (%s)" % [id, other])
	for key: String in ["name", "author", "licence"]:
		if pack.has(key) and not _name_ok(pack[key]):
			err.call(key, "must be text of 1 to %d characters" % MAX_NAME)
	var ships: Dictionary[StringName, NpcDef] = {}
	for i: int in _list(pack, "ships", err).size():
		var s: Variant = pack["ships"][i]
		var npc: NpcDef = _ship(id, "ships[%d]" % i, s, builtin, err)
		if npc != null:
			if ships.has(npc.id):
				err.call("ships[%d].id" % i, "duplicate %s" % (s as Dictionary)["id"])
			ships[npc.id] = npc
	var waves: Array[Scenario] = []
	for i: int in _list(pack, "encounters", err).size():
		var wave: PackWave = _encounter(
			id, "encounters[%d]" % i, pack["encounters"][i], ships, builtin, err
		)
		if wave != null:
			waves.append(wave)
	if ships.is_empty() and waves.is_empty() and errors.size() == before:
		err.call("(pack)", "adds no ships or encounters")
	if errors.size() > before:
		return
	npcs.merge(ships)
	scenarios.append_array(waves)
	loaded.append("%s (%s)" % [id, file])


func _ship(
	pack: String, at: String, data: Variant, builtin: Dictionary[StringName, NpcDef], err: Callable
) -> NpcDef:
	if not data is Dictionary:
		err.call(at, "must be an object")
		return null
	var s: Dictionary = data
	var keys: Array[String] = ["id", "base", "name"]
	keys.append_array(SHIP_FIELDS)
	keys.append_array(NPC_FIELDS)
	_unknown_keys(s, keys, at + ".", err)
	var id: String = _id(s, "id", at + ".", err)
	var base: NpcDef = builtin.get(StringName(str(s.get("base", ""))))
	if base == null:
		err.call(
			at + ".base",
			"must be a built-in NPC: %s" % ", ".join(PackedStringArray(builtin.keys()))
		)
		return null
	var npc: NpcDef = base.duplicate()
	npc.ship = base.ship.duplicate()
	npc.id = StringName("%s.%s" % [pack, id])
	npc.ship.id = npc.id
	if s.has("name"):
		if _name_ok(s["name"]):
			npc.display_name = s["name"]
			npc.ship.display_name = s["name"]
		else:
			err.call(at + ".name", "must be text of 1 to %d characters" % MAX_NAME)
	for field: String in SHIP_FIELDS + NPC_FIELDS:
		if not s.has(field):
			continue
		if not (s[field] is float and is_finite(s[field])):
			err.call(at + "." + field, "must be a number")
		elif SHIP_FIELDS.has(field):
			npc.ship.set(field, s[field])
		else:
			npc.set(field, s[field])
	for problem: String in npc.ship.validate() + npc.validate():
		err.call(at, problem)
	return npc


func _encounter(
	pack: String,
	at: String,
	data: Variant,
	ships: Dictionary[StringName, NpcDef],
	builtin: Dictionary[StringName, NpcDef],
	err: Callable
) -> PackWave:
	if not data is Dictionary:
		err.call(at, "must be an object")
		return null
	var e: Dictionary = data
	var keys: Array[String] = ["id", "ship", "name"]
	keys.append_array(ENCOUNTER_RANGES.keys())
	_unknown_keys(e, keys, at + ".", err)
	var spec: Dictionary = {"id": StringName("%s.%s" % [pack, _id(e, "id", at + ".", err)])}
	var ship: StringName = StringName(str(e.get("ship", "")))
	var local: StringName = StringName("%s.%s" % [pack, ship])
	if ships.has(local):
		spec["ship"] = local
	elif builtin.has(ship):
		spec["ship"] = ship
	else:
		err.call(at + ".ship", "must be one of this pack's ships or a built-in NPC")
	if e.has("name"):
		if _name_ok(e["name"]):
			spec["name"] = e["name"]
		else:
			err.call(at + ".name", "must be text of 1 to %d characters" % MAX_NAME)
	for field: String in ENCOUNTER_RANGES:
		if not e.has(field):
			continue
		var r: Vector2 = ENCOUNTER_RANGES[field]
		var v: Variant = e[field]
		if not v is float or v < r.x or v > r.y or (WHOLE.has(field) and v != roundf(v)):
			var kind: String = "a whole number" if WHOLE.has(field) else "a number"
			err.call(at + "." + field, "must be %s in [%d, %d]" % [kind, r.x, r.y])
		else:
			spec[field] = int(v) if WHOLE.has(field) else v
	var wave: PackWave = PackWave.of(spec)
	for problem: String in wave.meta().errors():
		err.call(at, problem)
	return wave


func _id(d: Dictionary, key: String, at: String, err: Callable) -> String:
	var v: Variant = d.get(key)
	if not v is String or _id_re.search(v) == null:
		err.call(at + key, "must match %s" % ID_PATTERN)
		return "?"
	return v


## The array under `key` (missing: empty), or empty with an error when it is not one.
static func _list(d: Dictionary, key: String, err: Callable) -> Array:
	var v: Variant = d.get(key, [])
	if not v is Array:
		err.call(key, "must be a list")
		return []
	return v


static func _unknown_keys(d: Dictionary, allowed: Array[String], at: String, err: Callable) -> void:
	for k: Variant in d:
		if not allowed.has(str(k)):
			err.call(at + str(k), "unknown key")


static func _name_ok(v: Variant) -> bool:
	return (
		v is String
		and not (v as String).strip_edges().is_empty()
		and (v as String).length() <= MAX_NAME
	)
