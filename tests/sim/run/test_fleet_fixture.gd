extends GdUnitTestSuite
## The M4 contract's sim fixture (#11): FleetFixture builds lobby-style worlds whose ships
## carry their slot's faction and team, and SessionRules checks the slots. Behaviour tests
## of the modes live with strand A's suites.


func test_coop_fleet_shares_one_faction() -> void:
	var f: FleetFixture = FleetFixture.make(SessionRules.Mode.COOP, 3)
	assert_object(f.world).is_not_null()
	assert_array(Array(f.ships())).is_equal([0, 1, 2])
	for id: int in f.ships():
		assert_int(f.world.faction_of(id)).is_equal(M1Encounter.PLAYER_FACTION)
		assert_int(f.world.team_of(id)).is_equal(0)
	assert_array(Array(f.api.crew_ships_of(M1Encounter.PLAYER_FACTION))).has_size(3)
	assert_bool(f.rules.is_pvp()).is_false()


func test_teams_get_one_faction_each_and_are_hostile() -> void:
	var teams: Array[int] = [0, 1, 1]
	var f: FleetFixture = FleetFixture.make(SessionRules.Mode.TEAMS, 3, teams)
	var w: SimWorld = f.world
	assert_int(w.faction_of(1)).is_equal(w.faction_of(2))
	assert_int(w.faction_of(0)).is_not_equal(w.faction_of(1))
	assert_int(w.relation(w.faction_of(0), w.faction_of(1))).is_equal(SimWorld.Relation.HOSTILE)
	assert_int(f.api.team_of(2)).is_equal(1)
	assert_int(f.api.session_mode()).is_equal(SessionRules.Mode.TEAMS)


func test_free_for_all_gives_each_ship_its_faction() -> void:
	var f: FleetFixture = FleetFixture.make(SessionRules.Mode.LAST_STANDING, 4)
	var seen: Dictionary[int, bool] = {}
	for id: int in f.ships():
		seen[f.world.faction_of(id)] = true
	assert_int(seen.size()).is_equal(4)
	assert_int(f.rules.eliminated_to).is_equal(SessionRules.Destination.SCOREBOARD)


func test_slot_rules() -> void:
	var teams: SessionRules = SessionRules.of_mode(SessionRules.Mode.TEAMS)
	var one_side: Array[int] = [0, 0]
	assert_array(teams.slot_errors(FleetFixture.slots_for(teams, 2, one_side))).is_not_empty()
	assert_array(teams.slot_errors(FleetFixture.slots_for(teams, 2))).is_empty()
	var coop: SessionRules = SessionRules.new()
	assert_array(coop.slot_errors(FleetFixture.slots_for(coop, 7))).is_not_empty()
	var race: SessionRules = SessionRules.of_mode(SessionRules.Mode.RACE)
	assert_array(race.slot_errors(FleetFixture.slots_for(race, 1))).is_not_empty()


func test_holdout_relaunch_is_asymmetric() -> void:
	var r: SessionRules = SessionRules.of_mode(SessionRules.Mode.HOLDOUT)
	assert_bool(r.relaunch_for(SessionRules.HOLDOUT_SMALL_TEAM).allows(1000)).is_true()
	var finite: RelaunchPolicy = r.relaunch_for(SessionRules.HOLDOUT_FINITE_TEAM)
	assert_bool(finite.allows(SessionRules.HOLDOUT_LIVES - 1)).is_true()
	assert_bool(finite.allows(SessionRules.HOLDOUT_LIVES)).is_false()
	assert_bool(SessionRules.new().relaunch_for(0).allows(0)).is_false()
	assert_object(RelaunchPolicy.from_dict(finite.to_dict())).is_not_null()


func test_director_stub_drives_the_fleet() -> void:
	var f: FleetFixture = FleetFixture.make(SessionRules.Mode.COOP, 2).with_director()
	f.step(5)
	assert_int(f.world.tick).is_equal(5)
	assert_bool(f.outcome().over()).is_false()
