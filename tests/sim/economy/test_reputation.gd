extends GdUnitTestSuite
## Reputation (strand C): changes drawn from seeded, data-defined distributions, one per
## interaction type, with the range shown where the data says so.

const BLUE: int = StoryFixture.BLUE
const RED: int = StoryFixture.RED


func _dist(id: StringName) -> RepDistDef:
	return StoryFixture.content()["rep_dists"][id]


func _draws(world_seed: int, id: StringName, n: int) -> Array[float]:
	var w: SimWorld = StoryFixture.world(world_seed)
	var out: Array[float] = []
	for i: int in n:
		out.append(Reputation.draw(w, _dist(id)))
	return out


# FT: FT-MIS-019, FT-DAT-010
# The same seed gives the same draws, another seed other draws, and the sequence is the
# "reputation" stream's alone.
func test_seeded_draws_reproduce() -> void:
	var a: Array[float] = _draws(5, &"rep.accept_contract", 20)
	assert_array(a).is_equal(_draws(5, &"rep.accept_contract", 20))
	assert_array(a).is_not_equal(_draws(6, &"rep.accept_contract", 20))
	var w: SimWorld = StoryFixture.world(5)
	w.rng.stream(&"faults").randf()
	assert_float(Reputation.draw(w, _dist(&"rep.accept_contract"))).is_equal(a[0])


# FT: FT-MIS-019, FT-DAT-010
# Each interaction type has its own distribution from data: draws stay in its range and
# their means follow its shape.
func test_distributions_per_interaction() -> void:
	var expect: Dictionary = {
		&"rep.accept_contract": [2.0, 10.0, (2.0 + 10.0 + 5.0) / 3.0],
		&"rep.complete_mission": [4.0, 12.0, 8.0],
		&"rep.complete_mission.fail": [-10.0, -3.0, -6.5],
		&"rep.call_bluff": [-5.0, 15.0, 6.0],
	}
	for id: StringName in expect:
		var draws: Array[float] = _draws(11, id, 2000)
		var sum: float = 0.0
		for d: float in draws:
			assert_float(d).is_between(expect[id][0], expect[id][1])
			sum += d
		assert_float(sum / draws.size()).override_failure_message(String(id)).is_equal_approx(
			expect[id][2], 0.35
		)
	assert_array(_draws(11, &"rep.accept_contract", 50)).is_not_equal(
		_draws(11, &"rep.complete_mission", 50)
	)


# FT: FT-MIS-020, FT-COM-005
# Comms gets the range of a change only where the data marks it visible.
func test_visible_ranges() -> void:
	var w: SimWorld = StoryFixture.world()
	assert_array(Reputation.visible_range(w, &"rep.accept_contract")).is_equal([2.0, 10.0])
	assert_array(Reputation.visible_range(w, &"rep.call_bluff")).is_empty()
	assert_array(Reputation.visible_range(w, &"rep.nothing")).is_empty()


# FT: FT-MIS-018, FT-MIS-019
# A change adds to the faction's standing with the other faction, clamps at the table's
# bounds, and is reported; an unknown distribution changes nothing and draws nothing.
func test_changes_apply_per_faction() -> void:
	var w: SimWorld = StoryFixture.world(3)
	StoryFixture.spawn(w, TestDefs.corvette(), BLUE)
	var before: Array = w.rng.states()
	assert_float(Reputation.change(w, 0, BLUE, RED, &"rep.nothing")).is_equal(0.0)
	assert_array(w.rng.states()).is_equal(before)
	var delta: float = Reputation.change(w, 0, BLUE, RED, &"rep.accept_contract")
	assert_float(w.reputation.value_of(BLUE, RED)).is_equal_approx(delta, 0.001)
	assert_float(w.reputation.value_of(RED, BLUE)).is_equal(0.0)
	assert_float(w.reputation.value_of(BLUE, 9)).is_equal(0.0)
	var events: Array[SimEvent] = StoryFixture.events(w, &"rep_changed")
	assert_int(events.size()).is_equal(1)
	assert_float(events[0].value).is_equal(delta)
	for i: int in 40:
		Reputation.apply(w, BLUE, RED, 50.0)
	assert_float(w.reputation.value_of(BLUE, RED)).is_equal(ReputationTable.MAX)
	for i: int in 40:
		Reputation.apply(w, BLUE, RED, -50.0)
	assert_float(w.reputation.value_of(BLUE, RED)).is_equal(ReputationTable.MIN)


# FT: FT-DAT-010, FT-DAT-002
# Distributions are data and validate: unknown kinds, inverted ranges and a mode outside
# the range fail.
func test_distribution_validation() -> void:
	for d: RepDistDef in StoryFixture.content()["rep_dists"].values():
		assert_array(d.validate()).is_empty()
	var bad: RepDistDef = _dist(&"rep.call_bluff").duplicate()
	bad.kind = &"loaded"
	bad.lo = 5.0
	bad.hi = 1.0
	assert_int(bad.validate().size()).is_equal(2)
	bad.kind = &"triangular"
	bad.lo = 0.0
	bad.hi = 4.0
	bad.mode = 9.0
	assert_array(bad.validate()).contains_exactly(["mode: must be in [0.0, 4.0], got 9.0"])
