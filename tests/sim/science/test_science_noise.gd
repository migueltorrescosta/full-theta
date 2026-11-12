extends GdUnitTestSuite
## E01: the server-side scan noise model (FT-SCI-005) and the sensor controls (FT-SCI-003).

const ME: int = 0
const FOE: int = 1


func _noise(
	dist: float = 8000.0,
	aspect: float = 0.5,
	eff: float = 1.0,
	pips: int = 2,
	is_active: bool = false,
	sweeping: bool = false,
	probe: bool = false,
	mark: bool = false
) -> float:
	return ScienceNoise.compute(
		ScienceFixture.science(), dist, aspect, eff, pips, 2, is_active, sweeping, probe, mark
	)


# FT: FT-SCI-005
# Each input moves the noise the way the spec says, one at a time.
func test_each_input_moves_noise() -> void:
	var base: float = _noise()
	assert_float(_noise(16000.0)).is_greater(base)
	assert_float(_noise(8000.0, 1.0)).is_greater(base)
	assert_float(_noise(8000.0, 0.0)).is_less(base)
	assert_float(_noise(8000.0, 0.5, 0.4)).is_greater(base)
	assert_float(_noise(8000.0, 0.5, 1.0, 3)).is_less(base)
	assert_float(_noise(8000.0, 0.5, 1.0, 1)).is_greater(base)
	assert_float(_noise(8000.0, 0.5, 1.0, 2, true)).is_less(base)
	assert_float(_noise(8000.0, 0.5, 1.0, 2, false, true)).is_less(base)
	assert_float(_noise(8000.0, 0.5, 1.0, 2, false, false, true)).is_less(base)
	assert_float(_noise(8000.0, 0.5, 1.0, 2, false, false, false, true)).is_less(base)


# FT: FT-SCI-005
# Noise stays within 0..1 however bad the inputs.
func test_noise_is_clamped() -> void:
	assert_float(_noise(1e9, 1.0, 0.0, 0)).is_equal(1.0)
	assert_float(_noise(0.0, 0.0, 1.0, 6, true, true, true, true)).is_greater_equal(0.0)


# FT: FT-SCI-005, FT-PAIR-003
# P10: sensor pips set the noise, 3 pips noise < 1 pip noise, from the live power table.
func test_sensor_pips_set_noise_in_the_world() -> void:
	var w: SimWorld = ScienceFixture.world()
	var row: int = w.damage.find_subsystem(ME, &"sensors")
	w.damage.pips[row] = 1
	var at_one: float = ScienceSystem.contact_noise(w, ME, FOE)
	w.damage.pips[row] = 3
	var at_three: float = ScienceSystem.contact_noise(w, ME, FOE)
	assert_float(at_three).is_less(at_one)


# FT: FT-SCI-005, FT-PAIR-003
# P3: range and aspect from the real ships; damaged sensors add noise.
func test_range_aspect_and_health_in_the_world() -> void:
	var near: float = ScienceSystem.contact_noise(ScienceFixture.world(3000.0), ME, FOE)
	var far: float = ScienceSystem.contact_noise(ScienceFixture.world(12000.0), ME, FOE)
	var bow_on: float = ScienceSystem.contact_noise(ScienceFixture.world(6000.0, false), ME, FOE)
	var broadside: float = ScienceSystem.contact_noise(ScienceFixture.world(6000.0, true), ME, FOE)
	assert_float(far).is_greater(near)
	assert_float(bow_on).is_greater(broadside)
	var w: SimWorld = ScienceFixture.world()
	var healthy: float = ScienceSystem.contact_noise(w, ME, FOE)
	var row: int = w.damage.find_subsystem(ME, &"sensors")
	w.damage.health[row] *= 0.5
	assert_float(ScienceSystem.contact_noise(w, ME, FOE)).is_greater(healthy)


