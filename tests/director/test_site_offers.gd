extends GdUnitTestSuite
## Crew-chosen sites (E2, w-bzx): at the start of a quiet gap before a regular encounter the
## director offers up to DirectorDef.site_offers picks, each a different scenario at a different
## free site; the pick flag chooses the one begun when the gap ends; with no valid pick the
## director picks then as before E2. Worlds are ApiFixture's (alpha and beta open: two free sites),
## scenarios TestScenario's.

const GAP: float = 100.0


func _def(offers: int, ids: PackedStringArray = PackedStringArray(["s_a", "s_b", "s_c"])) -> RunDef:
	var run: RunDef = ApiFixture.run_def(ids, 10.0, GAP, 2, 3)
	run.director.site_offers = offers
	run.director.offer_risk = {&"s_a": 1}
	run.director.offer_reward = {&"s_b": 2}
	return run


func _catalogue() -> Array[Scenario]:
	return [
		TestScenario.make(&"s_a", 1),
		TestScenario.make(&"s_b", 2, false, 60, true),
		TestScenario.make(&"s_c", 1),
	]


func _world(run: RunDef) -> SimWorld:
	var w: SimWorld = ApiFixture.world(1, run)
	w.sites.open(w, &"beta")
	return w


func _advance(w: SimWorld, d: RunDriver, ticks: int) -> void:
	var host: ScenarioHost = ScenarioHost.new(w)
	for i: int in ticks:
		host.advance(SimWorld.DT * 1.001, d.before_tick)


func _flag(w: SimWorld, flag: StringName, value: int) -> void:
	var c: SetFlagCommand = SetFlagCommand.new()
	c.flag_name = flag
	c.value = value
	w.submit(c)


## Ends the gap now (the Ready skip) and lets the begin apply.
func _skip(w: SimWorld, d: RunDriver) -> void:
	_flag(w, Director.skip_flag(Factions.CREW), w.tick)
	_advance(w, d, 5)


## The scenario of an offer of _def's tags: s_a risk 1 pay 1, s_b 2 and 2, s_c 0 and 1.
static func _id(o: Dictionary) -> String:
	return {Vector2i(1, 1): "s_a", Vector2i(2, 2): "s_b", Vector2i(0, 1): "s_c"}.get(
		Vector2i(o["risk"], o["reward"]), "?"
	)


static func _picks(d: Director) -> Array[DirectorDecision]:
	return d.decisions().filter(
		func(x: DirectorDecision) -> bool: return x.kind == DirectorDecision.Kind.PICK_ENCOUNTER
	)


# FT: FT-MIS-025, FT-MIS-027
# The gap's offers: as many as free sites allow (two of three), distinct scenarios at distinct
# free sites, tagged from the def (unlisted: risk 2 when hostile else 0, pay 1); the pick flag
# clears. Offer 0 is what the director picks without offers, at the same site.
func test_offers_are_made_at_gap_start() -> void:
	var w: SimWorld = _world(_def(3))
	var d: Director = Director.new(w.run_def.director, &"normal", _catalogue(), 3, Factions.CREW)
	_flag(w, Director.pick_flag(Factions.CREW), 7)
	_advance(w, d, 5)
	var offers: Array[Dictionary] = d.site_offers(Factions.CREW)
	assert_int(offers.size()).is_equal(2)
	assert_int(w.story_flags.get_flag(Director.pick_flag(Factions.CREW))).is_equal(0)
	assert_str(_id(offers[0])).is_not_equal(_id(offers[1]))
	assert_int(offers[0]["site"]).is_not_equal(offers[1]["site"])
	var names: Dictionary[int, String] = {}
	for s: SiteInfo in ScenarioApi.new(w).sites():
		names[s.id] = s.name_key
	for o: Dictionary in offers:
		assert_int(o["site"]).is_not_equal(Director.HOME_SITE)
		assert_str(o["name_key"]).is_equal(names[o["site"]])
		assert_str(_id(o)).is_not_equal("?")
		assert_array(o.keys()).contains_exactly(["site", "name_key", "risk", "reward"])
	assert_array(d.site_offers(Factions.CREW + 1)).is_empty()
	# The same seed without offers picks offer 0 at its site.
	var w0: SimWorld = _world(_def(0))
	var d0: Director = Director.new(w0.run_def.director, &"normal", _catalogue(), 3, Factions.CREW)
	_advance(w0, d0, 5)
	_skip(w0, d0)
	assert_str(String(_picks(d0)[0].scenario_id)).is_equal(_id(offers[0]))
	assert_int(_picks(d0)[0].site).is_equal(offers[0]["site"])


# FT: FT-MIS-025
# With no pick the gap ends as before E2: the director picks then, by its own rule, and the log
# names no offers; the offers are gone.
func test_no_pick_picks_as_before() -> void:
	var w: SimWorld = _world(_def(3))
	var d: Director = Director.new(w.run_def.director, &"normal", _catalogue(), 3, Factions.CREW)
	_advance(w, d, 5)
	assert_int(d.site_offers(Factions.CREW).size()).is_equal(2)
	_skip(w, d)
	var pick: DirectorDecision = _picks(d)[0]
	assert_str(pick.reason_key).is_equal("director.reason.budget_fits")
	assert_bool(pick.reason_args.has("offers")).is_false()
	assert_array(d.site_offers(Factions.CREW)).is_empty()
	assert_int(w.encounters.size()).is_equal(1)


