extends GdUnitTestSuite
## Who counts in a flee (FT-MIS-015, D233; w-fng, w-4tg): only ships spawned after the
## encounter opened can see a jump go, so a leftover raider of an older encounter (D326) makes
## no flee, least of all on a travel leg; and a crippled ship that jumped away and has not
## docked when its limp-home window ends has fled then.


## A raider left from an older encounter, 3 km from the vesper_beacon site.
func _leftover(f: ScenarioFixture) -> int:
	var site: int = f.world.sites.open(f.world, &"vesper_beacon")
	var at: PackedFloat64Array = CubePoint.plus(
		f.world.sites.point(site), Vector3(3000.0, 0.0, 0.0)
	)
	return f.world.spawn_npc(TestDefs.raider_enemy(), Factions.RAIDER, at)


# FT: FT-MIS-015, FT-MIS-041
func test_a_leftover_raider_does_not_make_a_travel_leg_jump_a_flee() -> void:
	var f: ScenarioFixture = ScenarioFixture.make()
	var old: int = _leftover(f)
	f.begin(&"debris_leg", &"vesper_beacon")
	f.run(3)
	assert_bool(KnowledgeSystem.is_detected(f.world, Factions.RAIDER, 0)).is_true()
	assert_int(EncounterSystem.hostile_seeing(f.world, 0)).is_not_equal(old)
	assert_int(EncounterSystem.hostile_seeing(f.world, 0)).is_equal(-1)
	# The jump to the yard, started in its sight, wins the leg instead.
	f.world.helm.jump_seen_by[0] = EncounterSystem.hostile_seeing(f.world, 0)
	f.world.kin.place(0, f.world.sites.point(0))
	f.world.emit(&"jump_arrive", 0, -1, 0.0, Vector3.ZERO, &"0")
	assert_int(f.run_until_end(10)).is_equal(Scenario.Result.WON)
	assert_int(f.world.encounters.fled_mask[f.encounter]).is_equal(0)
	assert_int(f.world.ships.fled_count[0]).is_equal(0)


# FT: FT-MIS-015
func test_a_raider_spawned_after_the_encounter_opened_still_sees_the_jump() -> void:
	var f: ScenarioFixture = ScenarioFixture.make()
	f.begin(&"debris_leg", &"vesper_beacon")
	var fresh: int = _leftover(f)
	f.run(3)
	assert_int(EncounterSystem.hostile_seeing(f.world, 0)).is_equal(fresh)


## A rescue with the ship crippled (0.2 hull) and a 1 s limp-home window.
func _crippled(f: ScenarioFixture) -> void:
	f.begin(&"rescue", &"vesper_beacon")
	f.run(3)
	var w: SimWorld = f.world
	var def: RunDef = w.run_def.duplicate()
	def.limp_home_time = 1.0
	w.run_def = def
	w.damage.health[w.damage.hull_row(0)] = 0.2 * w.defs[0].hull_max
	f.tick()
	assert_int(w.ships.crippled_tick[0]).is_greater_equal(0)


## Ship 0 jumps (seen by `seen_by`; ship 1 stands in for the hostile) 20 km off the site.
func _jump_away(f: ScenarioFixture, seen_by: int) -> void:
	var w: SimWorld = f.world
	w.helm.jump_seen_by[0] = seen_by
	w.kin.place(0, CubePoint.plus(w.sites.point(f.site), Vector3(20000.0, 0.0, 0.0)))
	w.kin.vel[0] = Vector3.ZERO
	w.emit(&"jump_arrive", 0, -1, 0.0, Vector3.ZERO, &"-1")
	f.tick()


# FT: FT-MIS-050, FT-MIS-015
func test_a_crippled_ship_that_jumped_away_undocked_has_fled_when_the_window_ends() -> void:
	var f: ScenarioFixture = ScenarioFixture.make()
	_crippled(f)
	var credits: int = Economy.credits(f.world, 0)
	_jump_away(f, 1)
	# Inside the window nothing is charged and the ship is still in the encounter.
	assert_int(f.world.ships.encounter[0]).is_equal(f.encounter)
	assert_int(f.world.encounters.fled_mask[f.encounter]).is_equal(0)
	assert_int(Economy.credits(f.world, 0)).is_equal(credits)
	f.run(SimRate.ticks(1.0) + 2)
	assert_int(f.world.encounters.fled_mask[f.encounter]).is_equal(1)
	assert_int(f.world.ships.fled_count[0]).is_equal(1)
	assert_int(f.world.ships.encounter[0]).is_equal(-1)
	assert_int(f.world.ships.limp_seen_by[0]).is_equal(-1)
	assert_int(Economy.credits(f.world, 0)).is_less(credits)


# FT: FT-MIS-050
func test_a_crippled_ship_that_never_jumped_stays_in_the_encounter() -> void:
	var f: ScenarioFixture = ScenarioFixture.make()
	_crippled(f)
	f.run(SimRate.ticks(1.0) + 2)
	assert_int(f.world.encounters.fled_mask[f.encounter]).is_equal(0)
	assert_int(f.world.ships.fled_count[0]).is_equal(0)


# FT: FT-MIS-050
func test_a_crippled_ship_that_jumped_unseen_pays_nothing_when_the_window_ends() -> void:
	var f: ScenarioFixture = ScenarioFixture.make()
	_crippled(f)
	_jump_away(f, -1)
	f.run(SimRate.ticks(1.0) + 2)
	assert_int(f.world.encounters.fled_mask[f.encounter]).is_equal(0)
