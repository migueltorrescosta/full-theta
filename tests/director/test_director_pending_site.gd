extends GdUnitTestSuite
## PROVISIONAL (Q23, owner 2026-10-26): when the director opens an encounter, only a Comms
## card names its site (D231), since the encounter starts only on arrival or after the
## timeout. The ship computer says nothing; the card informs and can't be accepted; the site
## is revealed to the ship's faction so Helm can select it and jump to it.


func _catalogue() -> Array[Scenario]:
	return [TestScenario.make(&"s_a", 4)]


# FT: FT-MIS-025, FT-MIS-027, FT-COM-003
func test_a_pending_encounter_is_named_by_an_information_card_only() -> void:
	var run: RunDef = ApiFixture.run_def(PackedStringArray(["s_a"]), 30.0, 1.0)
	var w: SimWorld = ApiFixture.world(1, run)
	var d: Director = Director.new(run.director, &"easy", _catalogue(), 3)
	var host: ScenarioHost = ScenarioHost.new(w)
	var says: Array[SimEvent] = []
	for i: int in 600:
		host.advance(SimWorld.DT * 1.001, d.before_tick)
		says.append_array(SimFixture.of_kind(w.drain_events(), &"say"))
		if w.story.size() > 0:
			break
	assert_int(w.story.size()).is_equal(1)
	assert_array(says).is_empty()
	var picked: DirectorDecision = null
	for dec: DirectorDecision in d.decisions():
		if dec.kind == DirectorDecision.Kind.PICK_ENCOUNTER:
			picked = dec
	assert_object(picked).is_not_null()
	assert_bool(w.sites.is_known(picked.site, w.faction_of(0))).is_true()
	var card: int = 0
	assert_str(w.story.title[card]).is_equal(w.sites.name_key_of(picked.site))
	assert_str(w.story.detail[card]).is_equal(String(Director.PENDING_DETAIL))
	assert_int(w.story.kind[card]).is_equal(StoryTable.Kind.INFO)
	assert_int(w.story.expires_tick[card]).is_greater(w.tick)
	# It informs and can't be accepted.
	var accept: AcceptCardCommand = AcceptCardCommand.new()
	accept.ship_id = 0
	accept.card = card
	w.submit(accept)
	w.step()
	assert_bool(accept.accepted).is_false()
	assert_int(w.story.state[card]).is_equal(StoryTable.State.OPEN)
