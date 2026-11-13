extends GdUnitTestSuite
## Docking doesn't stop the encounter clock (w-ckm): in an active encounter, a crewed ship
## docked while a live hostile spawned since the encounter opened is in the fight (within its
## sensor range of it or of the site) is out of the fight.
## It leaves as fled, charged the flee cost only when a hostile sees it (D233); the rest of a
## fleet fights on, and a lone ship's encounter ends FLED. Limping home, travel legs and
## pending encounters are unchanged. Worlds are ScenarioFixture's on m3_run.

const SITE: StringName = &"vesper_beacon"


func _wave(crew: int = 1) -> ScenarioFixture:
	var f: ScenarioFixture = ScenarioFixture.make(1, crew)
	f.begin(&"enemy_wave", SITE)
	f.run(3)
	assert_int(f.ships_of(&"m1_raider").size()).is_equal(1)
	return f


## Puts `ship` beside Kestrel Yard at rest and docks it there.
func _dock_at_yard(f: ScenarioFixture, ship: int = 0) -> void:
	f.world.kin.place(ship, CubePoint.plus(f.world.sites.point(0), Vector3(500.0, 0.0, 0.0)))
	f.world.kin.vel[ship] = Vector3.ZERO
	var dock: DockCommand = DockCommand.new()
	dock.site_id = 0
	assert_bool(f.send_as(ship, dock)).is_true()


# FT: FT-MIS-025, FT-HLM-013, FT-MIS-015
func test_a_lone_ship_docked_in_a_wave_has_fled_with_no_pay() -> void:
	var f: ScenarioFixture = _wave()
	var credits: int = Economy.credits(f.world, 0)
	_dock_at_yard(f)
	f.run(2)
	assert_int(f.api.encounter(f.encounter).result).is_equal(Scenario.Result.FLED)
	assert_int(f.world.encounters.fled_mask[f.encounter]).is_equal(1)
	assert_int(f.world.encounters.limped_mask[f.encounter]).is_equal(0)
	assert_int(f.world.ships.fled_count[0]).is_equal(1)
	assert_int(f.world.ships.encounter[0]).is_equal(-1)
	assert_int(Economy.credits(f.world, 0)).is_less_equal(credits)


# FT: FT-MIS-015
# D233: the flee cost is charged only when a hostile sees the docked ship go.
func test_a_docked_ship_pays_the_flee_cost_only_when_seen() -> void:
	var seen: ScenarioFixture = _wave()
	assert_int(EncounterSystem.hostile_seeing(seen.world, 0)).is_greater_equal(0)
	var credits: int = Economy.credits(seen.world, 0)
	# A stand-in dock where the ship is, in the raider's sight.
	seen.world.helm.docked_site[0] = 0
	seen.tick()
	assert_int(seen.world.ships.fled_count[0]).is_equal(1)
	assert_int(Economy.credits(seen.world, 0)).is_equal(
		credits - seen.world.run_def.flee_cost.credits
	)
	var unseen: ScenarioFixture = _wave()
	var raider: int = unseen.ships_of(&"m1_raider")[0]
	# The raider, beyond its sensors (15 km) but within the ship's (20 km) of the site, still
	# makes the fight but sees nothing.
	unseen.world.kin.place(
		raider, CubePoint.plus(unseen.world.sites.point(unseen.site), Vector3(1.9e4, 0.0, 0.0))
	)
	unseen.run(2)
	assert_int(EncounterSystem.hostile_seeing(unseen.world, 0)).is_equal(-1)
	credits = Economy.credits(unseen.world, 0)
	unseen.world.helm.docked_site[0] = 0
	unseen.tick()
	assert_int(unseen.world.ships.fled_count[0]).is_equal(1)
	assert_int(Economy.credits(unseen.world, 0)).is_equal(credits)


# FT: FT-MIS-025, FT-HLM-013
func test_in_a_fleet_the_docked_ship_leaves_and_the_other_fights_on() -> void:
	var f: ScenarioFixture = _wave(2)
	_dock_at_yard(f, 1)
	f.run(2)
	assert_int(f.api.encounter(f.encounter).result).is_equal(Scenario.Result.ACTIVE)
	assert_int(f.world.encounters.fled_mask[f.encounter]).is_equal(1 << 1)
	assert_int(f.world.ships.encounter[1]).is_equal(-1)
	assert_int(f.world.ships.encounter[0]).is_equal(f.encounter)
	f.run(60 * 46)
	for id: int in f.ships_of(&"m1_raider"):
		f.kill(id)
	assert_int(f.run_until_end(10)).is_equal(Scenario.Result.WON)


