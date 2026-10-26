extends GdUnitTestSuite
## P9 Weapons + Comms pair test (spec §7.4): scenario and scripts in p9_scenario.gd.

const BETTER: Dictionary = {
	"rep_lost": PairHarness.Better.LOWER, "reward": PairHarness.Better.HIGHER
}


# FT: FT-PAIR-001, FT-PAIR-004, FT-PAIR-015, FT-TST-006
func test_coop_beats_solo() -> void:
	var p9: PairDef = load("res://content/pairs/p9.tres") as PairDef
	var runs: Dictionary[String, PairHarness.Run] = P9Scenario.harness().compare(
		P9Scenario.coop, P9Scenario.solo
	)
	var failures: Array[String] = PairHarness.check(runs, BETTER, p9.pair_min_gain)
	(
		assert_array(failures)
		. override_failure_message("\n".join(failures) + "\n" + PairHarness.summary(runs))
		. is_empty()
	)


func _surrender_params() -> Dictionary:
	return ((ConversationLibrary.load_dir()[&"conv.surrender_demand"] as Dictionary)["nodes"]["n0"]["options"][0]["effects"][0])["surrender"]


func _yes_of_hundred(left: float) -> int:
	var w: SimWorld = P9Scenario.build()
	P9Scenario.damage_engines(w, left / P9Scenario.ENGINES_LEFT)
	w.step()
	var hail: HailCommand = HailCommand.new()
	hail.target = P9Scenario.RAIDER
	StoryFixture.run(w, 0, hail)
	var yes: int = 0
	for i: int in 100:
		StoryRules.roll_surrender(w, 0, 0, _surrender_params())
		yes += int(P9Scenario.surrendering(w))
	return yes


# FT: FT-PAIR-001, FT-PAIR-015
# The chance of a surrender (data, in the conversation) is higher for a contact whose engines
# are damaged, and the rolls follow it: more yeses out of a hundred, never above the cap.
func test_prior_engine_damage_raises_the_surrender_probability() -> void:
	var w: SimWorld = P9Scenario.build()
	var params: Dictionary = _surrender_params()
	P9Scenario.damage_engines(w, 1.0 / P9Scenario.ENGINES_LEFT)
	var undamaged: float = StoryRules.surrender_chance(w, P9Scenario.RAIDER, params)
	assert_float(undamaged).is_equal_approx(float(params["base"]), 0.0001)
	var damaged: float = StoryRules.surrender_chance(P9Scenario.build(), P9Scenario.RAIDER, params)
	assert_float(damaged).is_greater(undamaged)
	assert_float(damaged).is_less_equal(float(params["cap"]))
	assert_int(_yes_of_hundred(P9Scenario.ENGINES_LEFT)).is_greater(_yes_of_hundred(1.0))


# FT: FT-PAIR-001, FT-MIS-019
# Destroying a surrendered contact costs reputation with its faction by a draw inside
# rep.destroy_surrendered's range, logs a debrief line and fails the "do not destroy"
# contract; destroying a contact that never surrendered logs nothing.
func test_destroying_a_surrendered_contact_costs_reputation_and_logs_a_line() -> void:
	var dist: RepDistDef = load("res://content/economy/rep/destroy_surrendered.tres") as RepDistDef
	var w: SimWorld = P9Scenario.build()
	var lines: Array[SimEvent] = []
	while w.tick < P9Scenario.TICK_LIMIT and not P9Scenario.done(w):
		P9Scenario.environment(w)
		P9Scenario.solo(w)
		w.step()
		lines.append_array(StoryFixture.events(w, &"surrender_killed"))
	assert_int(lines.size()).is_equal(1)
	assert_str(lines[0].tag).is_equal("debrief.surrender_killed")
	assert_float(lines[0].value).is_between(dist.lo, dist.hi)
	assert_int(w.story.state[0]).is_equal(StoryTable.State.FAILED)
	assert_bool(w.kin.is_alive(P9Scenario.RAIDER)).is_false()
	assert_float(w.reputation.value_of(P9Scenario.BLUE, P9Scenario.RED)).is_less(dist.hi)
	# Nobody asked for a surrender: the same fire destroys it without a line.
	var rude: SimWorld = P9Scenario.build()
	var none: Array[SimEvent] = []
	for i: int in P9Scenario.TICK_LIMIT:
		if i >= P9Scenario.FIRE_TICK:
			Gunnery.gun(rude, 0, Gunnery.site_point(rude, P9Scenario.RAIDER, Vector3.ZERO))
		rude.step()
		none.append_array(StoryFixture.events(rude, &"surrender_killed"))
		if not rude.kin.is_alive(P9Scenario.RAIDER):
			break
	assert_bool(rude.kin.is_alive(P9Scenario.RAIDER)).is_false()
	assert_array(none).is_empty()


# FT: FT-MIS-042, FT-PAIR-007
# The contract's flag reaches Weapons' feeds under contract_flags once Comms shares it; the
# same view on Hard, or Easy without the press, has none.
func test_flags_reach_weapons_under_the_toggle() -> void:
	var w: SimWorld = P9Scenario.build()
	P9Scenario.environment(w)
	w.step()
	P9Scenario.comms(w)
	w.step()
	P9Scenario.comms(w)
	w.step()
	P9Scenario.comms(w)
	w.step()
	var row: int = w.knowledge.row_for(P9Scenario.BLUE, P9Scenario.RAIDER)
	assert_int(w.knowledge.flag[row]).is_equal(KnowledgeTable.Flag.DISABLE)
	var seen: Dictionary[String, int] = {}
	for code: String in ["easy#contract_flags", "easy", "hard#contract_flags", "normal"]:
		var values: Dictionary = FeedsView.block(w, 0)
		ViewFilter.of("weapons", code).apply(StationViews.Section.FEEDS, values, w, 0)
		seen[code] = (values["flags"] as Array).size()
	assert_dict(seen).is_equal(
		{"easy#contract_flags": 1, "easy": 0, "hard#contract_flags": 0, "normal": 0}
	)
