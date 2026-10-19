extends GdUnitTestSuite
## T030: power pips within the reactor cap, overcharge heat and faults, the boost, the
## weapons energy store and the thrust envelope (L2). Numbers come from the M1 corvette
## content: 12 reactor pips, 4 per subsystem, 2 nominal on engines, thrusters, weapons,
## shields and sensors, 5 K/s per overcharged pip, dissipation 0.05/s, fault at 100 K,
## envelope (0, 0.25) (1, 1) (2, 1.5), heat derate (0, 1) (1, 1) (2, 0.5), 8 s boost,
## 20 MW reactor, 5 MJ weapons store.

const ENG: int = SubsystemDef.Kind.ENGINES
const THR: int = SubsystemDef.Kind.THRUSTERS
const WPN: int = SubsystemDef.Kind.WEAPONS
const SHD: int = SubsystemDef.Kind.SHIELDS


func _world() -> SimWorld:
	var w: SimWorld = SimWorld.new(1, "test")
	w.spawn_ship(TestDefs.corvette(), 1, 0)
	return w


func _pips(w: SimWorld, kind: int, pips: int) -> bool:
	var c: SetPipsCommand = SetPipsCommand.new()
	c.ship_id = 0
	c.subsystem_kind = kind
	c.pips = pips
	w.submit(c)
	var logged: int = w.command_log.size()
	w.step()
	return w.command_log.size() > logged


func _steps(w: SimWorld, n: int) -> void:
	for i: int in n:
		w.step()


func _faults(events: Array[SimEvent]) -> Array[SimEvent]:
	return events.filter(func(e: SimEvent) -> bool: return e.kind == &"fault")


# FT: FT-SIM-026
# Pips per subsystem stay within the reactor cap and the per-subsystem maximum;
# overcharge above nominal is allowed; the reactor takes no pips.
func test_pips_within_cap() -> void:
	var w: SimWorld = _world()
	assert_array(Array(w.power.pips[0])).is_equal([2, 2, 2, 2, 2, 0])
	assert_bool(_pips(w, ENG, 4)).is_true()
	assert_bool(_pips(w, WPN, 3)).is_false()
	assert_bool(_pips(w, THR, 5)).is_false()
	assert_bool(_pips(w, THR, -1)).is_false()
	assert_bool(_pips(w, SubsystemDef.Kind.REACTOR, 1)).is_false()
	assert_bool(_pips(w, WPN, 0)).is_true()
	assert_bool(_pips(w, SHD, 4)).is_true()
	assert_array(Array(w.power.pips[0])).is_equal([4, 2, 0, 4, 2, 0])
	assert_int(w.command_log.size()).is_equal(3)


# FT: FT-SIM-026
# Overcharge builds heat as dT/dt = 5 K/s * 2 pips - 0.05/s * T; heat passes 100 K at
# t = ln 2 / 0.05 = 13.86 s (tick 831), where exactly one fault fires; after cooling
# below 80 K a new overcharge can fault again. Nominal pips never heat.
func test_overcharge_heat_creates_one_fault() -> void:
	var w: SimWorld = _world()
	_steps(w, 600)
	assert_float(w.power.heat[0][0]).is_equal(0.0)
	assert_bool(_pips(w, ENG, 4)).is_true()
	# The command applied on the tick _pips stepped.
	var start: int = w.tick - 1
	_steps(w, 599)
	# 10 s of overcharge: 200 K * (1 - e^-0.5); exact stepping, float tolerance.
	assert_float(w.power.heat[0][0]).is_equal_approx(200.0 * (1.0 - exp(-0.5)), 1e-6)
	_steps(w, 1200)
	var faults: Array[SimEvent] = _faults(w.drain_events())
	assert_int(faults.size()).is_equal(1)
	assert_int(faults[0].tick - start).is_equal(831)
	assert_str(String(faults[0].tag)).is_equal("engines")
	assert_int(faults[0].other_id).is_equal(0)
	assert_float(faults[0].value).is_greater(100.0)
	assert_bool(_pips(w, ENG, 2)).is_true()
	_steps(w, 60 * 20)
	assert_float(w.power.heat[0][0]).is_less(80.0)
	assert_int(_faults(w.drain_events()).size()).is_equal(0)
	assert_bool(_pips(w, ENG, 4)).is_true()
	_steps(w, 60 * 20)
	assert_int(_faults(w.drain_events()).size()).is_equal(1)


