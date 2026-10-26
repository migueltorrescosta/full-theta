extends SceneTree
## Scenario metadata gate (FT-DAT-008, FT-MIS-041, E07): loads every script in
## res://scenarios, instantiates the ones extending Scenario and prints the errors() of
## their ScenarioMeta, plus duplicate ids. Exits 1 on any.
##   godot --headless --path . -s res://tools/check_scenarios.gd


func _init() -> void:
	var errors: PackedStringArray = PackedStringArray()
	var ids: Dictionary[StringName, String] = {}
	var count: int = 0
	for file: String in ResourceLoader.list_directory("res://scenarios"):
		if file.get_extension() != "gd":
			continue
		var script: GDScript = load("res://scenarios/" + file) as GDScript
		var s: Variant = script.new() if script != null and script.can_instantiate() else null
		if not s is Scenario:
			errors.append("%s: not a Scenario" % file)
			continue
		count += 1
		var meta: ScenarioMeta = (s as Scenario).meta()
		if meta == null:
			errors.append("%s: meta() returned null" % file)
			continue
		for e: String in meta.errors():
			errors.append("%s: %s" % [file, e])
		if ids.has(meta.id):
			errors.append("%s: id %s also in %s" % [file, meta.id, ids[meta.id]])
		ids[meta.id] = file
	for e: String in errors:
		print(e)
	print("check_scenarios: %d scenario(s), %d error(s)" % [count, errors.size()])
	quit(1 if errors.size() > 0 else 0)
