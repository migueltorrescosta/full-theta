extends GdUnitTestSuite
## P15 Relay + Comms pair test (spec §7.4): scenario and scripts in p15_scenario.gd. A
## mission marked by Relay is reached faster than one searched for, its card gets the mission
## icon where mission_icon allows it, and a probe's discovery opens an opportunity on
## Comms' board.

const BETTER: Dictionary = {"seconds": PairHarness.Better.LOWER}


# FT: FT-PAIR-001, FT-PAIR-004, FT-PAIR-015, FT-TST-006
# Helm flying the mark reaches the objective sooner than Helm searching the three spots by
# at least P15's pair_min_gain; the search still arrives.
func test_coop_beats_solo() -> void:
	var p15: PairDef = load("res://content/pairs/p15.tres") as PairDef
	var runs: Dictionary[String, PairHarness.Run] = P15Scenario.harness().compare(
		P15Scenario.coop, P15Scenario.solo
	)
	var failures: Array[String] = PairHarness.check(runs, BETTER, p15.pair_min_gain)
	(
		assert_array(failures)
		. override_failure_message("\n".join(failures) + "\n" + PairHarness.summary(runs))
		. is_empty()
	)


# FT: FT-PAIR-001, FT-PAIR-014
# A mission gains its mark icon once Relay marked it; Comms' card row carries the icon
# where the mission_icon shortcut is on and Relay shared it, and in a joint view with Relay
# (Ops); never on Hard, and the mark changes no rule.
func test_a_marked_mission_gains_its_icon_under_the_toggle() -> void:
	var w: SimWorld = P15Scenario.build()
	P15Scenario.environment(w)
	w.step()
	assert_bool(StoryRules.is_marked(w, 0)).is_false()
	var shown: Dictionary[String, bool] = {}
	var cases: Dictionary[String, ViewFilter] = {
		"easy shared": ViewFilter.of("comms", "easy#mission_icon"),
		"easy unshared": ViewFilter.of("comms", "easy"),
		"hard shared": ViewFilter.of("comms", "hard#mission_icon"),
		"ops": ViewFilter.of("ops", "easy"),
	}
	for name: String in cases:
		shown[name] = CommsView.block(w, 0, cases[name])["cards"][0]["marked"]
	assert_dict(shown).is_equal(
		{"easy shared": false, "easy unshared": false, "hard shared": false, "ops": false}
	)
	var mark: MarkMissionCommand = MarkMissionCommand.new()
	mark.card = 0
	assert_bool(StoryFixture.run(w, 0, mark)).is_true()
	assert_bool(StoryRules.is_marked(w, 0)).is_true()
	for name: String in cases:
		shown[name] = CommsView.block(w, 0, cases[name])["cards"][0]["marked"]
	assert_dict(shown).is_equal(
		{"easy shared": true, "easy unshared": false, "hard shared": false, "ops": true}
	)


# FT: FT-PAIR-001, FT-COM-002
# A probe that finds a contact no ship of the faction senses itself, and that can be hailed,
# opens an OPEN hail card on Comms' board, once.
func test_a_probe_discovery_opens_an_opportunity() -> void:
	var w: SimWorld = P15Scenario.discovery_world()
	var posted: Array[SimEvent] = []
	while w.tick < 90 * SimWorld.HZ and posted.is_empty():
		P15Scenario.probe(w)
		w.step()
		posted = StoryFixture.events(w, &"card_posted")
	assert_int(posted.size()).is_equal(1)
	var card: int = posted[0].other_id
	assert_int(w.story.kind[card]).is_equal(StoryTable.Kind.HAIL)
	assert_int(w.story.state[card]).is_equal(StoryTable.State.OPEN)
	assert_int(w.story.target[card]).is_equal(P15Scenario.DERELICT)
	assert_str(w.story.title[card]).is_equal("comms.card.opportunity")
	assert_float(w.kin.relative(P15Scenario.PLAYER, P15Scenario.DERELICT).length()).is_greater(
		w.defs[P15Scenario.PLAYER].sensor_range
	)
	# Answering it opens the conversation like any incoming hail.
	var answer: AnswerHailCommand = AnswerHailCommand.new()
	answer.card = card
	assert_bool(StoryFixture.run(w, 0, answer)).is_true()
	assert_str(w.story.node[card]).is_equal("n0")
	# Once: nothing more is posted while the contact stays covered.
	for i: int in 10 * SimWorld.HZ:
		w.step()
	assert_int(w.story.size()).is_equal(1)


# FT: FT-PAIR-001
# A contact the ship's own sensors hold is no discovery: no opportunity card.
func test_a_contact_in_own_sensor_range_opens_no_opportunity() -> void:
	var w: SimWorld = StoryFixture.duel()
	assert_bool(KnowledgeSystem.is_detected(w, StoryFixture.BLUE, 1)).is_true()
	assert_int(w.story.size()).is_equal(0)