# FT: FT-SCI-003
# Active mode lowers the scan noise; a sensor sweep lowers it for sweep_duration, then
# cools down before the next.
func test_sensor_mode_and_sweep() -> void:
	var w: SimWorld = ScienceFixture.world()
	var passive: float = ScienceSystem.contact_noise(w, ME, FOE)
	var mode: ScienceSensorModeCommand = ScienceSensorModeCommand.new()
	mode.active = true
	ScienceFixture.do(w, mode)
	var active: float = ScienceSystem.contact_noise(w, ME, FOE)
	assert_float(active).is_less(passive)
	var events: Array[SimEvent] = ScienceFixture.do(w, SensorSweepCommand.new())
	assert_array(SimFixture.of_kind(events, &"science_refused")).is_empty()
	assert_float(ScienceSystem.contact_noise(w, ME, FOE)).is_less(active)
	events = ScienceFixture.do(w, SensorSweepCommand.new())
	assert_str(SimFixture.of_kind(events, &"science_refused")[0].tag).is_equal("cooling")
	SimFixture.run(w, int(w.science_def.sweep_duration * 60.0) + 2)
	assert_float(ScienceSystem.contact_noise(w, ME, FOE)).is_equal(active)
	SimFixture.run(w, int(w.science_def.sweep_cooldown * 60.0))
	events = ScienceFixture.do(w, SensorSweepCommand.new())
	assert_array(SimFixture.of_kind(events, &"science_refused")).is_empty()
	assert_float(w.science.sweep_left[ME]).is_greater(0.0)


# FT: FT-SCI-010, FT-PAIR-003
# P3: the scan-position mark sits broadside to the contact; flying to it lowers the noise.
func test_scan_position_mark_lowers_noise() -> void:
	var w: SimWorld = ScienceFixture.world(6000.0, false)
	var before: float = ScienceSystem.contact_noise(w, ME, FOE)
	var mark: ScienceMarkCommand = ScienceMarkCommand.new()
	mark.contact = FOE
	var events: Array[SimEvent] = ScienceFixture.do(w, mark)
	assert_int(SimFixture.of_kind(events, &"scan_mark").size()).is_equal(1)
	assert_bool(ScienceSystem.at_scan_point(w, ME)).is_false()
	var t: ScienceTable = w.science
	assert_bool(t.has_scan_point(ME)).is_true()
	# Fly there: the mark is broadside to the raider, which faces the corvette.
	w.kin.place(ME, CubePoint.make(t.scan_x[ME], t.scan_y[ME], t.scan_z[ME]))
	assert_bool(ScienceSystem.at_scan_point(w, ME)).is_true()
	assert_float(ScienceSystem.contact_noise(w, ME, FOE)).is_less(before)


# FT: FT-SCI-010
# D378 (12r-27): the server moves or clears the sim's scan point with
# ScienceScanPointCommand when the crew-state scan position changes; the noise follows.
func test_scan_point_command_moves_and_clears_it() -> void:
	var w: SimWorld = ScienceFixture.world(6000.0, false)
	var t: ScienceTable = w.science
	assert_bool(t.has_scan_point(ME)).is_false()
	var move: ScienceScanPointCommand = ScienceScanPointCommand.new()
	var here: PackedFloat64Array = w.kin.point_at(ME, Vector3.ZERO)
	move.scan_x = here[0]
	move.scan_y = here[1]
	move.scan_z = here[2]
	ScienceFixture.do(w, move)
	assert_bool(move.accepted).is_true()
	assert_bool(ScienceSystem.at_scan_point(w, ME)).is_true()
	assert_bool(ScienceSystem.noise_parts(w, ME, FOE)["mark"]).is_true()
	var clear: ScienceScanPointCommand = ScienceScanPointCommand.new()
	clear.clear = true
	ScienceFixture.do(w, clear)
	assert_bool(t.has_scan_point(ME)).is_false()
	assert_bool(ScienceSystem.at_scan_point(w, ME)).is_false()
	var bad: ScienceScanPointCommand = ScienceScanPointCommand.new()
	bad.scan_x = NAN
	ScienceFixture.do(w, bad)
	assert_bool(bad.accepted).is_false()
	# The command log round-trips it (FT-ARC-008).
	var back: SimCommand = SimCommands.from_dict(move.to_dict())
	assert_bool(back is ScienceScanPointCommand).is_true()
	assert_float((back as ScienceScanPointCommand).scan_x).is_equal(here[0])
