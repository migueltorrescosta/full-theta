extends GdUnitTestSuite
## Ships are baked at build time (D308): the game loads content/ships/baked/<look>.scn, the
## looks differ only in seeded panel shades and greebles, the stripe and the decal (D309),
## and a stale bake is found (tools/bake_ships.gd --check).

const SCRIPT: String = "res://tools/bake_ships.gd"


func _looks() -> Array:
	var spec: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/ships/looks.json")
	)
	return spec["looks"]


func _bodies(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for c: Node in n.find_children("*", "MeshInstance3D", true, false):
		out.append(c as MeshInstance3D)
	return out


func _hull(ship: Node3D) -> MeshInstance3D:
	return ship.find_child("BodyHull", true, false) as MeshInstance3D


func _albedo_hash(ship: Node3D) -> String:
	var m: StandardMaterial3D = _hull(ship).material_override as StandardMaterial3D
	return m.albedo_texture.get_image().get_data().hex_encode().sha256_text()


# FT: FT-AUD-016, FT-AUD-020
# Every look in looks.json has a baked scene with the ambient occlusion in vertex colours,
# and the manifest's hashes are the current ones.
func test_every_look_is_baked_with_its_occlusion() -> void:
	for look: Dictionary in _looks():
		var key: String = str(look["name"]).to_lower()
		assert_bool(ResourceLoader.exists(ProceduralShip.BAKED_DIR + key + ".scn")).is_true()
		var ship: Node3D = auto_free(ProceduralShip.instance(key))
		var bodies: Array[MeshInstance3D] = _bodies(ship)
		# E1: one mesh per material role, plus the greebles apart (was about 100 meshes).
		assert_int(bodies.size()).is_between(8, 12)
		var hull: ArrayMesh = _hull(ship).mesh as ArrayMesh
		var colours: PackedColorArray = hull.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		assert_int(colours.size()).is_equal(
			(hull.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		)
		var darkest: float = 1.0
		for c: Color in colours:
			darkest = minf(darkest, c.r)
		assert_float(darkest).is_less(0.95)


# FT: FT-AUD-016
# E1: the greebles are their own meshes, hidden beyond the detail range; the body meshes are
# drawn at any distance.
func test_greebles_drop_out_at_range_and_the_body_does_not() -> void:
	var ship: ProceduralShip = auto_free(ProceduralShip.new())
	ship.look = "kestrel"
	add_child(ship)
	var details: int = 0
	for body: MeshInstance3D in _bodies(ship):
		if body.is_in_group(ProceduralShip.DETAIL_GROUP):
			details += 1
			assert_float(body.visibility_range_end).is_equal(ProceduralShip.DETAIL_RANGE)
		else:
			assert_float(body.visibility_range_end).is_equal(0.0)
	assert_int(details).is_between(2, 3)
	# A ship drawn at 9x keeps its greebles 9x as far.
	ship.set_detail_scale(9.0)
	for body: MeshInstance3D in _bodies(ship):
		if body.is_in_group(ProceduralShip.DETAIL_GROUP):
			assert_float(body.visibility_range_end).is_equal(ProceduralShip.DETAIL_RANGE * 9.0)


# FT: FT-AUD-016
# E1: the merged ship covers the same space as the parts did: its box is the hull's box
# grown by the wings, nacelles, tail and greebles, not a collapsed one.
func test_merged_ship_keeps_its_extent() -> void:
	var ship: Node3D = auto_free(ProceduralShip.instance("generic"))
	var box: AABB = AABB()
	for body: MeshInstance3D in _bodies(ship):
		box = box.merge(body.mesh.get_aabb())
	assert_float(box.size.z).is_between(5.0, 5.6)
	assert_float(box.size.x).is_greater(1.5)
	assert_float(_hull(ship).mesh.get_aabb().size.z).is_between(4.9, 5.2)


# FT: FT-AUD-020
# The stale check passes on the committed bake, and fails on a copy whose manifest is
# out of date, naming the look, and on one with a baked scene no look wants.
func test_the_stale_check_passes_on_the_bake_and_fails_on_a_stale_one() -> void:
	var project: String = ProjectSettings.globalize_path("res://")
	var base: PackedStringArray = ["--headless", "--path", project, "-s", SCRIPT, "--"]
	var out: Array = []
	(
		assert_int(OS.execute(OS.get_executable_path(), base + PackedStringArray(["--check"]), out))
		. is_equal(0)
	)
	var copy: String = ProjectSettings.globalize_path("user://baked_copy")
	DirAccess.make_dir_recursive_absolute(copy)
	for f: String in DirAccess.get_files_at(ProceduralShip.BAKED_DIR):
		DirAccess.copy_absolute(ProceduralShip.BAKED_DIR + f, copy.path_join(f))
	var manifest: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(copy.path_join("manifest.json"))
	)
	manifest["kestrel"] = "0".repeat(64)
	FileAccess.open(copy.path_join("manifest.json"), FileAccess.WRITE).store_string(
		JSON.stringify(manifest)
	)
	DirAccess.copy_absolute(copy.path_join("tern.scn"), copy.path_join("gone.scn"))
	out.clear()
	var args: PackedStringArray = base + PackedStringArray(["--check", "--baked", copy])
	assert_int(OS.execute(OS.get_executable_path(), args, out, true)).is_equal(1)
	assert_str(out[0]).contains("kestrel is stale")
	assert_str(out[0]).contains("gone.scn has no look")
	assert_str(out[0]).not_contains("heron is stale")


# FT: FT-AUD-021
# Two seeds give different panels and greebles; the hull is the same, and so is every
# part's mesh bounds except the greebles'.
func test_two_seeds_give_different_panels_on_the_same_hull() -> void:
	var a: Dictionary = {"name": "A", "seed": 7, "stripe": "#c0785a", "decal": false}
	var b: Dictionary = {"name": "B", "seed": 99, "stripe": "#5a8fb0", "decal": false}
	var ship_a: Node3D = auto_free(ShipBuilder.bake(a, 0.8).instantiate())
	var ship_b: Node3D = auto_free(ShipBuilder.bake(b, 0.8).instantiate())
	var bodies_a: Array[MeshInstance3D] = _bodies(ship_a)
	var bodies_b: Array[MeshInstance3D] = _bodies(ship_b)
	assert_int(bodies_b.size()).is_equal(bodies_a.size())
	assert_object(_hull(ship_b).mesh.get_aabb()).is_equal(_hull(ship_a).mesh.get_aabb())
	assert_str(_albedo_hash(ship_a)).is_not_equal(_albedo_hash(ship_b))
	var greebles_a: PackedVector3Array = _greebles(ship_a)
	assert_bool(_greebles(ship_b) == greebles_a).is_false()
	# Same seed, same ship.
	var again: Node3D = auto_free(ShipBuilder.bake(a, 0.8).instantiate())
	assert_str(_albedo_hash(again)).is_equal(_albedo_hash(ship_a))
	assert_bool(_greebles(again) == greebles_a).is_true()


func _greebles(ship: Node3D) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	for body: MeshInstance3D in _bodies(ship):
		if body.is_in_group(ProceduralShip.DETAIL_GROUP):
			out.append_array(body.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
	return out


func _colours(ship: Node3D) -> Dictionary:
	var out: Dictionary = {}
	for body: MeshInstance3D in _bodies(ship):
		out[(body.material_override as StandardMaterial3D).albedo_color] = true
	return out


func _decals(ship: Node3D) -> int:
	var n: int = 0
	for body: MeshInstance3D in _bodies(ship):
		var m: StandardMaterial3D = body.material_override as StandardMaterial3D
		n += 1 if m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED else 0
	return n


# FT: FT-AUD-021
# A look has its own stripe colour, and a decal on each wing only when it names one.
func test_a_look_has_its_own_stripe_and_a_decal_when_asked() -> void:
	var plain: Node3D = auto_free(ProceduralShip.instance("generic"))
	var named: Node3D = auto_free(ProceduralShip.instance("kestrel"))
	var other: Node3D = auto_free(ProceduralShip.instance("heron"))
	assert_int(_decals(plain)).is_equal(0)
	# Both wings' decals are one merged mesh.
	assert_int(_decals(named)).is_equal(1)
	assert_int(_bodies(named).size()).is_equal(_bodies(plain).size() + 1)
	assert_bool(_colours(named).has(Color.from_string("#c0785a", Color.BLACK))).is_true()
	assert_bool(_colours(other).has(Color.from_string("#c0785a", Color.BLACK))).is_false()
	assert_bool(_colours(other).has(Color.from_string("#5a8fb0", Color.BLACK))).is_true()


# FT: FT-AUD-021
# The name decal is the name in capitals, in a texture sized to it.
func test_the_decal_texture_is_sized_to_the_name() -> void:
	var short: ShipBuilder = auto_free(ShipBuilder.new())
	short.decal_text = "TERN"
	var long: ShipBuilder = auto_free(ShipBuilder.new())
	long.decal_text = "KESTREL"
	assert_int(long._decal_texture().get_width()).is_greater(short._decal_texture().get_width())
	assert_float(long._decal_size().x).is_less_equal(ShipBuilder.DECAL_MAX_WIDTH + 0.001)
	assert_float(long._decal_size().y).is_less_equal(ShipBuilder.DECAL_HEIGHT + 0.001)


# FT: FT-AUD-021
# A ship name takes its own look when one is baked, the generic look otherwise.
func test_a_name_takes_its_own_look_or_the_generic_one() -> void:
	assert_str(ProceduralShip.look_for("Kestrel")).is_equal("kestrel")
	assert_str(ProceduralShip.look_for("Swift")).is_equal("swift")
	assert_str(ProceduralShip.look_for("Kestrel II")).is_equal(ProceduralShip.GENERIC)
	assert_str(ProceduralShip.look_for("")).is_equal(ProceduralShip.GENERIC)
	assert_str(ProceduralShip.look_for("Ship 7")).is_equal(ProceduralShip.GENERIC)


# FT: FT-AUD-016, FT-AUD-021
# Ships of one look share their meshes and materials; set_look swaps the model.
func test_ships_of_a_look_share_resources_and_set_look_swaps() -> void:
	var view: SpaceScene = auto_free(SpaceScene.new())
	add_child(view)
	var a: ProceduralShip = view.copy_ship("kestrel")
	var b: ProceduralShip = view.copy_ship("kestrel")
	var bodies_a: Array[MeshInstance3D] = _bodies(a)
	var bodies_b: Array[MeshInstance3D] = _bodies(b)
	assert_int(bodies_a.size()).is_between(8, 12)
	for i: int in bodies_a.size():
		assert_object(bodies_b[i].mesh).is_same(bodies_a[i].mesh)
		assert_object(bodies_b[i].material_override).is_same(bodies_a[i].material_override)
	var before: int = bodies_a.size()
	b.set_look("generic")
	await get_tree().process_frame
	assert_int(_bodies(b).size()).is_equal(before - 1)
	assert_str(b.look).is_equal("generic")


# FT: FT-AUD-016
# E2: the Low Graphics tier draws the ship without triplanar plating and normal maps, sharing
# one flat copy per baked material; the baked ones are untouched.
func test_low_graphics_ships_have_flat_materials() -> void:
	var baked: StandardMaterial3D = (
		_hull(auto_free(ProceduralShip.instance("generic"))).material_override
	)
	assert_bool(baked.uv1_triplanar).is_true()
	assert_bool(baked.normal_enabled).is_true()
	ProceduralShip.low_graphics = true
	var low: Node3D = ProceduralShip.instance("generic")
	var low_b: Node3D = ProceduralShip.instance("generic")
	ProceduralShip.low_graphics = false
	auto_free(low)
	auto_free(low_b)
	var flat: StandardMaterial3D = _hull(low).material_override
	assert_bool(flat.uv1_triplanar).is_false()
	assert_bool(flat.normal_enabled).is_false()
	assert_object(flat.albedo_texture).is_null()
	assert_object(_hull(low_b).material_override).is_same(flat)
	assert_bool(baked.uv1_triplanar).is_true()
	assert_float(flat.albedo_color.r).is_equal(baked.albedo_color.r)


# FT: FT-AUD-016
# E2: a ship built before the Low Graphics setting changed is rebuilt by the view.
func test_a_view_rebuilds_ships_when_low_graphics_changes() -> void:
	var view: SpaceScene = auto_free(SpaceScene.new())
	add_child(view)
	var ship: ProceduralShip = view.copy_ship("kestrel")
	assert_bool(ship.is_stale()).is_false()
	ProceduralShip.low_graphics = true
	assert_bool(ship.is_stale()).is_true()
	view.refresh_ship(ship, "kestrel")
	await get_tree().process_frame
	ProceduralShip.low_graphics = false
	assert_bool(_hull(ship).material_override.uv1_triplanar).is_false()
