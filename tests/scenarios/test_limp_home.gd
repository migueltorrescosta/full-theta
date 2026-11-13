extends GdUnitTestSuite
## Fail-forward (gp-09, #38 D4): a crewed ship crippled in an active encounter (hull under
## RunDef.crippled_hull, or RunDef.crippled_subsystems subsystems destroyed) that docks
## anywhere within RunDef.limp_home_time has limped home: the encounter ends PARTIAL and its
## accepted card pays RunDef.partial_pay. After that time a dock is no limp home (with a hostile
## about it takes the ship out of the fight, w-ckm: tests/sim/run/test_out_of_fight.gd).


## A rescue at Vesper Beacon with the escort accepted; returns the escort card.
func _rescue(f: ScenarioFixture) -> int:
	f.begin(&"rescue", &"vesper_beacon")
	f.run(3)
	var card: int = -1
	for c: CardInfo in f.api.cards_of(0):
		if c.title_key == "comms.card.escort":
			card = c.id
	var accept: AcceptCardCommand = AcceptCardCommand.new()
	accept.card = card
	assert_bool(f.send(accept)).is_true()
	return card


func _hull_to(f: ScenarioFixture, fraction: float) -> void:
	var w: SimWorld = f.world
	w.damage.health[w.damage.hull_row(0)] = fraction * w.defs[0].hull_max


## Puts ship 0 beside Kestrel Yard at rest and docks it; whether the dock was accepted.
func _dock_at_yard(f: ScenarioFixture) -> bool:
	var w: SimWorld = f.world
	w.kin.place(0, CubePoint.plus(w.sites.point(0), Vector3(500.0, 0.0, 0.0)))
	w.kin.vel[0] = Vector3.ZERO
	var dock: DockCommand = DockCommand.new()
	dock.site_id = 0
	return f.send(dock)


## Steps once and returns that tick's events of `kind` (the fixture drains them).
func _step_events(f: ScenarioFixture, kind: StringName) -> Array[SimEvent]:
	f.world.step()
	var out: Array[SimEvent] = f.world.drain_events().filter(
		func(e: SimEvent) -> bool: return e.kind == kind
	)
	return out


# FT: FT-MIS-050, FT-MIS-021
func test_a_crippled_ship_that_docks_in_time_limps_home_on_half_pay() -> void:
	var f: ScenarioFixture = ScenarioFixture.make()
	var card: int = _rescue(f)
	var credits: int = Economy.credits(f.world, 0)
	_hull_to(f, 0.2)
	var crippled: Array[SimEvent] = _step_events(f, &"crippled")
	assert_array(crippled).has_size(1)
	assert_float(crippled[0].value).is_equal(f.world.run_def.limp_home_time)
	assert_int(f.world.ships.crippled_tick[0]).is_greater_equal(0)
	f.run(60 * 30)
	assert_bool(_dock_at_yard(f)).is_true()
	f.run(3)
	assert_int(f.api.encounter(f.encounter).result).is_equal(Scenario.Result.PARTIAL)
	assert_bool(EncounterTable.has_bit(f.world.encounters.limped_mask[f.encounter], 0)).is_true()
	assert_int(f.card_state(card)).is_equal(CardInfo.State.DONE)
	# The escort pays 400; half of it (m3_run partial_pay 0.5), with the yard's market card.
	assert_int(Economy.credits(f.world, 0)).is_equal(credits + 200)
	assert_int(f.world.ships.crippled_tick[0]).is_equal(-1)


# FT: FT-MIS-050
func test_two_destroyed_subsystems_cripple_the_ship() -> void:
	var f: ScenarioFixture = ScenarioFixture.make()
	_rescue(f)
	var w: SimWorld = f.world
	var hull: int = w.damage.hull_row(0)
	w.damage.health[hull + 1] = 0.0
	assert_array(_step_events(f, &"crippled")).is_empty()
	assert_bool(EncounterSystem.crippled(w, 0)).is_false()
	w.damage.health[hull + 2] = 0.0
	assert_array(_step_events(f, &"crippled")).has_size(1)
	# Once per encounter: still crippled, no second event.
	assert_array(_step_events(f, &"crippled")).is_empty()


