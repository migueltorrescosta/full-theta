extends GdUnitTestSuite
## Encounter pacing (E07, FT-MIS-025, FT-MIS-027, D231): an encounter is PENDING until the
## ship arrives at its site or the arrival timeout passes, then ACTIVE; one encounter is
## open per ship; the director closes the run after RunDef.min_encounters of them, and it is won.

const TIMEOUT_S: float = 2.0


func _world(crew: int = 1) -> SimWorld:
	return ApiFixture.world(crew, ApiFixture.run_def(PackedStringArray(["s_a", "s_b"]), TIMEOUT_S))


func _begin(
	w: SimWorld, site: int, ships: PackedInt32Array = PackedInt32Array([0])
) -> BeginEncounterCommand:
	var c: BeginEncounterCommand = BeginEncounterCommand.new()
	c.scenario_id = &"s_a"
	c.site = site
	c.ships = ships
	c.cost = 3
	w.submit(c)
	w.step()
	return c


func _events(w: SimWorld, kind: StringName) -> Array[SimEvent]:
	return w.events.filter(func(e: SimEvent) -> bool: return e.kind == kind)


func _result(w: SimWorld, id: int) -> int:
	return w.encounters.result[id]


# FT: FT-MIS-025
func test_pending_until_the_ship_arrives_at_the_site() -> void:
	var w: SimWorld = _world()
	assert_bool(_begin(w, 1).accepted).is_true()
	assert_int(_result(w, 0)).is_equal(EncounterTable.Result.PENDING)
	assert_int(w.run.encounter[0]).is_equal(0)
	ApiFixture.step(w, 30)
	assert_int(_result(w, 0)).is_equal(EncounterTable.Result.PENDING)
	assert_int(w.encounters.start_tick[0]).is_equal(-1)
	# Inside the 3 km radius: ACTIVE on that step.
	ApiFixture.place(w, 0, ApiFixture.ALPHA + Vector3(2500.0, 0.0, 0.0))
	var arrival: int = w.tick
	w.step()
	assert_int(_result(w, 0)).is_equal(EncounterTable.Result.ACTIVE)
	assert_int(w.encounters.start_tick[0]).is_equal(arrival)
	var starts: Array[SimEvent] = _events(w, &"encounter_start")
	assert_array(starts).has_size(1)
	assert_int(starts[0].ship_id).is_equal(0)
	assert_str(String(starts[0].tag)).is_equal("s_a")


# FT: FT-MIS-025
func test_a_ship_outside_the_radius_does_not_start_it() -> void:
	var w: SimWorld = _world()
	_begin(w, 1)
	ApiFixture.place(w, 0, ApiFixture.ALPHA + Vector3(3500.0, 0.0, 0.0))
	ApiFixture.step(w, 20)
	assert_int(_result(w, 0)).is_equal(EncounterTable.Result.PENDING)


# FT: FT-MIS-025, FT-MIS-027
func test_the_arrival_timeout_starts_it_anyway() -> void:
	var w: SimWorld = _world()
	_begin(w, 1)
	var opened: int = w.encounters.open_tick[0]
	var timeout_ticks: int = ceili(TIMEOUT_S * SimWorld.HZ)
	while w.tick < opened + timeout_ticks:
		assert_int(_result(w, 0)).is_equal(EncounterTable.Result.PENDING)
		w.step()
	w.step()
	assert_int(_result(w, 0)).is_equal(EncounterTable.Result.ACTIVE)
	assert_int(w.encounters.start_tick[0]).is_equal(opened + timeout_ticks)


# FT: FT-MIS-025
func test_an_encounter_with_no_site_starts_at_once() -> void:
	var w: SimWorld = _world()
	_begin(w, -1)
	assert_int(_result(w, 0)).is_equal(EncounterTable.Result.ACTIVE)


# FT: FT-MIS-025
func test_one_open_encounter_per_ship() -> void:
	var w: SimWorld = _world(2)
	assert_bool(_begin(w, 1, PackedInt32Array([0])).accepted).is_true()
	# Ship 0 is in an encounter; ship 1 is free; a group with ship 0 is refused whole.
	assert_bool(_begin(w, 1, PackedInt32Array([0])).accepted).is_false()
	assert_bool(_begin(w, 1, PackedInt32Array([1, 0])).accepted).is_false()
	assert_int(w.encounters.size()).is_equal(1)
	assert_int(w.run.encounter[1]).is_equal(-1)
	assert_bool(_begin(w, 1, PackedInt32Array([1])).accepted).is_true()
	assert_int(w.encounters.size()).is_equal(2)
	# Ending the first frees ship 0 for the next.
	var end: EndEncounterCommand = EndEncounterCommand.new()
	end.encounter = 0
	end.result = EncounterTable.Result.WON
	w.submit(end)
	w.step()
	assert_bool(end.accepted).is_true()
	assert_int(w.run.encounter[0]).is_equal(-1)
	assert_int(w.run.encounters_done[0]).is_equal(1)
	assert_bool(_begin(w, 1, PackedInt32Array([0])).accepted).is_true()


