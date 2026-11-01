extends GdUnitTestSuite
## ProceduralShip builds its parts once per process and its materials once per wear
## (#28, load fix 5); a bake in slices (ProceduralShip.warm) gives the same meshes.


func _ship(wear: float) -> ProceduralShip:
	var s: ProceduralShip = auto_free(ProceduralShip.new())
	s.wear = wear
	add_child(s)
	return s


func _bodies(s: ProceduralShip) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n: Node in s.find_children("*", "MeshInstance3D", true, false):
		out.append(n as MeshInstance3D)
	return out


# FT: FT-AUD-016
# Every ship shares the parts' meshes; ships of one wear share materials, other wears
# get their own.
func test_ships_share_meshes_and_materials_per_wear() -> void:
	var a: Array[MeshInstance3D] = _bodies(_ship(0.6))
	var b: Array[MeshInstance3D] = _bodies(_ship(0.6))
	var c: Array[MeshInstance3D] = _bodies(_ship(1.0))
	assert_int(a.size()).is_equal(88)
	assert_int(c.size()).is_equal(a.size())
	for i: int in a.size():
		assert_object(b[i].mesh).is_same(a[i].mesh)
		assert_object(c[i].mesh).is_same(a[i].mesh)
		assert_object(b[i].material_override).is_same(a[i].material_override)
		assert_object(c[i].material_override).is_not_same(a[i].material_override)
		assert_str(var_to_str(c[i].transform)).is_equal(var_to_str(a[i].transform))


# FT: FT-AUD-016
# A bake cut into slices of about 1 ms gives the meshes the shared parts have.
func test_a_sliced_bake_gives_the_same_meshes() -> void:
	ProceduralShip.warm(0.6, -1)
	var bake: ProceduralShip.Bake = ProceduralShip._start_bake()
	var calls: int = 1
	while not ProceduralShip._bake_slices(bake, Time.get_ticks_usec() + 1000):
		calls += 1
	assert_int(calls).is_greater(1)
	assert_int(bake.parts.size()).is_equal(ProceduralShip._parts.size())
	for i: int in bake.parts.size():
		var mine: ProceduralShip.Part = bake.parts[i]
		var shared: ProceduralShip.Part = ProceduralShip._parts[i]
		assert_int(mine.parent).is_equal(shared.parent)
		var got: PackedByteArray = var_to_bytes(mine.mesh.surface_get_arrays(0))
		assert_bool(got == var_to_bytes(shared.mesh.surface_get_arrays(0))).is_true()
