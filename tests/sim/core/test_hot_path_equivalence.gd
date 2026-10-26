extends GdUnitTestSuite
## The per-tick loops that run a helper's arithmetic inline give exactly the helper's
## results (bit for bit), over seeded random states: Integrator.step_all against
## Integrator.step per row, and AssistSystem's per-tick target lookup against
## has_target() and target_offset().

const DT: float = 1.0 / 60.0
const CASES: int = 200


# FT: FT-SIM-038, FT-ARC-007
# step_all over a table equals step() row by row: every column, bit for bit, including
# dead rows (skipped) and burns that run out of propellant.
func test_step_all_equals_step_per_row() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 41
	for c: int in CASES:
		var a: Kinematics = _random_table(rng, c)
		var b: Kinematics = _copy(a)
		Integrator.step_all(a, DT)
		for row: int in b.size():
			if b.is_alive(row):
				Integrator.step(b, row, DT)
		assert_array(_bytes(a)).override_failure_message("case %d" % c).is_equal(_bytes(b))


# FT: FT-HLM-005, FT-ARC-013
# The target lookup AssistSystem.step uses is target_offset() exactly when has_target()
# holds and not finite otherwise: ships and points, dead, own and
# undetected ships.
func test_targeted_offset_equals_has_target_and_target_offset() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 43
	var hits: int = 0
	for c: int in CASES:
		var w: SimWorld = SimWorld.new(c, "test")
		var n: int = rng.randi_range(2, 6)
		for i: int in n:
			w.spawn_ship(
				TestDefs.corvette(),
				rng.randi_range(1, 3),
				Vector3(
					rng.randf_range(-99000, 99000),
					rng.randf_range(-99000, 99000),
					rng.randf_range(-99000, 99000)
				)
			)
			if rng.randf() < 0.2:
				w.kin.alive[i] = 0
		KnowledgeSystem.step(w)
		for row: int in n:
			var kind: int = rng.randi_range(0, 2)
			w.helm.target_kind[row] = kind
			w.helm.target_ship[row] = rng.randi_range(-1, n) if kind == 1 else -1
			w.helm.target_x[row] = rng.randf_range(-99000, 99000)
			w.helm.target_y[row] = rng.randf_range(-99000, 99000)
			w.helm.target_z[row] = rng.randf_range(-99000, 99000)
			var got: Vector3 = AssistSystem._targeted_offset(w, w.kin, w.helm, row)
			var msg: String = "case %d row %d" % [c, row]
			if AssistSystem.has_target(w, row):
				hits += 1
				var want: Vector3 = AssistSystem.target_offset(w, row)
				assert_array([got.x, got.y, got.z]).override_failure_message(msg).is_equal(
					[want.x, want.y, want.z]
				)
			else:
				assert_bool(got.is_finite()).override_failure_message(msg).is_false()
	assert_int(hits).is_greater(CASES / 2)


func _random_table(rng: RandomNumberGenerator, c: int) -> Kinematics:
	var kin: Kinematics = Kinematics.new()
	var n: int = rng.randi_range(1, 5)
	for i: int in n:
		kin.add_ship(i, 1, TestDefs.corvette() if i % 2 == 0 else TestDefs.raider())
		kin.place(
			i,
			rng.randf_range(-100000, 100000),
			rng.randf_range(-100000, 100000),
			rng.randf_range(-100000, 100000)
		)
		kin.rot[i] = Quaternion(_unit(rng), rng.randf_range(-PI, PI))
		kin.vel[i] = _unit(rng) * rng.randf_range(0.0, 300.0)
		kin.set_angular_velocity(i, _unit(rng) * rng.randf_range(0.0, 0.5))
		kin.force_cmd[i] = _unit(rng) * rng.randf_range(0.0, 2.0e6)
		kin.torque_cmd[i] = _unit(rng) * rng.randf_range(0.0, 8.0e6)
		kin.thrust_scale[i] = rng.randf_range(0.0, 1.5)
		kin.torque_scale[i] = rng.randf_range(0.0, 1.5)
		# Some ships nearly out of propellant, some dead.
		if rng.randf() < 0.3:
			kin.propellant[i] = rng.randf_range(0.0, 0.05)
		if rng.randf() < 0.2 and c % 2 == 0:
			kin.alive[i] = 0
	return kin


func _unit(rng: RandomNumberGenerator) -> Vector3:
	var v: Vector3 = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
	return v.normalized() if v.length() > 1e-3 else Vector3.UP


func _copy(kin: Kinematics) -> Kinematics:
	var out: Kinematics = Kinematics.new()
	out.period = kin.period
	for col: Array in kin.columns():
		var value: Variant = col[1]
		out.set(col[0], value.duplicate())
	return out


func _bytes(kin: Kinematics) -> Array:
	var out: Array = []
	for col: Array in kin.columns():
		out.append(var_to_bytes(col[1]))
	return out
