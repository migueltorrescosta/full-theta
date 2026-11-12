extends GdUnitTestSuite
## Review 2026-11-08 B1 and B2 (R09-2, R09-3, R09-5): the sim's edge paths. An empty
## tank, dead engines and thrusters, and commands to a destroyed ship.

const DT: float = 1.0 / 60.0


func _world() -> SimWorld:
	var w: SimWorld = SimWorld.new(1, "edge")
	w.spawn_ship(TestDefs.corvette(), 1)
	return w


func _row(w: SimWorld, id: StringName) -> int:
	return w.damage.find_subsystem(0, id)


# FT: FT-SIM-007
# Under full force and torque with 1 g of propellant: the tank ends at exactly 0, never
# below, the burn is scaled to what was left, and nothing moves after the first tick.
func test_empty_tank_stops_thrust_and_torque() -> void:
	var kin: Kinematics = Kinematics.new()
	kin.add_ship(0, 0, TestDefs.corvette())
	kin.propellant[0] = 0.001
	kin.force_cmd[0] = Vector3(0.0, 0.0, -5.0e5)
	kin.torque_cmd[0] = Vector3(0.0, 1.0e5, 0.0)
	Integrator.step(kin, 0, DT)
	assert_float(kin.propellant[0]).is_equal(0.0)
	var vel: Vector3 = kin.vel[0]
	var spin: Vector3 = kin.ang_vel[0]
	assert_float(vel.length()).is_less(1.0)
	for i: int in 120:
		Integrator.step(kin, 0, DT)
		assert_float(kin.propellant[0]).is_greater_equal(0.0)
	assert_vector(kin.vel[0]).is_equal(vel)
	assert_vector(kin.ang_vel[0]).is_equal(spin)
	assert_bool(kin.vel[0].is_finite() and kin.ang_vel[0].is_finite()).is_true()
	# Exactly empty with a demand: no NaN from the 0 / 0 scale.
	kin.propellant[0] = 0.0
	Integrator.step(kin, 0, DT)
	assert_bool(kin.vel[0].is_finite()).is_true()
	assert_vector(kin.vel[0]).is_equal(vel)


# FT: FT-SIM-006, FT-SIM-021
# Engines at 0 health give no thrust at full throttle; thrusters at 0 give no turn at
# full stick; half-health engines scale the envelope by their effectiveness. Assist stays
# finite throughout.
func test_dead_engines_and_thrusters_scale_thrust_and_turn() -> void:
	var w: SimWorld = _world()
	w.damage.health[_row(w, &"engines")] = 0.0
	w.damage.health[_row(w, &"thrusters")] = 0.0
	FlightFixture.input(w, 0, Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, 1.0))
	for i: int in 120:
		w.step()
	assert_float(w.kin.thrust_scale[0]).is_equal(0.0)
	assert_float(w.kin.torque_scale[0]).is_equal(0.0)
	assert_float(w.kin.vel[0].length()).is_less(1e-3)
	assert_float(w.kin.ang_vel[0].length()).is_less(1e-5)
	assert_bool(w.kin.vel[0].is_finite() and w.kin.ang_vel[0].is_finite()).is_true()
	assert_int(w.state_hash().length()).is_greater(0)
	var half: SimWorld = _world()
	var sd: SubsystemDef = TestDefs.corvette().subsystems[SimFixture.sub_index(half, 0, &"engines")]
	half.damage.health[_row(half, &"engines")] = 0.5 * sd.health_max
	half.step()
	assert_float(half.kin.thrust_scale[0]).is_equal_approx(
		PowerSystem.curve_at(sd.effectiveness, 0.5), 1e-9
	)


# FT: FT-SIM-006
# Facing and approaching with dead thrusters and engines produce finite commands.
func test_assist_with_zero_authority_stays_finite() -> void:
	var w: SimWorld = _world()
	w.spawn_ship(TestDefs.raider(), 2, CubePoint.make(0.0, 0.0, -3000.0))
	w.damage.health[_row(w, &"engines")] = 0.0
	w.damage.health[_row(w, &"thrusters")] = 0.0
	FlightFixture.input(w, 0, Vector3.ZERO, Vector3(0.0, 0.0, 1.0), true, true)
	for i: int in 180:
		w.step()
		assert_bool(w.kin.force_cmd[0].is_finite() and w.kin.torque_cmd[0].is_finite()).is_true()


# FT: FT-SIM-029
# Commands to a destroyed ship are dropped: refused, not logged, and nothing it would
# change moves (spare parts, pips, propellant). A server ResetShip still applies.
func test_commands_to_a_destroyed_ship_are_dropped() -> void:
	var w: SimWorld = _world()
	DamageSystem.damage_hull(w, 0, 1e12)
	w.step()
	assert_int(w.kin.alive[0]).is_equal(0)
	var parts: int = w.damage.spare_parts[w.damage.hull_row(0)]
	var pips: Array = SimFixture.sub_values(w, 0, "pips")
	var propellant: float = w.kin.propellant[0]
	var logged: int = w.accepted_commands().size()
	var cmds: Array[SimCommand] = []
	var fire: FireCommand = FireCommand.new()
	var set_pips: SetPipsCommand = SetPipsCommand.new()
	set_pips.subsystem_kind = SubsystemDef.Kind.ENGINES
	set_pips.pips = 3
	var dispatch: DispatchRepairCommand = DispatchRepairCommand.new()
	dispatch.subsystem_id = &"engines"
	var harden: HardenCommand = HardenCommand.new()
	harden.subsystem_id = &"sensors"
	var jump: JumpCommand = JumpCommand.new()
	jump.target_kind = HelmTable.JumpKind.MARK
	jump.x = 5000.0
	cmds.append_array([fire, set_pips, dispatch, harden, jump])
	for c: SimCommand in cmds:
		c.ship_id = 0
		w.submit(c)
	w.step()
	for c: SimCommand in cmds:
		assert_bool(c.accepted).override_failure_message(c.kind()).is_false()
	assert_int(w.accepted_commands().size()).is_equal(logged)
	assert_int(w.damage.spare_parts[w.damage.hull_row(0)]).is_equal(parts)
	assert_array(SimFixture.sub_values(w, 0, "pips")).is_equal(pips)
	assert_float(w.kin.propellant[0]).is_equal(propellant)
	assert_int(w.helm.jump_left[0]).is_equal(0)
	var reset: ResetShipCommand = ResetShipCommand.new()
	reset.ship_id = 0
	w.submit(reset)
	w.step()
	assert_bool(reset.accepted).is_true()
	assert_int(w.kin.alive[0]).is_equal(1)
