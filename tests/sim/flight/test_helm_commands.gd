extends GdUnitTestSuite
## T028: Helm commands: codec round trip, validation and table reset (L1).


func _commands() -> Array[SimCommand]:
	var i: HelmInputCommand = HelmInputCommand.new()
	i.rotation = Vector3(0.5, -1.0, 0.25)
	i.strafe = -0.5
	i.lift = 1.0
	i.throttle = 0.75
	i.face = true
	i.approach = true
	var d: DecoupledCommand = DecoupledCommand.new()
	d.decoupled = false
	var s: SelectTargetCommand = SelectTargetCommand.new()
	s.site = 3
	s.x = 123456.789012
	s.y = -0.5
	s.z = 7.0
	return [i, d, AllStopCommand.new(), LevelCommand.new(), s]


# FT: FT-ARC-008
# Every Helm command registers in the codec and round-trips its typed parameters.
func test_commands_round_trip() -> void:
	for c: SimCommand in _commands():
		c.ship_id = 2
		c.tick = 9
		var d: Dictionary = c.to_dict()
		var back: SimCommand = SimCommands.from_dict(d)
		assert_object(back).override_failure_message(str(c.kind())).is_not_null()
		assert_str(back.get_script().get_global_name()).is_equal(c.get_script().get_global_name())
		assert_dict(back.to_dict()).is_equal(d)


# FT: FT-ARC-008
# Selecting checks its target: not itself, not an unknown ship, not a point off the
# site grid; non-finite stick input is rejected. Rejected commands change nothing and
# aren't logged; axes are clamped to [-1, 1].
func test_invalid_commands_rejected() -> void:
	var w: SimWorld = FlightFixture.world()
	var id: int = FlightFixture.spawn(w)
	FlightFixture.select_ship(w, id, id)
	FlightFixture.select_ship(w, id, 5)
	FlightFixture.select_point(w, id, 0, Vector3(0.0, 200001.0, 0.0))
	FlightFixture.input(w, id, Vector3(NAN, 0.0, 0.0))
	w.step()
	assert_int(w.helm.target_kind[id]).is_equal(HelmTable.Target.NONE)
	assert_vector(w.helm.input_rotation[id]).is_equal(Vector3.ZERO)
	assert_int(w.command_log.size()).is_equal(0)
	FlightFixture.input(w, id, Vector3(3.0, -2.0, 0.0), Vector3(0.0, 0.0, 9.0))
	w.step()
	assert_vector(w.helm.input_rotation[id]).is_equal(Vector3(1.0, -1.0, 0.0))
	assert_vector(w.helm.input_translation[id]).is_equal(Vector3(0.0, 0.0, 1.0))


# FT: FT-GEN-002
# Resetting a ship restores its helm row (assist on, nothing held or selected).
func test_reset_ship_restores_helm() -> void:
	var w: SimWorld = FlightFixture.world()
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
	var w: SimWorld = FlightFixture.world()
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
