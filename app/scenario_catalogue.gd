class_name ScenarioCatalogue
extends RefCounted
## The scenarios the director may pick (E07, FT-DAT-006): every class in res://scenarios/
## whose meta id the run lists, one instance each. app/ loads them because the director
## may not name scenarios/ (D103). The director copies an instance for every encounter.

const FOLDER: String = "res://scenarios"


## Scenario instances for the ids, in the order of the ids; a listed id with no scenario
## is left out (the L0 scenario check reports it).
static func load_for(ids: PackedStringArray) -> Array[Scenario]:
	var found: Dictionary[StringName, Scenario] = {}
	for file: String in ResourceLoader.list_directory(FOLDER):
		if file.get_extension() != "gd":
			continue
		var script: GDScript = load(FOLDER.path_join(file)) as GDScript
		if script == null or not script.can_instantiate():
			continue
		var s: Variant = script.new()
		if s is Scenario and (s as Scenario).meta() != null:
			found[(s as Scenario).meta().id] = s
	var out: Array[Scenario] = []
	for id: String in ids:
		if found.has(StringName(id)):
			out.append(found[StringName(id)])
	return out
