extends GdUnitTestSuite
## T028: Helm commands: validation and table reset (L1).


# FT: FT-ARC-008
# Selecting checks its target: not itself, not an unknown ship, not a non-finite point
# (FT-SIM-035: finite points wrap); non-finite stick input is rejected. Rejected
# commands change nothing and aren't logged; axes are clamped to [-1, 1].
func test_invalid_commands_rejected() -> void:
	var w: SimWorld = SimWorld.new(1, "test")
	var id: int = FlightFixture.spawn(w)
	FlightFixture.select_ship(w, id, id)
	FlightFixture.select_ship(w, id, 5)
	FlightFixture.select_point(w, id, 0, Vector3(0.0, NAN, 0.0))
	FlightFixture.input(w, id, Vector3(NAN, 0.0, 0.0))
	w.step()
	assert_int(w.helm.target_kind[id]).is_equal(HelmTable.Target.NONE)
	assert_vector(w.helm.input_rotation[id]).is_equal(Vector3.ZERO)
	assert_int(w.accepted_commands().size()).is_equal(0)
	FlightFixture.input(w, id, Vector3(3.0, -2.0, 0.0), Vector3(0.0, 0.0, 9.0))
	w.step()
	assert_vector(w.helm.input_rotation[id]).is_equal(Vector3(1.0, -1.0, 0.0))
	assert_vector(w.helm.input_translation[id]).is_equal(Vector3(0.0, 0.0, 1.0))


# Resetting a ship restores its helm row (assist on, nothing held or selected).
func test_reset_ship_restores_helm() -> void:
	var w: SimWorld = SimWorld.new(1, "test")
	var id: int = FlightFixture.spawn(w)
	var other: int = FlightFixture.spawn(w, Vector3(0.0, 0.0, -1000.0))
	FlightFixture.decouple(w, id, true)
	FlightFixture.select_ship(w, id, other)
	FlightFixture.select_ship(w, other, id)
	FlightFixture.input(w, id, Vector3.ONE, Vector3.ONE, true, true)
	w.step()
	w.reset_ship(id, 0)
	assert_bool(w.helm.is_decoupled(id)).is_false()
	assert_int(w.helm.target_kind[id]).is_equal(HelmTable.Target.NONE)
	assert_vector(w.helm.input_rotation[id]).is_equal(Vector3.ZERO)
	assert_int(w.helm.approach_held[id]).is_equal(0)
	assert_int(w.helm.target_ship[other]).is_equal(id)


# FT: FT-ARC-013
# Helm can select only ships its faction detects.
func test_select_requires_detection() -> void:
	var w: SimWorld = SimWorld.new(1, "test")
	var id: int = FlightFixture.spawn(w)
	var far: int = w.spawn_ship(TestDefs.raider(), 2, 0, Vector3(0, 0, -50000))
	var near: int = w.spawn_ship(TestDefs.raider(), 2, 0, Vector3(0, 0, -5000))
	w.step()
	FlightFixture.select_ship(w, id, far)
	w.step()
	assert_int(w.helm.target_ship[id]).is_equal(-1)
	FlightFixture.select_ship(w, id, near)
	w.step()
	assert_int(w.helm.target_ship[id]).is_equal(near)
