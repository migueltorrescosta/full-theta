extends GdUnitTestSuite
## Spike checks for S6 (#3): D98 site-local isolation (a far site behaves like the
## origin one), FT-ARC-008 and FT-ARC-009 (not traceability tags: the ids stay pending
## until M1). D104's slow drift 200 km from a site's centre is not covered here; it
## belongs to a T025 test with 64-bit offsets.

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


## Ships and projectiles at different sites never interact, even when their
## offsets overlap and the grid key keeps only the site's low 4 bits (site 16
## shares keys with site 0). Same sites at the same offsets do interact.
func test_sites_are_isolated() -> void:
	for layout: int in 2:
		for site_b: int in [0, 1, 16]:
			var world: Variant = S6WorldPacked.new(1) if layout == 0 else S6WorldObject.new(1)
			var zero := Vector3.ZERO
			var rot := Quaternion.IDENTITY
			world.add_ship(0, zero, zero, rot, zero, zero)
			world.add_ship(site_b, Vector3(10.0, 0.0, 0.0), zero, rot, zero, zero)
			# Passes 20 m from ship 0 and 30 m from ship 1 (hit radius 25.5 m).
			world.add_projectile(site_b, Vector3(-20.0, 0.0, -100.0), Vector3(0.0, 0.0, 3000.0), 10)
			var kinds: Array[int] = []
			for i in 5:
				world.step()
				var events: PackedInt32Array = world.events
				for e in range(1, events.size(), 4):
					kinds.append(events[e])
			var msg := "layout %d, site %d: %s" % [layout, site_b, kinds]
			if site_b == 0:
				assert_array(kinds).override_failure_message(msg).contains(
					[S6WorldPacked.EV_CONTACT, S6WorldPacked.EV_HIT]
				)
			else:
				assert_array(kinds).override_failure_message(msg).is_empty()
