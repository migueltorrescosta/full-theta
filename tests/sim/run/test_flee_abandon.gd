extends GdUnitTestSuite
## Fleeing and abandoning (E07, FT-MIS-015, FT-MIS-016, D233): a jump out of the encounter
## site while a hostile ship detects the ship is fleeing, at the data cost; out of sight it
## is not; the crew's abandon ends the run. JumpSystem is strand B's, so the tests emit the
## &"jump_arrive" event it will emit and place the ship where the jump would.

## Where the ship sits in the encounter, and the enemy 5 km from it (inside its sensors).
const AT_ALPHA: Vector3 = Vector3(30000.0, 0.0, 0.0)


func _world() -> SimWorld:
	var w: SimWorld = ApiFixture.world()
	ApiFixture.place(w, 0, AT_ALPHA)
	var begin: BeginEncounterCommand = BeginEncounterCommand.new()
	begin.scenario_id = &"s_a"
	begin.site = 1
	begin.ships = PackedInt32Array([0])
	begin.cost = 3
	w.submit(begin)
	w.step()
	w.step()
	assert_int(w.encounters.result[0]).is_equal(EncounterTable.Result.ACTIVE)
	return w


func _enemy_near(w: SimWorld, offset: Vector3) -> int:
	var id: int = w.spawn_enemy(TestDefs.raider_enemy(), 2, AT_ALPHA + offset)
	# Hold fire: the test is about knowledge, not combat.
	w.ai.enabled[id] = 1
	return id


func _jump_to(w: SimWorld, to: Vector3) -> void:
	ApiFixture.place(w, 0, to)
	w.emit(&"jump_arrive", 0, -1, 1.0)
	w.step()


# FT: FT-MIS-015
func test_a_jump_out_while_detected_is_fleeing_at_the_data_cost() -> void:
	var w: SimWorld = _world()
	var enemy: int = _enemy_near(w, Vector3(0.0, 0.0, -5000.0))
	# Destination 6 km from the site and still 8 km from the raider: it sees the ship go.
	_jump_to(w, AT_ALPHA + Vector3(6000.0, 0.0, 0.0))
	assert_bool(KnowledgeSystem.is_detected(w, 2, 0)).is_true()
	assert_int(w.encounters.result[0]).is_equal(EncounterTable.Result.FLED)
	assert_int(w.encounters.fled_mask[0]).is_equal(1)
	assert_int(w.encounters.losses_mask[0]).is_equal(0)
	assert_int(w.run.fled_count[0]).is_equal(1)
	assert_int(w.run.encounters_done[0]).is_equal(1)
	assert_int(w.run.encounter[0]).is_equal(-1)
	var fled: Array[SimEvent] = w.events.filter(func(e: SimEvent) -> bool: return e.kind == &"fled")
	assert_array(fled).has_size(1)
	assert_int(fled[0].other_id).is_equal(enemy)
	var cost: Array[SimEvent] = w.events.filter(func(e: SimEvent) -> bool: return e.kind == &"flee_cost")
	assert_array(cost).has_size(1)
	var def: FleeCostDef = w.run_def.flee_cost
	assert_int(int(cost[0].value)).is_equal(def.credits)
	assert_str(String(cost[0].tag)).is_equal(String(def.rep_dist))


# FT: FT-MIS-015
func test_a_jump_out_of_sight_is_not_fleeing() -> void:
	var w: SimWorld = _world()
	# The only hostile is 40 km away: out of sensor range both before and after.
	var enemy: int = _enemy_near(w, Vector3(0.0, 0.0, -40000.0))
	ApiFixture.step(w, 2)
	assert_bool(KnowledgeSystem.is_detected(w, 2, 0)).is_false()
	_jump_to(w, AT_ALPHA + Vector3(6000.0, 0.0, 0.0))
	assert_bool(KnowledgeSystem.is_detected(w, 2, 0)).is_false()
	assert_int(w.encounters.result[0]).is_equal(EncounterTable.Result.ACTIVE)
	assert_int(w.encounters.fled_mask[0]).is_equal(0)
	assert_int(w.run.fled_count[0]).is_equal(0)
	assert_int(w.run.encounter[0]).is_equal(0)
	assert_array(w.events.filter(func(e: SimEvent) -> bool: return e.kind == &"fled")).is_empty()
	assert_bool(w.kin.is_alive(enemy)).is_true()


# FT: FT-MIS-015
func test_a_jump_that_stays_at_the_site_is_not_fleeing() -> void:
	var w: SimWorld = _world()
	_enemy_near(w, Vector3(0.0, 0.0, -5000.0))
	_jump_to(w, AT_ALPHA + Vector3(1000.0, 0.0, 0.0))
	assert_int(w.encounters.result[0]).is_equal(EncounterTable.Result.ACTIVE)
	assert_int(w.run.fled_count[0]).is_equal(0)


# FT: FT-MIS-015
func test_a_friendly_neighbour_does_not_make_it_fleeing() -> void:
	var w: SimWorld = _world()
	var friend: int = _enemy_near(w, Vector3(0.0, 0.0, -5000.0))
	w.set_relation(w.faction_of(0), w.faction_of(friend), SimWorld.Relation.NEUTRAL)
	_jump_to(w, AT_ALPHA + Vector3(6000.0, 0.0, 0.0))
	assert_int(w.encounters.result[0]).is_equal(EncounterTable.Result.ACTIVE)


# FT: FT-MIS-016
func test_abandon_run_ends_the_run_and_its_encounters() -> void:
	var w: SimWorld = _world()
	var abandon: AbandonRunCommand = AbandonRunCommand.new()
	w.submit(abandon)
	w.step()
	w.step()
	assert_bool(abandon.accepted).is_true()
	assert_int(w.run.status[0]).is_equal(RunTable.Status.ABANDONED)
	assert_int(w.run.outcome[0]).is_equal(RunTable.Outcome.LOSS)
	assert_int(w.encounters.result[0]).is_equal(EncounterTable.Result.ABANDONED)
	assert_int(w.run.encounter[0]).is_equal(-1)
	assert_array(w.accepted_commands()).contains([abandon])
	assert_int(abandon.source).is_equal(SimCommand.Source.SERVER)
	# Nothing left to abandon.
	var again: AbandonRunCommand = AbandonRunCommand.new()
	w.submit(again)
	w.step()
	assert_bool(again.accepted).is_false()


# FT: FT-MIS-016
func test_abandon_run_names_no_ship_and_is_logged_for_replay() -> void:
	var w: SimWorld = ApiFixture.world(2)
	var abandon: AbandonRunCommand = AbandonRunCommand.new()
	w.submit(abandon)
	w.step()
	assert_int(w.run.status[0]).is_equal(RunTable.Status.ABANDONED)
	assert_int(w.run.status[1]).is_equal(RunTable.Status.ABANDONED)
	var decoded: SimCommand = SimCommands.from_dict(abandon.to_dict())
	assert_object(decoded).is_instanceof(AbandonRunCommand)
	assert_int(decoded.ship_id).is_equal(-1)