# FT: FT-MIS-025
func test_begin_is_refused_for_bad_input() -> void:
	var w: SimWorld = _world()
	var c: BeginEncounterCommand = BeginEncounterCommand.new()
	c.scenario_id = &"unknown"
	c.site = 1
	c.ships = PackedInt32Array([0])
	w.submit(c)
	w.step()
	assert_bool(c.accepted).is_false()
	assert_bool(_begin(w, 9).accepted).is_false()
	assert_bool(_begin(w, 1, PackedInt32Array()).accepted).is_false()
	assert_bool(_begin(w, 1, PackedInt32Array([5])).accepted).is_false()
	assert_int(w.encounters.size()).is_equal(0)


# FT: FT-MIS-025
func test_end_encounter_stamps_the_result_and_refuses_a_second_end() -> void:
	var w: SimWorld = _world()
	_begin(w, -1)
	var end: EndEncounterCommand = EndEncounterCommand.new()
	end.encounter = 0
	end.result = EncounterTable.Result.WON
	w.submit(end)
	w.step()
	assert_int(_result(w, 0)).is_equal(EncounterTable.Result.WON)
	assert_int(w.encounters.end_tick[0]).is_greater_equal(0)
	var again: EndEncounterCommand = EndEncounterCommand.new()
	again.encounter = 0
	again.result = EncounterTable.Result.LOST
	w.submit(again)
	w.step()
	assert_bool(again.accepted).is_false()
	var ended: Array[SimEvent] = _events(w, &"encounter_end")
	assert_array(ended).has_size(1)
	assert_int(int(ended[0].value)).is_equal(EncounterTable.Result.WON)


# FT: FT-MIS-025
func test_a_destroyed_ship_loses_its_encounter() -> void:
	var w: SimWorld = _world()
	_begin(w, -1)
	w.kin.alive[0] = 0
	ApiFixture.step(w, 2)
	assert_int(_result(w, 0)).is_equal(EncounterTable.Result.LOST)
	assert_int(w.encounters.losses_mask[0]).is_equal(1)
	assert_int(w.run.encounter[0]).is_equal(-1)


# FT: FT-MIS-001, FT-MIS-025
# Q4, owner 2026-10-26: the run is won when the director closes it (CloseRunCommand), which
# the sim accepts only after RunDef.min_encounters and which wins once the ship is in none.
func test_the_run_is_won_when_the_director_closes_it_after_the_fewest_encounters() -> void:
	var run: RunDef = ApiFixture.run_def(PackedStringArray(["s_a", "s_b"]), TIMEOUT_S, 1.0, 2, 3)
	var w: SimWorld = ApiFixture.world(1, run)
	for n: int in 2:
		assert_int(w.run.outcome[0]).is_equal(RunTable.Outcome.NONE)
		_begin(w, -1)
		var close: CloseRunCommand = CloseRunCommand.new()
		close.ship = 0
		w.submit(close)
		w.step()
		# Closing needs the fewest encounters played, and an open encounter keeps the ship in.
		assert_bool(close.accepted).is_false()
		var end: EndEncounterCommand = EndEncounterCommand.new()
		end.encounter = n
		end.result = EncounterTable.Result.WON
		w.submit(end)
		w.step()
	w.step()
	assert_int(w.run.encounters_done[0]).is_equal(2)
	assert_int(w.run.outcome[0]).is_equal(RunTable.Outcome.NONE)
	var closing: CloseRunCommand = CloseRunCommand.new()
	closing.ship = 0
	w.submit(closing)
	w.step()
	w.step()
	assert_bool(closing.accepted).is_true()
	assert_int(w.run.closed[0]).is_equal(1)
	assert_int(w.run.outcome[0]).is_equal(RunTable.Outcome.WIN)
	var again: CloseRunCommand = CloseRunCommand.new()
	again.ship = 0
	w.submit(again)
	w.step()
	assert_bool(again.accepted).is_false()


# FT: FT-MIS-025
func test_no_clear_sky_win_in_a_director_run() -> void:
	# The M1 rule (every hostile gone wins) is off while a run is in progress.
	var w: SimWorld = _world()
	var enemy: int = w.spawn_enemy(TestDefs.raider_enemy(), 2, Vector3(0.0, 0.0, -5000.0))
	w.kin.alive[enemy] = 0
	ApiFixture.step(w, 3)
	assert_int(w.run.outcome[0]).is_equal(RunTable.Outcome.NONE)