# FT: FT-MIS-028
# Offer 0 was drawn at full hull; the hull drops during the gap and nobody picks: the low-hull
# calm filter judges the hull at the gap's end, as before E2.
func test_no_pick_judges_the_hull_at_the_gap_end() -> void:
	var catalogue: Array[Scenario] = [
		TestScenario.make(&"s_h", 1, false, 60, true), TestScenario.make(&"s_c", 1)
	]
	var w: SimWorld
	var d: Director
	# A seed whose offer 0 is the hostile s_h (risk 2).
	for seed_value: int in range(1, 40):
		w = _world(_def(3, PackedStringArray(["s_h", "s_c"])))
		d = Director.new(w.run_def.director, &"normal", catalogue, seed_value, Factions.CREW)
		_advance(w, d, 5)
		if d.site_offers(Factions.CREW)[0]["risk"] == 2:
			break
	assert_int(d.site_offers(Factions.CREW)[0]["risk"]).is_equal(2)
	w.damage.health[w.damage.hull_row(0)] = w.defs[0].hull_max * 0.3
	_skip(w, d)
	assert_str(String(_picks(d)[0].scenario_id)).is_equal("s_c")
	assert_str(_picks(d)[0].reason_key).is_equal("director.reason.low_hull")


# FT: FT-MIS-025, FT-MIS-029
# The crew's pick (flag = offer + 1) is begun at its site, logged crew_pick, and its cost is
# what the budget spends; it may change during the gap.
func test_the_pick_flag_picks_the_encounter() -> void:
	var w: SimWorld = _world(_def(3))
	var d: Director = Director.new(w.run_def.director, &"normal", _catalogue(), 3, Factions.CREW)
	_advance(w, d, 5)
	var offers: Array[Dictionary] = d.site_offers(Factions.CREW)
	_flag(w, Director.pick_flag(Factions.CREW), 1)
	_advance(w, d, 2)
	_flag(w, Director.pick_flag(Factions.CREW), 2)
	_skip(w, d)
	var pick: DirectorDecision = _picks(d)[0]
	assert_str(String(pick.scenario_id)).is_equal(_id(offers[1]))
	assert_int(pick.site).is_equal(offers[1]["site"])
	assert_str(pick.reason_key).is_equal("director.reason.crew_pick")
	assert_int(pick.reason_args["pick"]).is_equal(1)
	assert_array(pick.reason_args["offers"]).is_equal([_id(offers[0]), _id(offers[1])])
	var cost: int = 2 if _id(offers[1]) == "s_b" else 1
	assert_int(d.budget_left()).is_equal(9 - cost)
	assert_int(pick.cost).is_equal(cost)


# FT: FT-MIS-025
# A pick past the offers is no pick.
func test_an_out_of_range_pick_is_no_pick() -> void:
	var w: SimWorld = _world(_def(3))
	var d: Director = Director.new(w.run_def.director, &"normal", _catalogue(), 3, Factions.CREW)
	_advance(w, d, 5)
	_flag(w, Director.pick_flag(Factions.CREW), 3)
	_skip(w, d)
	assert_str(_picks(d)[0].reason_key).is_equal("director.reason.budget_fits")
	assert_bool(_picks(d)[0].reason_args.has("offers")).is_false()


# FT: FT-MIS-027
# The picked site was taken meanwhile (by another director of the session): the encounter goes
# to another free site.
func test_a_taken_site_moves_the_pick_to_a_free_one() -> void:
	var w: SimWorld = _world(_def(3))
	var d: Director = Director.new(w.run_def.director, &"normal", _catalogue(), 3, Factions.CREW)
	var taken: Dictionary[int, bool] = {}
	d.share_sites(taken)
	_advance(w, d, 5)
	var offers: Array[Dictionary] = d.site_offers(Factions.CREW)
	taken[offers[1]["site"]] = true
	_flag(w, Director.pick_flag(Factions.CREW), 2)
	_skip(w, d)
	var pick: DirectorDecision = _picks(d)[0]
	assert_str(String(pick.scenario_id)).is_equal(_id(offers[1]))
	assert_int(pick.site).is_equal(offers[0]["site"])


# FT: FT-MIS-028
# The low-hull calm filter shapes offer 0 only: the other offers may be hostile.
func test_low_hull_shapes_only_offer_zero() -> void:
	var w: SimWorld = _world(_def(3, PackedStringArray(["s_h", "s_c"])))
	w.damage.health[w.damage.hull_row(0)] = w.defs[0].hull_max * 0.3
	var catalogue: Array[Scenario] = [
		TestScenario.make(&"s_h", 1, false, 60, true), TestScenario.make(&"s_c", 1)
	]
	var d: Director = Director.new(w.run_def.director, &"normal", catalogue, 3, Factions.CREW)
	_advance(w, d, 5)
	var offers: Array[Dictionary] = d.site_offers(Factions.CREW)
	assert_int(offers.size()).is_equal(2)
	assert_int(offers[0]["risk"]).is_equal(0)  # s_c
	assert_int(offers[1]["risk"]).is_equal(2)  # s_h, hostile and unlisted
	_skip(w, d)
	assert_str(_picks(d)[0].reason_key).is_equal("director.reason.low_hull")


