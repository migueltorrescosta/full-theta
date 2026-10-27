extends GdUnitTestSuite
## FleetDirector (#11, FT-MIS-023, FT-MIS-013, owner M4-Q1, M4-Q5, M4-Q7, 2026-10-28): one
## Director per crew faction, a co-op fleet run scaled to its ship count, the race's one
## seeded encounter list at each ship's own copy of the site, and last-ship-standing raider
## waves. Worlds are FleetFixture's lobby-built m3_run worlds.

const HZ: int = SimWorld.HZ


## The fixture's world on a copy of m3_run with only enemy_wave, `encounters` encounters a
## run and short gaps and arrival timeouts, so a whole fleet run fits in a test.
static func short_run(mode: SessionRules.Mode, n: int, encounters: int) -> FleetFixture:
	var f: FleetFixture = FleetFixture.make(mode, n)
	var run: RunDef = f.setup.run_def.duplicate()
	var director: DirectorDef = run.director.duplicate()
	director.gap_s = 1.0
	director.arrival_timeout_s = 1.0
	director.spawn_site_every_s = 0.0
	run.director = director
	run.min_encounters = encounters
	run.max_encounters = encounters
	run.scenarios = PackedStringArray(["enemy_wave"])
	f.setup.run_def = run
	f.world.run_def = run
	return f.with_director()


## Steps until `done` returns true or `limit` ticks pass, destroying every AI ship as it
## appears; returns every event.
static func play(f: FleetFixture, limit: int, done: Callable) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	while f.world.tick < limit and not done.call():
		for id: int in f.world.ship_count():
			if f.world.ai.is_enabled(id) and f.world.kin.is_alive(id):
				f.kill(id)
		out.append_array(f.step(1))
	return out


static func picks(d: Array[DirectorDecision]) -> Array[DirectorDecision]:
	return d.filter(
		func(x: DirectorDecision) -> bool: return x.kind == DirectorDecision.Kind.PICK_ENCOUNTER
	)


# FT: FT-MIS-023
# The director names sim/api only, so it keeps SessionRules.Mode as ints: they match.
func test_mode_numbers_match_session_rules() -> void:
	assert_int(FleetDirector.COOP).is_equal(SessionRules.Mode.COOP)
	assert_int(FleetDirector.RACE).is_equal(SessionRules.Mode.RACE)
	assert_int(FleetDirector.LAST_STANDING).is_equal(SessionRules.Mode.LAST_STANDING)
	assert_int(FleetDirector.TEAMS).is_equal(SessionRules.Mode.TEAMS)
	assert_int(FleetDirector.HOLDOUT).is_equal(SessionRules.Mode.HOLDOUT)


# FT: FT-MIS-023, FT-MIS-013
# A co-op fleet of three is one fleet run: one Director, one encounter holding every ship,
# its raiders scaled to the ship count (enemy_wave's 2 at strength 1, times 1 + 0.5 per
# ship beyond the first: 4), and one final objective: the run closes for every ship at
# once and the session is won with all three.
func test_coop_fleet_run() -> void:
	var f: FleetFixture = short_run(SessionRules.Mode.COOP, 3, 1)
	assert_float(f.director.strength_for(3)).is_equal(2.0)
	assert_float(f.director.strength_for(1)).is_equal(1.0)
	var spawned: Array[int] = []
	var events: Array[SimEvent] = []
	while f.world.tick < 200 * HZ and not f.outcome().over():
		for id: int in f.world.ship_count():
			if f.world.ai.is_enabled(id) and f.world.kin.is_alive(id):
				if not spawned.has(id):
					spawned.append(id)
				f.kill(id)
		events.append_array(f.step(1))
	assert_object(f.director.director_for(M1Encounter.PLAYER_FACTION)).is_not_null()
	var d: Array[DirectorDecision] = f.director.decisions()
	assert_int(picks(d).size()).is_equal(1)
	assert_int(f.world.encounters.size()).is_equal(1)
	assert_array(Array(f.api.encounter(0).ships)).is_equal([0, 1, 2])
	assert_int(spawned.size()).is_equal(4)
	var out: SessionOutcome = f.outcome()
	assert_int(out.reason).is_equal(SessionOutcome.Reason.OBJECTIVE)
	assert_array(Array(out.winners)).is_equal([0, 1, 2])
	for ship: int in 3:
		assert_int(f.world.run.finish_tick[ship]).is_equal(f.world.run.finish_tick[0])


# FT: FT-MIS-023
# PvP keys the director per faction: two teams get a Director each, and each team's
# encounters hold only its own ships.
func test_teams_get_a_director_each() -> void:
	var f: FleetFixture = short_run(SessionRules.Mode.TEAMS, 4, 2)
	play(f, 60 * HZ, func() -> bool: return f.world.encounters.size() >= 2)
	var a: Director = f.director.director_for(f.world.faction_of(0))
	var b: Director = f.director.director_for(f.world.faction_of(1))
	assert_object(a).is_not_null()
	assert_object(b).is_not_null()
	assert_object(a).is_not_same(b)
	var fleets: Array = []
	for e: int in f.world.encounters.size():
		fleets.append(Array(f.api.encounter(e).ships))
	fleets.sort()
	assert_array(fleets).is_equal([[0, 2], [1, 3]])