# FT: FT-SIM-006
# The envelope function at table points: envelope_curve(pip ratio) * effectiveness *
# heat_derate(heat / threshold), linear between points, clamped past the ends.
func test_envelope_at_table_points() -> void:
	var p: PowerDef = TestDefs.corvette().power
	# [pip ratio, effectiveness, heat ratio, expected]
	var table: Array[Array] = [
		[1.0, 1.0, 0.0, 1.0],
		[0.0, 1.0, 0.0, 0.25],
		[0.5, 1.0, 0.0, 0.625],
		[1.5, 1.0, 0.0, 1.25],
		[2.0, 1.0, 0.0, 1.5],
		[3.0, 1.0, 0.0, 1.5],
		[1.0, 0.8, 0.0, 0.8],
		[1.0, 1.0, 1.0, 1.0],
		[1.0, 1.0, 1.5, 0.75],
		[2.0, 1.0, 2.0, 0.75],
		[2.0, 0.5, 3.0, 0.375],
	]
	for row: Array in table:
		var got: float = PowerSystem.envelope(p, row[0], row[1], row[2])
		assert_float(got).override_failure_message("%s gave %s" % [row, got]).is_equal_approx(
			row[3], 1e-9
		)


# FT: FT-SIM-006
# Power writes the envelope each tick: nominal pips and full health give 1; engine
# pips set the thrust scale and thruster pips the torque scale.
func test_envelope_follows_pips() -> void:
	var w: SimWorld = _world()
	w.kin.thrust_scale[0] = 0.3
	w.step()
	assert_float(w.kin.thrust_scale[0]).is_equal(1.0)
	assert_float(w.kin.torque_scale[0]).is_equal(1.0)
	assert_bool(_pips(w, ENG, 1)).is_true()
	assert_bool(_pips(w, THR, 4)).is_true()
	assert_float(w.kin.thrust_scale[0]).is_equal_approx(0.625, 1e-9)
	assert_float(w.kin.torque_scale[0]).is_equal_approx(1.5, 1e-9)
	assert_bool(_pips(w, ENG, 0)).is_true()
	assert_float(w.kin.thrust_scale[0]).is_equal_approx(0.25, 1e-9)


# Ticks for a ship flown by Helm through assist (on by default) to turn 90 degrees at
# full yaw input, then to cover 2 km at full throttle (a crude stand-in for the P1 test,
# T039). Both phases are bounded by a tick limit so a regression fails instead of hanging.
func _turn_and_sprint(boost: bool) -> int:
	var w: SimWorld = _world()
	if boost:
		var b: BoostCommand = BoostCommand.new()
		b.ship_id = 0
		w.submit(b)
	FlightFixture.input(w, 0, Vector3(0, 1, 0))
	var limit: int = 60 * 30
	while Vector3.FORWARD.angle_to(w.kin.forward(0)) < PI / 2 and w.tick < limit:
		w.step()
	assert_int(w.tick).override_failure_message("turn did not finish").is_less(limit)
	FlightFixture.input(w, 0, Vector3.ZERO, Vector3(0, 0, 1))
	while w.kin.relative_to_point(0, 0.0, 0.0, 0.0).length() < 2000.0 and w.tick < limit:
		w.step()
	assert_int(w.tick).override_failure_message("sprint did not finish").is_less(limit)
	return w.tick


