extends GdUnitTestSuite
## MountArc (shared/, FT-SIM-011, FT-ARC-021): the one arc rule the sim and Weapons use,
## on the edge angles.

const HALF: float = deg_to_rad(15.0)
const TOL: float = 1e-5


func _at(angle: float) -> Vector3:
	return Vector3.FORWARD.rotated(Vector3.UP, angle)


# FT: FT-SIM-011, FT-ARC-021
func test_in_arc_includes_the_edge() -> void:
	assert_bool(MountArc.in_arc(Vector3.FORWARD, HALF, Vector3.FORWARD)).is_true()
	assert_bool(MountArc.in_arc(Vector3.FORWARD, HALF, _at(HALF - 1e-4))).is_true()
	assert_bool(MountArc.in_arc(Vector3.FORWARD, HALF, _at(-HALF + 1e-4))).is_true()
	assert_bool(MountArc.in_arc(Vector3.FORWARD, HALF, _at(HALF + 1e-4))).is_false()
	assert_bool(MountArc.in_arc(Vector3.FORWARD, HALF, Vector3.BACK)).is_false()


# FT: FT-SIM-011
func test_in_arc_matches_weapon_system() -> void:
	var def: MountDef = MountDef.new()
	def.forward = Vector3.FORWARD
	def.arc_half_angle = HALF
	for k: int in range(-40, 41):
		var dir: Vector3 = _at(k * 0.01).rotated(Vector3.RIGHT, k * 0.003)
		assert_bool(WeaponSystem.in_arc(def, dir)).is_equal(MountArc.in_arc(def.forward, HALF, dir))


# FT: FT-SIM-011
func test_clamp_keeps_inside_and_stops_outside_at_the_edge() -> void:
	var inside: Vector3 = _at(0.1)
	assert_vector(MountArc.clamp_to_arc(Vector3.FORWARD, HALF, inside)).is_equal(inside)
	var out: Vector3 = MountArc.clamp_to_arc(Vector3.FORWARD, HALF, Vector3.RIGHT)
	assert_float(Vector3.FORWARD.angle_to(out)).is_equal_approx(HALF, TOL)
	assert_float(out.x).is_greater(0.0)
	# Straight behind: still on the edge, about some axis square to forward.
	var behind: Vector3 = MountArc.clamp_to_arc(Vector3.FORWARD, HALF, Vector3.BACK)
	assert_float(Vector3.FORWARD.angle_to(behind)).is_equal_approx(HALF, TOL)


# FT: FT-SIM-011
func test_turn_toward_stops_at_the_angle() -> void:
	var to: Vector3 = Vector3(1, 0, -1).normalized()
	assert_vector(MountArc.turn_toward(Vector3.FORWARD, to, 1.0)).is_equal(to)
	var part: Vector3 = MountArc.turn_toward(Vector3.FORWARD, Vector3.RIGHT, 0.25)
	assert_float(Vector3.FORWARD.angle_to(part)).is_equal_approx(0.25, TOL)
	assert_float(part.x).is_greater(0.0)
	# Opposite directions still turn (about an axis off `from`), also from straight up.
	var back: Vector3 = MountArc.turn_toward(Vector3.FORWARD, Vector3.BACK, 0.5)
	assert_float(Vector3.FORWARD.angle_to(back)).is_equal_approx(0.5, TOL)
	var down: Vector3 = MountArc.turn_toward(Vector3.UP, Vector3.DOWN, 0.5)
	assert_float(Vector3.UP.angle_to(down)).is_equal_approx(0.5, TOL)
