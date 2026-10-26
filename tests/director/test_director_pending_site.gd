extends GdUnitTestSuite
## PROVISIONAL (Q23): when the director opens an encounter the crew is told where it is
## (D231): the site is revealed to the ship's faction, the ship computer says its name and a
## Comms card carries it, since the encounter starts only on arrival or after the timeout.


func _catalogue() -> Array[Scenario]:
	return [TestScenario.make(&"s_a", 4)]


# FT: FT-MIS-025, FT-MIS-027, FT-AUD-006
func test_a_pending_encounter_names_its_site_to_the_crew() -> void:
	var run: RunDef = ApiFixture.run_def(PackedStringArray(["s_a"]), 30.0, 1.0)
	var w: SimWorld = ApiFixture.world(1, run)
	var d: Director = Director.new(run.director, &"easy", _catalogue(), 3)
	var host: ScenarioHost = ScenarioHost.new(w)
	var say: SimEvent = null
	for i: int in 600:
		host.advance(SimWorld.DT * 1.001, d.before_tick)
		for e: SimEvent in w.drain_events():
			if e.kind == &"say" and say == null:
				say = e
		if say != null:
			break
	assert_object(say).is_not_null()
	assert_str(String(say.tag)).is_equal(Director.PENDING_LINE)
	var picked: DirectorDecision = null
	for dec: DirectorDecision in d.decisions():
		if dec.kind == DirectorDecision.Kind.PICK_ENCOUNTER:
			picked = dec
	assert_object(picked).is_not_null()
	var key: String = str(say.args["site"])
	assert_str(key).is_equal(w.site_names[picked.site])
	assert_bool(w.sites.is_known(picked.site, w.faction_of(0))).is_true()
	host.advance(SimWorld.DT * 3.0, d.before_tick)
	var titles: Array[String] = []
	for c: int in w.story.size():
		titles.append(w.story.title[c])
	assert_array(titles).contains([key])
	var card: int = titles.find(key)
	assert_str(w.story.detail[card]).is_equal(String(Director.PENDING_DETAIL))
	assert_int(w.story.expires_tick[card]).is_greater(w.tick)