# FT: FT-MIS-032, FT-MIS-023
# A race plays one seeded encounter list: the same scenarios in the same order and strength
# for every ship, each at its own copy of the plan's site (one site row per ship, same name,
# same offset from the ship's start site), with no adaptation to a crew.
func test_race_plays_one_list_at_own_copies() -> void:
	var f: FleetFixture = FleetFixture.make(SessionRules.Mode.RACE, 3).with_director()
	var w: SimWorld = f.world
	play(f, 400 * HZ, func() -> bool: return w.encounters.size() >= 3)
	var plan: PackedStringArray = f.director.race_plan()
	assert_int(plan.size()).is_greater_equal(f.setup.run_def.min_encounters)
	assert_int(plan.size()).is_less_equal(f.setup.run_def.max_encounters)
	var sites: Dictionary[int, bool] = {}
	for e: int in 3:
		var ev: EncounterView = f.api.encounter(e)
		assert_str(String(ev.scenario_id)).is_equal(plan[0])
		var ship: int = ev.ships[0]
		sites[ev.site] = true
		var start: int = w.ship_start_site[ship]
		var gap: Vector3 = w.sites.point3(ev.site) - w.sites.point3(start)
		var first: int = w.sites.id_of(StringName(f.director.race_sites()[0]))
		var expected: Vector3 = (
			w.sites.point3(first) - w.sites.point3(0) if first >= 0 else Vector3.INF
		)
		if first >= 0:
			for axis: int in 3:
				assert_float(w.kin.wrap(gap[axis] - expected[axis])).is_equal_approx(0.0, 1.0)
		assert_str(w.sites.name_key_of(ev.site)).is_equal("site.%s" % f.director.race_sites()[0])
		assert_int(w.encounters.cost[e]).is_equal(w.encounters.cost[0])
	assert_int(sites.size()).is_equal(3)
	# the same seed draws the same list
	var again: FleetFixture = FleetFixture.make(SessionRules.Mode.RACE, 2).with_director()
	again.step(1)
	assert_array(Array(again.director.race_plan())).is_equal(Array(plan))
	# Easy's budget fits fewer race encounters than a run needs: the plan still has enough.
	var run: RunDef = f.setup.run_def
	var easy: Director = Director.new(
		run.director, &"easy", ScenarioCatalogue.load_for(run.scenarios), 1
	)
	var keys: PackedStringArray = PackedStringArray(["vesper_beacon"])
	var limits: Vector2i = Vector2i(run.min_encounters, run.max_encounters)
	assert_int(easy.plan_race(limits, keys).size()).is_equal(run.min_encounters)


# FT: FT-MIS-033
# Last ship standing (M4-Q7): no run, but a raider wave at every surviving ship each
# raider_wave_every_s, growing by raider_wave_growth: one raider each at normal strength,
# then round(1.5) = 2; a ship out of play gets none.
func test_last_standing_raider_waves() -> void:
	var f: FleetFixture = FleetFixture.make(SessionRules.Mode.LAST_STANDING, 3).with_director()
	var every: int = ceili(f.setup.run_def.director.raider_wave_every_s * HZ)
	assert_int(every).is_greater(0)
	assert_float(f.director.wave_strength(0)).is_equal(1.0)
	assert_float(f.director.wave_strength(2)).is_equal(2.0)
	DamageSystem.damage_hull(f.world, 2, INF, -1)
	f.step(every + 2)
	assert_int(_raiders(f.world)).is_equal(2)
	for ship: int in [0, 1]:
		var near: float = INF
		for id: int in f.world.ship_count():
			if f.world.ai.is_enabled(id):
				near = minf(near, f.api.distance(ship, id))
		assert_float(near).is_less_equal(FleetDirector.RAIDER_RANGE_M + 100.0)
	f.step(every)
	assert_int(_raiders(f.world)).is_equal(2 + 4)
	var waves: Array[DirectorDecision] = f.director.decisions().filter(
		func(x: DirectorDecision) -> bool: return x.kind == DirectorDecision.Kind.RAIDER_WAVE
	)
	assert_int(waves.size()).is_equal(4)
	assert_int(f.world.encounters.size()).is_equal(0)


# FT: FT-MIS-023
# A single-ship co-op run under FleetDirector plans exactly as M3's Director did: the same
# decisions and the same world, tick for tick.
func test_single_ship_coop_matches_m3() -> void:
	var fleet: FleetFixture = FleetFixture.make(SessionRules.Mode.COOP, 1).with_director()
	var m3: FleetFixture = FleetFixture.make(SessionRules.Mode.COOP, 1)
	var run: RunDef = m3.setup.run_def
	var d: Director = Director.new(
		run.director, &"normal", ScenarioCatalogue.load_for(run.scenarios), 1
	)
	for i: int in 400 * HZ:
		fleet.step(1)
		d.before_tick(m3.api)
		m3.world.step()
	assert_str(fleet.world.state_hash()).is_equal(m3.world.state_hash())
	var a: Array = fleet.director.decisions().map(
		func(x: DirectorDecision) -> Dictionary: return x.to_dict()
	)
	var b: Array = d.decisions().map(func(x: DirectorDecision) -> Dictionary: return x.to_dict())
	assert_array(a).is_not_empty()
	assert_array(a).is_equal(b)


static func _raiders(w: SimWorld) -> int:
	var n: int = 0
	for id: int in w.ship_count():
		if w.ai.is_enabled(id):
			n += 1
	return n
