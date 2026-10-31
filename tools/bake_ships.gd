extends SceneTree
## Bakes the ships (D308, FT-AUD-016): one PackedScene per look in content/ships/looks.json,
## with meshes whose ambient occlusion is already in the vertex colours, saved to
## content/ships/baked/<look>.scn. content/ships/baked/manifest.json records, for each look,
## the hash of everything its bake depends on (tools/ship_builder.gd, the hull sections, the
## look, the wear and the engine version). Every look shares one roughness and one normal
## map (D317), saved once as shared_roughness.res and shared_normal.res; the manifest's
## "shared" entry hashes their inputs.
##   godot --headless --path . -s res://tools/bake_ships.gd -- [--all | --check]
## Without a flag it bakes the stale looks, `--all` every look, `--check` bakes nothing and
## fails when a look is stale or a baked scene has no look (L0).
## `--baked <dir>` reads and writes another folder than content/ships/baked/ (the tests).

const LOOKS: String = "res://content/ships/looks.json"
const BUILDER: String = "res://tools/ship_builder.gd"

const SHARED: String = "shared"
const SHARED_FILES: PackedStringArray = ["shared_roughness.res", "shared_normal.res"]

var _dir: String = ProceduralShip.BAKED_DIR


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if "--baked" in args:
		_dir = args[args.find("--baked") + 1]
		if not _dir.ends_with("/"):
			_dir += "/"
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LOOKS))
	var wear: float = float(spec["wear"])
	var manifest: Dictionary = _manifest()
	var stale: PackedStringArray = []
	var want: Dictionary = {}
	for look: Dictionary in spec["looks"]:
		var key: String = str(look["name"]).to_lower()
		want[key] = _hash(look, wear)
		if manifest.get(key, "") != want[key] or not FileAccess.file_exists(_path(key)):
			stale.append(key)
	want[SHARED] = _shared_hash(wear)
	var have: bool = true
	for file: String in SHARED_FILES:
		have = have and FileAccess.file_exists(_dir + file)
	if manifest.get(SHARED, "") != want[SHARED] or not have:
		stale.append(SHARED)
	var orphans: PackedStringArray = []
	for file: String in DirAccess.get_files_at(_dir):
		if file.ends_with(".scn") and not want.has(file.get_basename()):
			orphans.append(file)
	if "--check" in args:
		for key: String in stale:
			printerr("bake_ships: %s is stale: run tools/bake_ships.gd" % key)
		for file: String in orphans:
			printerr("bake_ships: %s has no look: run tools/bake_ships.gd" % file)
		print(
			(
				"bake_ships: %d look(s), %d stale, %d orphan(s)"
				% [want.size() - 1, stale.size(), orphans.size()]
			)
		)
		quit(1 if stale.size() + orphans.size() > 0 else 0)
		return
	var shared: Array[ImageTexture] = []
	if "--all" in args or SHARED in stale:
		shared = ShipBuilder.bake_shared(wear)
		for k: int in SHARED_FILES.size():
			var err: Error = ResourceSaver.save(
				shared[k], _dir + SHARED_FILES[k], ResourceSaver.FLAG_COMPRESS
			)
			if err != OK:
				printerr("bake_ships: cannot save %s (%d)" % [SHARED_FILES[k], err])
				quit(1)
				return
			shared[k].take_over_path(_dir + SHARED_FILES[k])
		print("bake_ships: shared maps")
	for look: Dictionary in spec["looks"]:
		var key: String = str(look["name"]).to_lower()
		if "--all" in args or key in stale or SHARED in stale:
			if shared.is_empty():
				for file: String in SHARED_FILES:
					shared.append(load(_dir + file))
			var start: int = Time.get_ticks_msec()
			var err: Error = ResourceSaver.save(
				ShipBuilder.bake(look, wear, shared), _path(key), ResourceSaver.FLAG_COMPRESS
			)
			if err != OK:
				printerr("bake_ships: cannot save %s (%d)" % [_path(key), err])
				quit(1)
				return
			print("bake_ships: %s in %d ms" % [key, Time.get_ticks_msec() - start])
	for file: String in orphans:
		DirAccess.remove_absolute(_dir.path_join(file))
	var out: FileAccess = FileAccess.open(_dir + "manifest.json", FileAccess.WRITE)
	out.store_string(JSON.stringify(want, "  ", true) + "\n")
	quit(0)


func _path(key: String) -> String:
	return _dir + key + ".scn"


## The hash of the shared maps' inputs: the builder, the wear and the engine version.
func _shared_hash(wear: float) -> String:
	var parts: PackedStringArray = [
		FileAccess.get_file_as_string(BUILDER), str(wear), Engine.get_version_info()["string"]
	]
	return "\n".join(parts).sha256_text()


func _manifest() -> Dictionary:
	var path: String = _dir + "manifest.json"
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## The hash of the bake's inputs for one look.
func _hash(look: Dictionary, wear: float) -> String:
	var parts: PackedStringArray = [
		FileAccess.get_file_as_string(BUILDER),
		var_to_str(ProceduralShip.SECTIONS),
		JSON.stringify(look, "", true),
		str(wear),
		Engine.get_version_info()["string"],
	]
	return "\n".join(parts).sha256_text()
