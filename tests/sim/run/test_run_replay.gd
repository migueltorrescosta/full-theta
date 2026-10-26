extends GdUnitTestSuite
## A director run replays from the command log alone (E07, FT-ARC-008): the log holds every
## SERVER command the director queued (spawns, site opens, encounters), so a fresh world
## fed the log reaches the same tick and state hash, with neither the director nor the
## scenarios (FT-DAT-009).

const TICKS: int = 1500


func _drive(w: SimWorld) -> Director:
	var catalogue: Array[Scenario] = [
		TestScenario.make(&"s_a", 2, true, 90), TestScenario.make(&"s_b", 3, true, 60)
	]
	var d: Director = Director.new(w.run_def.director, &"normal", catalogue, 11)
	d.encounters_per_run = 2
	var host: ScenarioHost = ScenarioHost.new(w)
	for i: int in TICKS:
		host.advance(SimWorld.DT * 1.001, d.before_tick)
	return d


func _fresh() -> SimWorld:
	return ApiFixture.world(1, ApiFixture.run_def(PackedStringArray(["s_a", "s_b"]), 2.0, 1.0))


# FT: FT-ARC-008
func test_a_director_run_replays_from_its_command_log() -> void:
	var live: SimWorld = _fresh()
	var director: Director = _drive(live)
	var kinds: Dictionary[StringName, int] = {}
	for c: SimCommand in live.command_log:
		kinds[c.kind()] = kinds.get(c.kind(), 0) + 1
	# The run did something worth replaying.
	assert_int(kinds.get(&"begin_encounter", 0)).is_greater_equal(1)
	assert_int(kinds.get(&"spawn_ship", 0)).is_greater_equal(1)
	assert_int(kinds.get(&"end_encounter", 0)).is_greater_equal(1)
	assert_int(kinds.get(&"open_site", 0)).is_greater_equal(1)
	assert_int(director.decisions().size()).is_greater_equal(2)
	var record: CommandLog = CommandLog.from_world(live, {"run": &"test_run"})
	var round: CommandLog = CommandLog.from_text(record.to_text())
	assert_object(round).is_not_null()
	var replayed: SimWorld = _fresh()
	var problems: PackedStringArray = round.replay(replayed, live.tick)
	assert_array(Array(problems)).is_empty()
	assert_int(replayed.tick).is_equal(live.tick)
	assert_int(replayed.ship_count()).is_equal(live.ship_count())
	assert_int(replayed.encounters.size()).is_equal(live.encounters.size())
	assert_str(replayed.state_hash()).is_equal(live.state_hash())


# FT: FT-ARC-008
func test_the_same_seed_and_director_give_the_same_run() -> void:
	var a: SimWorld = _fresh()
	var b: SimWorld = _fresh()
	_drive(a)
	_drive(b)
	assert_str(a.state_hash()).is_equal(b.state_hash())