# FT: FT-MIS-050
func test_after_the_limp_home_time_docking_ends_nothing() -> void:
	var f: ScenarioFixture = ScenarioFixture.make()
	_rescue(f)
	# A 1 s limp-home time, so it runs out before the raiders end the fight.
	var w: SimWorld = f.world
	var def: RunDef = w.run_def.duplicate()
	def.limp_home_time = 1.0
	w.run_def = def
	_hull_to(f, 0.2)
	assert_array(_step_events(f, &"crippled")).has_size(1)
	f.run(SimRate.ticks(1.0) + 1)
	assert_bool(_dock_at_yard(f)).is_true()
	f.run(3)
	assert_int(f.api.encounter(f.encounter).result).is_equal(Scenario.Result.ACTIVE)
	assert_int(f.world.encounters.limped_mask[f.encounter]).is_equal(0)


# FT: FT-MIS-050
func test_a_whole_ship_that_docks_has_not_limped_home() -> void:
	var f: ScenarioFixture = ScenarioFixture.make()
	_rescue(f)
	assert_bool(_dock_at_yard(f)).is_true()
	f.run(3)
	assert_int(f.api.encounter(f.encounter).result).is_equal(Scenario.Result.ACTIVE)
	assert_int(f.world.ships.crippled_tick[0]).is_equal(-1)


## A jump that a hostile saw start lands ship 0 beside the yard (as JumpSystem would: placed,
## then &"jump_arrive"; the freighter, ship 1, stands in for the hostile that saw it).
func _seen_jump_to_yard(f: ScenarioFixture) -> void:
	var w: SimWorld = f.world
	w.helm.jump_seen_by[0] = 1
	w.kin.place(0, CubePoint.plus(w.sites.point(0), Vector3(500.0, 0.0, 0.0)))
	w.kin.vel[0] = Vector3.ZERO
	w.emit(&"jump_arrive", 0, -1, 0.0, Vector3.ZERO, &"-1")
	f.tick()


# FT: FT-MIS-050, FT-MIS-015
# Limping home is a jump to a dock: a crippled ship's seen jump in time is no flee, and the
# dock that follows ends the encounter partial. The same jump by a whole ship is a flee.
func test_a_crippled_ship_jumps_to_the_yard_and_docks() -> void:
	var f: ScenarioFixture = ScenarioFixture.make()
	_rescue(f)
	var credits: int = Economy.credits(f.world, 0)
	_hull_to(f, 0.2)
	assert_array(_step_events(f, &"crippled")).has_size(1)
	_seen_jump_to_yard(f)
	assert_int(f.api.encounter(f.encounter).result).is_equal(Scenario.Result.ACTIVE)
	assert_int(f.world.encounters.fled_mask[f.encounter]).is_equal(0)
	assert_int(f.world.ships.encounter[0]).is_equal(f.encounter)
	var dock: DockCommand = DockCommand.new()
	dock.site_id = 0
	assert_bool(f.send(dock)).is_true()
	f.run(3)
	assert_int(f.api.encounter(f.encounter).result).is_equal(Scenario.Result.PARTIAL)
	assert_bool(EncounterTable.has_bit(f.world.encounters.limped_mask[f.encounter], 0)).is_true()
	assert_int(Economy.credits(f.world, 0)).is_equal(credits + 200)
	var whole: ScenarioFixture = ScenarioFixture.make()
	_rescue(whole)
	_seen_jump_to_yard(whole)
	assert_int(whole.api.encounter(whole.encounter).result).is_equal(Scenario.Result.FLED)


# FT: FT-MIS-050
# A ship crippled while already docked has not limped home: the dock must come after.
func test_a_ship_crippled_while_docked_does_not_limp_home() -> void:
	var f: ScenarioFixture = ScenarioFixture.make()
	_rescue(f)
	assert_bool(_dock_at_yard(f)).is_true()
	_hull_to(f, 0.2)
	assert_array(_step_events(f, &"crippled")).has_size(1)
	f.run(3)
	assert_int(f.api.encounter(f.encounter).result).is_equal(Scenario.Result.ACTIVE)
	assert_int(f.world.encounters.limped_mask[f.encounter]).is_equal(0)
