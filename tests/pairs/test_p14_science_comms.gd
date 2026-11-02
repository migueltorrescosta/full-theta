extends GdUnitTestSuite
## P14 Science + Comms pair test (spec §7.4): scenario and scripts in p14_scenario.gd.


# FT: FT-PAIR-001, FT-COM-007
# "Call the bluff" is in the reply list from the start but locked, and only a cargo scan
# opens it; the scan shows as the Science icon on it (verify_chip, shared) and the pair's
# cooperative event is counted when Comms chooses it.
func test_the_option_exists_only_after_a_cargo_scan() -> void:
	var w: SimWorld = P14Scenario.build()
	var crew: Callable = P14Scenario.coop_crew()
	var share: ViewFilter = ViewFilter.of("comms", "easy#verify_chip")
	var unlocked_at: int = -1
	var locked_icon: bool = false
	while w.tick < P14Scenario.TICK_LIMIT and not P14Scenario.done(w):
		crew.call(w)
		w.step()
		var o: Dictionary = P14Scenario.option(w, &"o3")
		if o.is_empty():
			continue
		if not o["enabled"]:
			assert_int(unlocked_at).is_equal(-1)
			assert_bool(o["verify"]).is_true()
			var row: Dictionary = CommsView.block(w, 0, share)["nodes"][0]["options"][2]
			assert_bool(row["verify"]).override_failure_message("icon").is_true()
			assert_bool(row["enabled"]).is_false()
			var hidden: Dictionary = CommsView.block(w, 0, ViewFilter.of("comms", "easy"))
			assert_bool(hidden["nodes"][0]["options"][2]["verify"]).is_false()
			locked_icon = true
		elif unlocked_at < 0:
			unlocked_at = w.tick
	assert_bool(locked_icon).is_true()
	assert_int(unlocked_at).is_greater(BluffScenario.HAIL_TICK)
	assert_bool(Story.knows_fact(w, BluffScenario.BLUE, BluffScenario.TRADER, "cargo")).is_true()
	assert_bool(BluffScenario.bluffing(w)).is_true()
	var picked: Array[SimEvent] = StoryFixture.events(w, &"scan_option")
	assert_int(picked.size()).is_equal(1)
	assert_str(picked[0].tag).is_equal("cargo")


# FT: FT-PAIR-001, FT-MIS-019
# Choosing the option yields the scripted outcome distribution (rep.call_bluff): over many
# seeds every change is inside its range, the mean is near its mode, and they differ.
func test_calling_the_bluff_draws_from_its_distribution() -> void:
	var dist: RepDistDef = load("res://content/economy/rep/call_bluff.tres") as RepDistDef
	var draws: Array[float] = []
	for seed_value: int in 60:
		var w: SimWorld = StoryFixture.duel(seed_value)
		var hail: HailCommand = HailCommand.new()
		hail.target = 1
		assert_bool(StoryFixture.run(w, 0, hail)).is_true()
		Story.learn_fact(w, StoryFixture.BLUE, 1, "cargo")
		var reply: ReplyCommand = ReplyCommand.new()
		reply.card = 0
		reply.option = &"o3"
		assert_bool(StoryFixture.run(w, 0, reply)).is_true()
		draws.append(w.reputation.value_of(StoryFixture.BLUE, StoryFixture.RED))
	var mean: float = 0.0
	for d: float in draws:
		assert_float(d).is_between(dist.lo, dist.hi)
		mean += d / draws.size()
	assert_float(mean).is_equal_approx(dist.mode, 1.5)
	assert_float(draws.max() - draws.min()).is_greater(1.0)
