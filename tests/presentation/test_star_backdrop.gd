extends GdUnitTestSuite
## The star backdrop (D310): a fixed far-off shell, denser and brighter than M1's 700 points,
## with a galaxy band and its haze, and no parallax.


func _points(mesh: ArrayMesh, surface: int) -> PackedVector3Array:
	return mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]


# FT: FT-AUD-022
# Several times M1's 700 stars, all on the shell, with a band denser than the field.
func test_the_backdrop_is_denser_than_m1_and_all_on_the_shell() -> void:
	var mesh: ArrayMesh = SpaceView._star_mesh()
	assert_int(mesh.get_surface_count()).is_equal(4)
	var stars: int = 0
	for s: int in 3:
		for p: Vector3 in _points(mesh, s):
			stars += 1
			assert_float(p.length()).is_equal_approx(SpaceView.STAR_R, 0.01)
	assert_int(stars).is_greater_equal(5 * 700)
	for p: Vector3 in _points(mesh, 3):
		assert_float(p.length()).is_equal_approx(SpaceView.STAR_R, 0.01)


# FT: FT-AUD-022
# The band's stars lie near its great circle, the field's don't.
func test_the_band_stars_hug_the_great_circle() -> void:
	var mesh: ArrayMesh = SpaceView._star_mesh()
	var normal: Vector3 = SpaceView.BAND_NORMAL.normalized()
	var near_band: int = 0
	for p: Vector3 in _points(mesh, 2):
		if absf((p / SpaceView.STAR_R).dot(normal)) < 0.35:
			near_band += 1
	assert_float(float(near_band) / _points(mesh, 2).size()).is_greater(0.95)
	var field_near: int = 0
	for p: Vector3 in _points(mesh, 0):
		if absf((p / SpaceView.STAR_R).dot(normal)) < 0.35:
			field_near += 1
	assert_float(float(field_near) / _points(mesh, 0).size()).is_less(0.5)


# FT: FT-AUD-022
# The haze is additive and faint, and the stars are the same on every build.
func test_the_haze_is_faint_and_the_stars_are_seeded() -> void:
	var mesh: ArrayMesh = SpaceView._star_mesh()
	var material: StandardMaterial3D = mesh.surface_get_material(3) as StandardMaterial3D
	assert_int(material.blend_mode).is_equal(BaseMaterial3D.BLEND_MODE_ADD)
	for c: Color in mesh.surface_get_arrays(3)[Mesh.ARRAY_COLOR]:
		assert_float(c.a).is_less_equal(SpaceView.HAZE_PEAK + 0.001)
	assert_bool(_points(SpaceView._star_mesh(), 0) == _points(mesh, 0)).is_true()


# FT: FT-AUD-022
# The backdrop moves with the camera, so it never parallaxes.
func test_the_backdrop_follows_the_camera() -> void:
	var view: SpaceView = auto_free(SpaceView.new())
	add_child(view)
	view.place_camera(Transform3D(Basis(), Vector3(120, -40, 7)), 70.0)
	assert_vector(view._stars.position).is_equal(Vector3(120, -40, 7))
