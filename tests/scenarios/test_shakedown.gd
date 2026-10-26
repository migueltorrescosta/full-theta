extends GdUnitTestSuite
## The Shakedown (FT-MIS-039, D100, D235, FT-SIM-029): no director and no elimination, a
## drone target, and a track per station whose steps end on use (a command step) or on
## Next (a client-only step); a pair's step starts once both its stations have finished.

const CORE: Dictionary = {
	"helm": ["face", "approach", "all_stop", "jump"],
	"weapons": ["aim_x", "fire", "ammo_next"],
	"engineering": ["pip_add", "dispatch_nearest", "boost"],
	"science": ["sci_scan", "sci_hack"],
	"relay": ["mark", "probe_launch", "route"],
	"comms": ["comms_open", "comms_reply_1", "accept", "comms_buy"],
}

var rig: ShakedownRig


func before_test() -> void:
	rig = ShakedownRig.new()


# FT: FT-MIS-039
func test_the_scenario_is_training_with_no_threat_and_no_director() -> void:
	var meta: ScenarioMeta = ShakedownScenario.new().meta()
	assert_array(meta.errors()).is_empty()
	assert_bool(meta.training).is_true()
	assert_bool(meta.tags.has("training")).is_true()
	assert_int(meta.threat_cost).is_equal(0)
	# The director would never pick it, and the driver opens no encounter and no site.
	var def: DirectorDef = rig.world.run_def.director
	var d: Director = Director.new(def, &"normal", [ShakedownScenario.new()], 1)
	assert_int(d.budget_left(0)).is_equal(9)
	var sites: int = rig.world.sites.size()
	rig.tick(600)
	assert_int(rig.world.encounters.size()).is_equal(0)
	assert_int(rig.world.sites.size()).is_equal(sites)
	assert_array(d.decisions()).is_empty()


# FT: FT-MIS-039
func test_a_drone_without_weapons_is_the_target() -> void:
	rig.tick(5)
	assert_int(rig.world.ship_count()).is_equal(2)
	assert_bool(rig.world.ai.is_enabled(1)).is_true()
	assert_int(rig.world.faction_of(1)).is_not_equal(rig.world.faction_of(0))
	assert_array(rig.world.defs[1].mounts).is_empty()
	# Destroyed, it is replaced.
	rig.world.kin.alive[1] = 0
	rig.world.run.status[1] = RunTable.Status.DESTROYED
	rig.tick(ScenarioApi.HZ * 2)
	assert_int(rig.world.ship_count()).is_equal(3)


# FT: FT-MIS-039, FT-SIM-029
func test_a_ship_at_hull_zero_is_reset_at_the_yard_not_eliminated() -> void:
	rig.tick(5)
	rig.world.kin.place(0, 5000.0, 0.0, 0.0)
	DamageSystem.damage_hull(rig.world, 0, 1.0e12)
	assert_int(rig.world.kin.alive[0]).is_equal(0)
	rig.tick(3)
	assert_int(rig.world.kin.alive[0]).is_equal(1)
	assert_int(rig.world.run.status[0]).is_equal(RunTable.Status.IN_PLAY)
	assert_int(rig.world.run.outcome[0]).is_equal(RunTable.Outcome.NONE)
	assert_float(DamageSystem.hull_fraction(rig.world, 0)).is_equal(1.0)
	assert_float(rig.world.kin.point_at(0, Vector3.ZERO)[0]).is_less(1000.0)
	# A run that is not training still eliminates (the rule is the training world's).
	var w: SimWorld = ApiFixture.world()
	DamageSystem.damage_hull(w, 0, 1.0e12)
	w.step()
	assert_int(w.run.status[0]).is_equal(RunTable.Status.DESTROYED)


# FT: FT-MIS-039
func test_every_station_hears_its_first_step_and_only_its_own() -> void:
	rig.tick(3)
	for station: StringName in rig.driver.stations():
		var step: TrainingStepDef = rig.driver.current(station)
		var heard: Array[SimEvent] = rig.said(step.line)
		assert_array(heard).is_not_empty()
		assert_array(heard[0].args["stations"]).is_equal([String(station)])


# FT: FT-MIS-039
func test_command_steps_end_on_use_only() -> void:
	rig.tick(3)
	assert_str(String(rig.driver.current(&"helm").intent)).is_equal("face")
	# Time, Next, another command and an unrelated Helm input do not end Face.
	rig.tick(120)
	rig.press_next(&"helm")
	rig.world.submit(rig.command_for(&"helm_all_stop"))
	rig.world.submit(rig.command_for(&"helm_input:throttle"))
	rig.tick(3)
	assert_str(String(rig.driver.current(&"helm").intent)).is_equal("face")
	# Face, from the Helm.
	rig.world.submit(rig.command_for(&"helm_input:face"))
	rig.tick(3)
	var next: TrainingStepDef = rig.driver.current(&"helm")
	assert_str(String(next.intent)).is_equal("approach")
	assert_array(rig.said(next.line)).is_not_empty()