# FT: FT-MIS-025, FT-MIS-027
# One free site: a single offer (the UI shows no choice); its pick still works as offer 0.
func test_one_free_site_makes_one_offer() -> void:
	var w: SimWorld = ApiFixture.world(1, _def(3))
	var d: Director = Director.new(w.run_def.director, &"normal", _catalogue(), 3, Factions.CREW)
	_advance(w, d, 5)
	assert_int(d.site_offers(Factions.CREW).size()).is_equal(1)


# FT: FT-MIS-025, FT-MIS-028
# The gap before the finale offers nothing: the finale is played at its site.
func test_the_finale_gap_has_no_offers() -> void:
	var run: RunDef = _def(3, PackedStringArray(["s_a", "s_fin"]))
	run.min_encounters = 2
	run.max_encounters = 2
	run.director.gap = 2.0
	run.director.arrival_timeout = 1.0
	run.director.finale_scenario = &"s_fin"
	run.director.finale_site = &"alpha"
	var w: SimWorld = _world(run)
	var catalogue: Array[Scenario] = [
		TestScenario.make(&"s_a", 1, false, 30), TestScenario.make(&"s_fin", 1, false, 30)
	]
	var d: Director = Director.new(run.director, &"normal", catalogue, 3, Factions.CREW)
	var host: ScenarioHost = ScenarioHost.new(w)
	var first_gap: int = -1
	var finale_gap: int = -1
	for i: int in 60 * 20:
		host.advance(SimWorld.DT * 1.001, d.before_tick)
		if w.story_flags.get_flag(Director.gap_flag(Factions.CREW)) > 0:
			var n: int = d.site_offers(Factions.CREW).size()
			if _picks(d).is_empty():
				first_gap = n
			elif _picks(d).size() == 1:
				finale_gap = maxi(finale_gap, n)
	assert_int(first_gap).is_equal(1)  # s_a alone fits: one offer
	assert_int(finale_gap).is_equal(0)
	assert_str(String(_picks(d)[1].scenario_id)).is_equal("s_fin")


# FT: FT-MIS-023, FT-MIS-025
# FleetDirector hands out its faction's Director's offers; a race has none.
func test_fleet_director_offers_and_race_has_none() -> void:
	for mode: int in [GameRules.Mode.COOP, ScenarioApi.MODE_RACE]:
		var w: SimWorld = _world(_def(3))
		var f: FleetDirector = FleetDirector.new(
			w.run_def.director, &"normal", _catalogue(), 3, mode
		)
		_advance(w, f, 5)
		var want: int = 2 if mode == GameRules.Mode.COOP else 0
		assert_int(f.site_offers(Factions.CREW).size()).is_equal(want)
		assert_array(f.site_offers(Factions.CREW + 1)).is_empty()


# FT: FT-MIS-025
# site_offers 0 or 1 (no choice): no offers, the pick flag is never written and the log names
# none.
func test_no_offers_without_site_offers() -> void:
	for n: int in [0, 1]:
		var w: SimWorld = _world(_def(n))
		var d: Director = Director.new(
			w.run_def.director, &"normal", _catalogue(), 3, Factions.CREW
		)
		_advance(w, d, 5)
		assert_array(d.site_offers(Factions.CREW)).is_empty()
		_skip(w, d)
		assert_bool(_picks(d)[0].reason_args.has("offers")).is_false()
		for c: SimCommand in w.command_log:
			if c is SetFlagCommand:
				assert_str(String((c as SetFlagCommand).flag_name)).is_not_equal(
					String(Director.pick_flag(Factions.CREW))
				)


# FT: FT-ARC-008, FT-MIS-025
# A run with a crew pick replays from its command log: the pick is a logged SetFlagCommand.
func test_a_picked_run_replays() -> void:
	var live: SimWorld = _world(_def(3))
	var d: Director = Director.new(
		live.run_def.director, &"normal", _catalogue(), 11, Factions.CREW
	)
	_advance(live, d, 5)
	var offers: Array[Dictionary] = d.site_offers(Factions.CREW)
	_flag(live, Director.pick_flag(Factions.CREW), 2)
	_skip(live, d)
	_advance(live, d, 600)
	assert_str(String(_picks(d)[0].scenario_id)).is_equal(_id(offers[1]))
	var record: CommandLog = CommandLog.from_world(live, {"run": &"test_run"})
	var round: CommandLog = CommandLog.from_text(record.to_text())
	var replayed: SimWorld = _world(_def(3))
	assert_array(Array(round.replay(replayed, live.tick))).is_empty()
	assert_int(replayed.encounters.size()).is_equal(live.encounters.size())
	assert_str(replayed.state_hash()).is_equal(live.state_hash())