# FT: FT-MIS-050
# A crippled ship docking inside its limp-home window still limps home: PARTIAL, not fled.
func test_limping_home_to_a_dock_is_still_partial() -> void:
	var f: ScenarioFixture = _wave()
	var w: SimWorld = f.world
	w.damage.health[w.damage.hull_row(0)] = 0.2 * w.defs[0].hull_max
	f.run(2)
	assert_int(w.ships.crippled_tick[0]).is_greater_equal(0)
	_dock_at_yard(f)
	f.run(2)
	assert_int(f.api.encounter(f.encounter).result).is_equal(Scenario.Result.PARTIAL)
	assert_bool(EncounterTable.has_bit(w.encounters.limped_mask[f.encounter], 0)).is_true()
	assert_int(w.encounters.fled_mask[f.encounter]).is_equal(0)


# FT: FT-MIS-041
# A travel leg holds only debris: docking at the yard still wins it.
func test_docking_at_the_yard_still_wins_a_debris_leg() -> void:
	var f: ScenarioFixture = ScenarioFixture.make()
	f.begin(&"debris_leg", SITE)
	f.run(3)
	_dock_at_yard(f)
	assert_int(f.run_until_end(10)).is_equal(Scenario.Result.WON)
	assert_int(f.world.encounters.fled_mask[f.encounter]).is_equal(0)
	assert_int(f.world.ships.fled_count[0]).is_equal(0)


# FT: FT-MIS-025
# A pending encounter keeps its docked crew; the arrival timeout starts it all the same, and
# with a hostile about the ship then leaves it at once.
func test_a_docked_crew_waits_out_pending_then_leaves_once_it_starts() -> void:
	var f: ScenarioFixture = ScenarioFixture.make()
	var w: SimWorld = f.world
	_dock_at_yard(f)
	f.scenario = ScenarioCatalogue.load_for(PackedStringArray(["enemy_wave"]))[0].fresh()
	f.site = w.sites.open(w, SITE)
	var begin: ApiHandle = f.api.begin_encounter(&"enemy_wave", f.site, f.ships, 0)
	w.step()
	f.encounter = begin.id()
	var at: PackedFloat64Array = CubePoint.plus(w.sites.point(f.site), Vector3(3000.0, 0.0, 0.0))
	w.spawn_npc(TestDefs.raider_enemy(), Factions.RAIDER, at)
	f.run(60)
	assert_int(f.api.encounter(f.encounter).result).is_equal(Scenario.Result.PENDING)
	assert_int(w.ships.encounter[0]).is_equal(f.encounter)
	f.run(SimRate.ticks(w.run_def.director.arrival_timeout))
	assert_int(f.api.encounter(f.encounter).result).is_equal(Scenario.Result.FLED)
	assert_int(w.ships.fled_count[0]).is_equal(1)


# FT: FT-MIS-025, FT-MIS-041
# Two encounters: a raider of the other one, spawned after this travel leg opened but far off at
# the other site, leaves a ship docked on the leg in it; one at the docked ship does not.
func test_another_encounters_hostiles_far_off_leave_a_docked_ship_in() -> void:
	var f: ScenarioFixture = ScenarioFixture.make(1, 2)
	var w: SimWorld = f.world
	f.ships = PackedInt32Array([0])
	f.begin(&"debris_leg", SITE)
	f.run(3)
	var other: int = w.sites.open(w, &"cinder_field")
	w.kin.place(1, w.sites.point(other))
	var wave: ApiHandle = f.api.begin_encounter(&"enemy_wave", other, PackedInt32Array([1]), 0)
	w.step()
	assert_int(w.ships.encounter[1]).is_equal(wave.id())
	var raider: int = w.spawn_npc(
		TestDefs.raider_enemy(),
		Factions.RAIDER,
		CubePoint.plus(w.sites.point(other), Vector3(3000.0, 0.0, 0.0))
	)
	assert_int(raider).is_greater_equal(w.encounters.npc_floor[f.encounter])
	w.helm.docked_site[0] = f.site  # a stand-in dock at the leg's start (one at the yard wins it)
	f.run(2)
	assert_int(w.ships.encounter[0]).is_equal(f.encounter)
	assert_int(w.encounters.fled_mask[f.encounter]).is_equal(0)
	w.kin.place(raider, CubePoint.plus(w.kin.point(0), Vector3(2000.0, 0.0, 0.0)))
	f.run(2)
	assert_int(w.encounters.fled_mask[f.encounter]).is_equal(1)
	assert_int(w.ships.encounter[0]).is_equal(-1)
