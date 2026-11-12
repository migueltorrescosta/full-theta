extends GdUnitTestSuite
## The M4 contract's sim fixture (#11): FleetFixture builds lobby-style worlds whose ships
## carry the faction their slot's team maps to, and GameRules checks the slots. Behaviour tests
## of the modes live with strand A's suites.


func test_coop_fleet_shares_one_faction() -> void:
	var f: FleetFixture = FleetFixture.make(GameRules.Mode.COOP, 3)
	assert_object(f.world).is_not_null()
	assert_array(Array(f.ships())).is_equal([0, 1, 2])
	for id: int in f.ships():
		assert_int(f.world.faction_of(id)).is_equal(M1Encounter.PLAYER_FACTION)
	assert_array(Array(f.api.crew_ships_of(M1Encounter.PLAYER_FACTION))).has_size(3)
	assert_bool(f.rules.is_pvp()).is_false()


func test_teams_get_one_faction_each_and_are_hostile() -> void:
	var teams: Array[int] = [0, 1, 1]
	var f: FleetFixture = FleetFixture.make(GameRules.Mode.TEAMS, 3, teams)
	var w: SimWorld = f.world
	assert_int(w.faction_of(1)).is_equal(w.faction_of(2))
	assert_int(w.faction_of(0)).is_not_equal(w.faction_of(1))
	assert_int(w.relation(w.faction_of(0), w.faction_of(1))).is_equal(SimWorld.Relation.HOSTILE)
	assert_int(f.api.faction_of(2)).is_equal(f.rules.faction_for(2, 1))
	assert_int(f.api.game_mode()).is_equal(GameRules.Mode.TEAMS)


func test_free_for_all_gives_each_ship_its_faction() -> void:
	var f: FleetFixture = FleetFixture.make(GameRules.Mode.LAST_STANDING, 4)
	var seen: Dictionary[int, bool] = {}
	for id: int in f.ships():
		seen[f.world.faction_of(id)] = true
	assert_int(seen.size()).is_equal(4)
	assert_int(f.rules.eliminated_to).is_equal(GameRules.Destination.SCOREBOARD)


func test_slot_rules() -> void:
	var teams: GameRules = GameRules.of_mode(GameRules.Mode.TEAMS)
	var one_side: Array[int] = [0, 0]
	assert_array(teams.slot_errors(FleetFixture.slots_for(teams, 2, one_side))).is_not_empty()
	assert_array(teams.slot_errors(FleetFixture.slots_for(teams, 2))).is_empty()
	var coop: GameRules = GameRules.new()
	assert_array(coop.slot_errors(FleetFixture.slots_for(coop, 7))).is_not_empty()
	var race: GameRules = GameRules.of_mode(GameRules.Mode.RACE)
	assert_array(race.slot_errors(FleetFixture.slots_for(race, 1))).is_not_empty()


func test_holdout_relaunch_is_asymmetric() -> void:
	var r: GameRules = GameRules.of_mode(GameRules.Mode.HOLDOUT)
	var small: int = r.faction_for(0, GameRules.HOLDOUT_SMALL_TEAM)
	assert_bool(r.relaunch_for(small).allows(1000)).is_true()
	var finite: RelaunchPolicy = r.relaunch_for(r.holdout_finite_faction())
	assert_bool(finite.allows(GameRules.HOLDOUT_LIVES - 1)).is_true()
	assert_bool(finite.allows(GameRules.HOLDOUT_LIVES)).is_false()
	assert_bool(GameRules.new().relaunch_for(0).allows(0)).is_false()


func test_director_stub_drives_the_fleet() -> void:
	var f: FleetFixture = FleetFixture.make(GameRules.Mode.COOP, 2).with_director()
	f.step(5)
	assert_int(f.world.tick).is_equal(5)
	assert_bool(f.outcome().over()).is_false()
