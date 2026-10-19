extends GdUnitTestSuite
## Spike checks for S6 (#3). Spike check for FT-SIM-035, FT-ARC-008 and
## FT-ARC-009 (not traceability tags: the ids stay pending until M1).

const FAR := 1.0e8


## The same intercept at a site 1e8 m from the world origin, with site-local
## positions, ends bit-identical to the one at the origin (R16, D98).
func test_far_site_intercept_matches_origin() -> void:
	var ref := S6Intercept.run(0, Vector3.ZERO)
	var far := S6Intercept.run(1, Vector3.ZERO)
	assert_int(ref["hit_tick"]).is_greater(0)
	assert_int(ref["hit_ship"]).is_equal(S6Intercept.TARGET)
	assert_int(ref["contact_tick"]).is_greater(ref["warn_tick"])
	assert_int(ref["warn_tick"]).is_greater(0)
	for key: String in ["hit_tick", "hit_ship", "warn_tick", "contact_tick"]:
		assert_int(far[key]).is_equal(ref[key])
	var ref_pos: Array[Vector3] = ref["pos"]
	var far_pos: Array[Vector3] = far["pos"]
	var ref_rot: Array[Quaternion] = ref["rot"]
	var far_rot: Array[Quaternion] = far["rot"]
	for s in ref_pos.size():
		# Exact comparison: Vector3 and Quaternion == compare floats bit for bit.
		assert_bool(far_pos[s] == ref_pos[s]).is_true()
		assert_bool(far_rot[s] == ref_rot[s]).is_true()
	assert_bool(far["proj"] == ref["proj"]).is_true()
	# In float64 the far ship sits exactly FAR metres from the origin one.
	var origin := S6Intercept.world_position(PackedFloat64Array([0.0, 0.0, 0.0]), ref_pos[1])
	var moved := S6Intercept.world_position(PackedFloat64Array([FAR, 0.0, 0.0]), far_pos[1])
	assert_float(moved[0] - origin[0]).is_equal(FAR)
	assert_float(moved[1]).is_equal(origin[1])


## The comparison case: naive global float32 positions 1e8 m out (spacing
## 8 m) freeze slow ships and break the intercept.
func test_naive_global_float32_breaks_far_away() -> void:
	var ref := S6Intercept.run(0, Vector3.ZERO)
	var base := Vector3(FAR, 0.0, 0.0)
	var naive := S6Intercept.run(0, base)
	var err := S6Intercept.max_error(naive, ref, base)
	print("S6 naive float32 at 1e8 m: max position error %.1f m" % err)
	assert_float(err).is_greater(100.0)
	assert_int(naive["contact_tick"]).is_not_equal(ref["contact_tick"])


## Same seed gives the same run, and both layouts agree tick for tick.
func test_layouts_agree_and_repeat() -> void:
	var a := S6WorldPacked.new(42)
	var b := S6WorldPacked.new(42)
	var c := S6WorldObject.new(42)
	a.setup_benchmark(20, 60)
	b.setup_benchmark(20, 60)
	c.setup_benchmark(20, 60)
	for i in 120:
		a.step()
		b.step()
		c.step()
		assert_bool(a.events == c.events).is_true()
	assert_float(b.checksum()).is_equal(a.checksum())
	assert_float(c.checksum()).is_equal(a.checksum())
	assert_int(a.total_hits).is_greater(0)