# FT: FT-SIM-006, FT-SIM-026
# A boost runs engines and thrusters at 4 pips for 8 s above the cap (envelope 1.5),
# builds 200 K * (1 - e^-0.4) = 65.9 K of heat without a fault, then ends; a second
# boost is rejected while one runs. The boosted turn and sprint finishes sooner, and
# with no Engineering input it still finishes.
func test_boost_is_short_overcharge() -> void:
	var w: SimWorld = _world()
	var b: BoostCommand = BoostCommand.new()
	b.ship_id = 0
	w.submit(b)
	w.step()
	assert_float(w.kin.thrust_scale[0]).is_equal_approx(1.5, 1e-9)
	assert_float(w.kin.torque_scale[0]).is_equal_approx(1.5, 1e-9)
	var again: BoostCommand = BoostCommand.new()
	again.ship_id = 0
	w.submit(again)
	_steps(w, 479)
	assert_int(w.command_log.size()).is_equal(1)
	assert_float(w.power.heat[0][0]).is_equal_approx(200.0 * (1.0 - exp(-0.4)), 1e-6)
	assert_array(Array(w.power.pips[0])).is_equal([2, 2, 2, 2, 2, 0])
	w.step()
	assert_float(w.kin.thrust_scale[0]).is_equal(1.0)
	assert_int(_faults(w.drain_events()).size()).is_equal(0)
	var plain: int = _turn_and_sprint(false)
	var boosted: int = _turn_and_sprint(true)
	assert_int(boosted).is_less(plain)


# FT: FT-SIM-026
# Two boosts back to back overheat the engines past 100 K: a fault.
func test_back_to_back_boosts_fault() -> void:
	var w: SimWorld = _world()
	for i: int in 2:
		var b: BoostCommand = BoostCommand.new()
		b.ship_id = 0
		w.submit(b)
		_steps(w, 480)
	var faults: Array[SimEvent] = _faults(w.drain_events())
	assert_int(faults.size()).is_equal(2)
	(
		assert_array(faults.map(func(e: SimEvent) -> String: return String(e.tag)))
		. contains_exactly(["engines", "thrusters"])
	)


# FT: FT-SIM-012
# The weapons store starts full (5 MJ), each draw takes its energy or nothing, and it
# recharges with the weapons share of the reactor: 20 MW * 2 / 12 pips.
func test_draw_energy_from_weapons_store() -> void:
	var w: SimWorld = _world()
	for i: int in 10:
		assert_bool(PowerSystem.draw_energy(w, 0, 500000.0)).is_true()
	assert_bool(PowerSystem.draw_energy(w, 0, 1.0)).is_false()
	assert_float(w.power.weapon_energy[0]).is_equal_approx(0.0, 1e-6)
	_steps(w, 60)
	assert_float(w.power.weapon_energy[0]).is_equal_approx(20e6 * 2.0 / 12.0, 1e-3)
	assert_bool(_pips(w, WPN, 0)).is_true()
	var before: float = w.power.weapon_energy[0]
	_steps(w, 60)
	assert_float(w.power.weapon_energy[0]).is_equal(before)
	assert_bool(_pips(w, WPN, 4)).is_true()
	_steps(w, 600)
	assert_float(w.power.weapon_energy[0]).is_equal(5e6)


# FT: FT-ARC-008, FT-GEN-002
# Power commands round-trip through the command codec, and a ship reset restores its
# pips, heat and store.
func test_commands_round_trip_and_reset() -> void:
	var c: SetPipsCommand = SetPipsCommand.new()
	c.subsystem_kind = THR
	c.pips = 3
	var back: SetPipsCommand = SimCommands.from_dict(c.to_dict()) as SetPipsCommand
	assert_int(back.subsystem_kind).is_equal(THR)
	assert_int(back.pips).is_equal(3)
	assert_object(SimCommands.from_dict(BoostCommand.new().to_dict())).is_instanceof(BoostCommand)
	var w: SimWorld = _world()
	assert_bool(_pips(w, ENG, 4)).is_true()
	_steps(w, 300)
	PowerSystem.draw_energy(w, 0, 1e6)
	w.reset_ship(0, 0)
	assert_array(Array(w.power.pips[0])).is_equal([2, 2, 2, 2, 2, 0])
	assert_float(w.power.heat[0][0]).is_equal(0.0)
	assert_float(w.power.weapon_energy[0]).is_equal(5e6)
