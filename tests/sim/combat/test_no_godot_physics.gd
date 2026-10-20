extends GdUnitTestSuite
## FT-ARC-007: the simulation uses its own integrator and collisions, no Godot physics.

const PHYSICS: String = (
	"\\b(PhysicsServer[23]D\\w*|PhysicsBody[23]D|RigidBody[23]D|CharacterBody[23]D|"
	+ "StaticBody[23]D|AnimatableBody[23]D|Area[23]D|CollisionShape[23]D|"
	+ "PhysicsDirect\\w+|PhysicsRayQueryParameters[23]D|move_and_slide)\\b"
)


# FT: FT-ARC-007
func test_sim_names_no_godot_physics() -> void:
	var re: RegEx = RegEx.create_from_string(PHYSICS)
	var found: Array[String] = []
	var files: Array[String] = _gd_files("res://sim")
	for f: String in files:
		for m: RegExMatch in re.search_all(FileAccess.get_file_as_string(f)):
			found.append("%s: %s" % [f, m.get_string()])
	assert_int(files.size()).is_greater(10)
	assert_array(found).is_empty()


func _gd_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d: String in DirAccess.get_directories_at(dir):
		out.append_array(_gd_files(dir.path_join(d)))
	return out