# FT: FT-MIS-039
func test_client_only_steps_end_on_next_only() -> void:
	rig.tick(3)
	# Run Helm's track up to its first client-only step.
	while rig.driver.current(&"helm").kind == TrainingStepDef.Kind.COMMAND:
		rig.use(rig.driver.current(&"helm"))
	var step: TrainingStepDef = rig.driver.current(&"helm")
	assert_int(step.kind).is_equal(TrainingStepDef.Kind.NEXT)
	rig.world.submit(rig.command_for(&"helm_all_stop"))
	rig.world.submit(rig.command_for(&"helm_input:face"))
	rig.tick(130)
	assert_object(rig.driver.current(&"helm")).is_same(step)
	# Another station's Next is not Helm's.
	rig.press_next(&"weapons")
	assert_object(rig.driver.current(&"helm")).is_same(step)
	rig.press_next(&"helm")
	assert_object(rig.driver.current(&"helm")).is_not_same(step)


# FT: FT-MIS-039
func test_each_track_runs_at_its_own_pace_core_actions_first() -> void:
	rig.tick(3)
	for station: String in CORE:
		var track: Array[TrainingStepDef] = rig.steps.track(StringName(station))
		var core: Array = CORE[station]
		for i: int in core.size():
			assert_str(String(track[i].intent)).is_equal(core[i])
	rig.finish(&"helm")
	assert_object(rig.driver.current(&"helm")).is_null()
	assert_bool(rig.driver.finished(&"helm")).is_true()
	assert_str(String(rig.driver.current(&"weapons").intent)).is_equal("aim_x")
	assert_str(String(rig.driver.current(&"comms").intent)).is_equal("comms_open")
	assert_array(rig.said("shakedown.helm.track_done")).is_not_empty()


# FT: FT-MIS-039, FT-PAIR-012
func test_a_pair_step_starts_once_both_stations_finished() -> void:
	rig.tick(3)
	assert_array(rig.driver.active_pairs()).is_empty()
	rig.finish(&"helm")
	rig.tick(3)
	assert_array(rig.driver.active_pairs()).is_empty()
	rig.finish(&"engineering")
	rig.tick(3)
	var on: Array[TrainingStepDef] = rig.driver.active_pairs()
	assert_array(on).has_size(1)
	assert_str(String(on[0].intent)).is_equal("pair_p1")
	var heard: Array[SimEvent] = rig.said("shakedown.pair_p1")
	assert_array(heard).is_not_empty()
	assert_array(heard[0].args["stations"]).contains_exactly_in_any_order(["engineering", "helm"])
	# It ends when both press Next, not one.
	rig.press_next(&"helm")
	assert_array(rig.driver.active_pairs()).has_size(1)
	rig.press_next(&"engineering")
	assert_array(rig.driver.active_pairs()).is_empty()


# FT: FT-MIS-039
func test_every_pair_step_runs_and_the_shakedown_closes() -> void:
	rig.tick(3)
	for station: StringName in rig.driver.stations():
		rig.finish(station)
	var guard: int = 0
	while guard < 60:
		guard += 1
		for step: TrainingStepDef in rig.driver.active_pairs():
			rig.press_next(step.station)
			rig.press_next(step.partner)
		rig.tick(2)
	assert_array(rig.said("shakedown.all_done")).is_not_empty()
	for pair: TrainingStepDef in rig.steps.pairs():
		assert_array(rig.said(pair.line)).is_not_empty()


# FT: FT-MIS-039
func test_next_is_logged_and_sets_the_station_flag() -> void:
	rig.tick(2)
	rig.press_next(&"science")
	rig.press_next(&"science")
	assert_int(rig.host.api().flag(&"train.science.next")).is_equal(2)
	var logged: Array[SimCommand] = rig.world.command_log.filter(
		func(c: SimCommand) -> bool: return c.kind() == &"training_next"
	)
	assert_array(logged).has_size(2)
	assert_bool(logged[0].accepted).is_true()
	assert_array(rig.world.accepted_commands()).contains([logged[0]])
	var round: SimCommand = SimCommands.from_dict(logged[0].to_dict())
	assert_object(round).is_instanceof(TrainingNextCommand)
	assert_str(String((round as TrainingNextCommand).station)).is_equal("science")
