extends GdUnitTestSuite
## SnapshotInterpolator (FT-ARC-015): interpolation between snapshots, no extrapolation,
## minimum image across a site seam (D124), rotation slerp.

## A 1 km site: positions wrap into [-500 m, 500 m).
const P_UNITS: int = 16000


## A view at `tick` with the own ship at `own` (m) and contact 7 at `contact` (m).
func _view(
	tick: int, own: Vector3, contact: Vector3, rot: Quaternion = Quaternion.IDENTITY
) -> NetViewState:
	var v: NetViewState = NetViewState.new(P_UNITS)
	v.tick = tick
	v.kin = {"site": 0, "pos": _units(own), "rot": rot}
	v.contacts = {"model": {7: [_units(contact), Vector3i.ZERO, tick]}, "info": {7: [0, "H1"]}}
	return v


func _units(m: Vector3) -> Vector3i:
	return NetCodec.quant_pos(m.x, m.y, m.z, P_UNITS)


# FT: FT-ARC-015
func test_midway_between_two_snapshots() -> void:
	var interp: SnapshotInterpolator = SnapshotInterpolator.new()
	interp.push(_view(100, Vector3(0, 0, 0), Vector3(100, 0, 0)), 0)
	interp.push(_view(104, Vector3(20, 0, 0), Vector3(200, 0, -40)), 0)
	interp.render_tick = 102.0
	interp.update(0)
	assert_vector(interp.own_position()).is_equal_approx(Vector3(10, 0, 0), Vector3.ONE * 0.01)
	assert_array(interp.contact_ids()).is_equal([7])
	assert_vector(interp.contact_position(7)).is_equal_approx(
		Vector3(150, 0, -20), Vector3.ONE * 0.01
	)
	assert_vector(interp.offset_to(interp.contact_position(7))).is_equal_approx(
		Vector3(140, 0, -20), Vector3.ONE * 0.01
	)


# FT: FT-ARC-015
func test_render_clock_follows_time_and_never_passes_the_newest() -> void:
	var interp: SnapshotInterpolator = SnapshotInterpolator.new()
	interp.push(_view(100, Vector3.ZERO, Vector3.ZERO), 0)
	interp.push(_view(102, Vector3(2, 0, 0), Vector3.ZERO), 33)
	interp.update(33)
	var before: float = interp.render_tick
	interp.update(50)
	assert_float(interp.render_tick).is_greater(before)
	# No snapshot for 10 s: the picture stops at the newest one, no extrapolation.
	interp.update(10000)
	assert_float(interp.render_tick).is_equal(102.0)
	assert_vector(interp.own_position()).is_equal_approx(Vector3(2, 0, 0), Vector3.ONE * 0.01)


# FT: FT-ARC-015
func test_render_clock_snaps_when_far_behind() -> void:
	var interp: SnapshotInterpolator = SnapshotInterpolator.new()
	for i: int in 8:
		interp.push(_view(100 + 2 * i, Vector3.ZERO, Vector3.ZERO), 0)
	interp.update(0)
	# Started at the first tick, now far behind: it jumps to newest - delay.
	assert_float(interp.render_tick).is_equal(114.0 - SnapshotInterpolator.DELAY_TICKS)


# FT: FT-ARC-015
func test_seam_crossing_uses_the_minimum_image() -> void:
	var interp: SnapshotInterpolator = SnapshotInterpolator.new()
	# The contact moves 2 m in +X across the seam at x = ±500 m.
	interp.push(_view(100, Vector3(499, 0, 0), Vector3(499, 0, 0)), 0)
	interp.push(_view(104, Vector3(-499, 0, 0), Vector3(-499, 0, 0)), 0)
	interp.render_tick = 102.0
	interp.update(0)
	assert_float(absf(interp.contact_position(7).x)).is_equal_approx(500.0, 0.01)
	assert_float(absf(interp.own_position().x)).is_equal_approx(500.0, 0.01)
	interp.render_tick = 101.0
	interp.update(0)
	assert_float(interp.contact_position(7).x).is_equal_approx(499.5, 0.01)
	# The offset to a point just over the seam is short, not across the site.
	assert_vector(interp.offset_to(Vector3(-499.5, 0, 0))).is_equal_approx(
		Vector3(1, 0, 0), Vector3.ONE * 0.01
	)


# FT: FT-ARC-015
func test_rotation_slerps() -> void:
	var interp: SnapshotInterpolator = SnapshotInterpolator.new()
	var quarter: Quaternion = Quaternion(Vector3.UP, PI / 2.0)
	interp.push(_view(100, Vector3.ZERO, Vector3.ZERO), 0)
	interp.push(_view(104, Vector3.ZERO, Vector3.ZERO, quarter), 0)
	interp.render_tick = 102.0
	interp.update(0)
	var want: Quaternion = Quaternion(Vector3.UP, PI / 4.0)
	assert_float(interp.own_rotation().angle_to(want)).is_less(0.001)
	# The ship frame turns with it: a contact dead ahead in world -Z is off the bow.
	var local: Vector3 = interp.local(Vector3(0, 0, -100))
	assert_float(Callout.bearing_deg(local)).is_equal_approx(45.0, 0.1)


# FT: FT-ARC-015
func test_contacts_follow_the_older_sample() -> void:
	var interp: SnapshotInterpolator = SnapshotInterpolator.new()
	var a: NetViewState = _view(100, Vector3.ZERO, Vector3(10, 0, 0))
	var b: NetViewState = _view(104, Vector3.ZERO, Vector3(10, 0, 0))
	b.contacts["model"].erase(7)
	b.contacts["model"][9] = [_units(Vector3(5, 0, 0)), Vector3i.ZERO, 104]
	interp.push(a, 0)
	interp.push(b, 0)
	interp.render_tick = 102.0
	interp.update(0)
	assert_array(interp.contact_ids()).is_equal([7])
	interp.render_tick = 104.0
	interp.update(0)
	assert_array(interp.contact_ids()).is_equal([9])


# FT: FT-ARC-015
func test_jump_back_restarts() -> void:
	var interp: SnapshotInterpolator = SnapshotInterpolator.new()
	assert_bool(interp.has_data()).is_false()
	interp.push(_view(100, Vector3.ZERO, Vector3.ZERO), 0)
	interp.push(_view(50, Vector3(3, 0, 0), Vector3.ZERO), 0)
	assert_float(interp.render_tick).is_equal(50.0)
	assert_vector(interp.own_position()).is_equal_approx(Vector3(3, 0, 0), Vector3.ONE * 0.01)
