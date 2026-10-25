extends GdUnitTestSuite
## T036: the run reset (FT-MIS-017, FT-M1-012). The reset is M1Encounter.build() again:
## a fresh world from the same seed, build id and loaded definitions.

const HZ: int = SimWorld.HZ


func _encounter(world_seed: int) -> M1Encounter:
	return M1Encounter.new(world_seed, "test", TestDefs.corvette(), TestDefs.raider_enemy())


# FT: FT-MIS-017, FT-RLY-004
# D220: the encounter places the hazards it is given in every world it builds, and refuses
# more than HazardSystem.MAX_HAZARDS with a clear error (one bit each in HazardTable).
func test_encounter_places_hazards_and_caps_them() -> void:
	var encounter: M1Encounter = _encounter(5)
	var lib: DefLibrary = DefLibrary.new()
	encounter.hazards = lib.m1_hazards()
	assert_int(encounter.hazards.size()).is_equal(2)
	assert_object(encounter.hazards[0]).is_not_null()
	assert_object(encounter.hazards[1]).is_not_null()
	assert_int(encounter.build().hazards.size()).is_equal(2)
	var many: Array[HazardDef] = []
	for i: int in HazardSystem.MAX_HAZARDS + 1:
		many.append(encounter.hazards[0])
	encounter.hazards = many
	assert_array(encounter.validate()).has_size(1)
	assert_str(encounter.validate()[0]).contains("at most 30")
	assert_object(encounter.build()).is_null()


# FT: FT-MIS-017, FT-ARC-020, FT-GEN-010, FT-M1-012
# A full encounter fought to its outcome with the scripted crew (a win by destruction
# at tick 3189) leaves every definition's hash unchanged; the reset world (build()
# again) has the state hash of a freshly built one, not the ended world's: tick 0,
# every ship in play, no outcome, no events, no command log, and the two run the next
# 600 ticks to the same hash.
func test_reset_restores_definitions_and_state() -> void:
	var defs: Dictionary[String, Resource] = TestDefs.all_defs()
	var before: Dictionary[String, String] = TestDefs.hashes(defs)
	assert_int(before.size()).is_greater(10)
	var encounter: M1Encounter = _encounter(5)
	var world: SimWorld = encounter.build()
	var crew: ScriptedCrew = ScriptedCrew.new()
	while OutcomeSystem.encounter_outcome(world) == RunTable.Outcome.NONE and world.tick < 120 * HZ:
		crew.act(world)
		world.step()
	assert_int(OutcomeSystem.encounter_outcome(world)).is_equal(RunTable.Outcome.WIN)
	assert_dict(TestDefs.hashes(defs)).is_equal(before)
	var reset: SimWorld = encounter.build()
	var fresh: SimWorld = _encounter(5).build()
	assert_str(reset.state_hash()).is_equal(fresh.state_hash())
	assert_str(reset.state_hash()).is_not_equal(world.state_hash())
	assert_int(reset.tick).is_equal(0)
	assert_array(reset.events).is_empty()
	assert_array(reset.command_log).is_empty()
	for id: int in reset.ship_count():
		assert_int(reset.run.status[id]).is_equal(RunTable.Status.IN_PLAY)
		assert_int(reset.run.outcome[id]).is_equal(RunTable.Outcome.NONE)
		assert_object(reset.defs[id]).is_same(world.defs[id])
	var crew_a: ScriptedCrew = ScriptedCrew.new()
	var crew_b: ScriptedCrew = ScriptedCrew.new()
	for i: int in 600:
		crew_a.act(reset)
		reset.step()
		crew_b.act(fresh)
		fresh.step()
	assert_str(reset.state_hash()).is_equal(fresh.state_hash())


# FT: FT-ARC-020
# The hash helper sees a change deep inside a definition: a copy of the corvette with
# one weapon number changed (in a duplicated sub-resource) hashes differently.
func test_def_hash_sees_nested_change() -> void:
	var def: ShipDef = TestDefs.corvette().duplicate()
	var mount: MountDef = def.mounts[0].duplicate()
	mount.weapon = mount.weapon.duplicate()
	mount.weapon.damage += 1.0
	def.mounts = [mount]
	var loaded: String = TestDefs.def_hash(TestDefs.corvette())
	assert_str(TestDefs.def_hash(def)).is_not_equal(loaded)
	assert_str(TestDefs.def_hash(TestDefs.corvette().duplicate())).is_equal(loaded)
