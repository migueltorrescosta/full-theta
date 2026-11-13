# gdlint: disable=unused-argument
extends GdUnitTestSuite
## Every pair's "co-op beats solo" test and the pairs' determinism (spec §7.4, FT-PAIR-015),
## table-driven over PairCases; each scenario and its scripts live in pN_scenario.gd. The
## pairs are the 15 distinct pairs of the six crew stations, never the Captain.


# FT: FT-PAIR-001, FT-PAIR-002
# The pair ids p1 to p15 name 15 distinct pairs of two crew stations each.
func test_fifteen_pairs_of_crew_stations() -> void:
	var seen: Dictionary[String, String] = {}
	for i: int in range(1, 16):
		var id: String = "p%d" % i
		var pair: Array = CoopEvents.stations_of(id)
		assert_array(pair).override_failure_message("%s has no stations" % id).has_size(2)
		for st: String in pair:
			assert_bool(StationCatalogue.CREW.has(st)).override_failure_message(id + st).is_true()
			assert_str(st).is_not_equal("captain")
		pair.sort()
		var key: String = ",".join(pair)
		(
			assert_bool(seen.has(key))
			. override_failure_message("%s repeats %s" % [id, seen.get(key)])
			. is_false()
		)
		seen[key] = id
	assert_int(seen.size()).is_equal(15)


# FT: FT-PAIR-001, FT-PAIR-003, FT-PAIR-004, FT-PAIR-015, FT-TST-006, FT-WPN-007, FT-M1-010
# FT: FT-SIM-002
# Co-op beats solo by the pair's gain (PairHarness.min_gain) on each of its metrics, and both
# complete; then the pair's own extra assertions. A second co-op run ends in the same state
# (the same seed and scripts give the same end state).
func test_coop_beats_solo(
	id: String,
	test_parameters := [
		["p1"],
		["p2"],
		["p3"],
		["p4"],
		["p5"],
		["p6"],
		["p7"],
		["p8"],
		["p9"],
		["p10"],
		["p11"],
		["p13"],
		["p14"],
		["p15"],
	]
) -> void:
	var row: Dictionary = PairCases.of(id)
	var harness: PairHarness = row["harness"]
	var runs: Dictionary[String, PairHarness.Run] = harness.compare(row["coop"], row["solo"])
	var failures: Array[String] = PairHarness.check(runs, row["better"], PairHarness.min_gain(id))
	(
		assert_array(failures)
		. override_failure_message("\n".join(failures) + "\n" + PairHarness.summary(runs))
		. is_empty()
	)
	_extras(id, row, runs)
	# A fresh row, so no crew script carries state from the first run.
	Determinism.assert_replays(
		self, runs.coop.state_hash, func() -> String: return _coop_hash(id), id
	)


func _coop_hash(id: String) -> String:
	var row: Dictionary = PairCases.of(id)
	return (row["harness"] as PairHarness).run(row["coop"]).state_hash


# The assertions beyond the metrics' gain that a pair's test makes.
func _extras(id: String, row: Dictionary, runs: Dictionary[String, PairHarness.Run]) -> void:
	match id:
		"p1", "p6":
			# The co-op's heat guard keeps it fault-free.
			assert_float(runs.coop.metrics.heat_faults).is_equal(0.0)
		"p3":
			assert_float(runs.coop.metrics.confidence).is_greater_equal(
				runs.solo.metrics.confidence
			)
			var cap: float = ScienceFixture.science().scan_cap
			assert_float(runs.solo.metrics.scan_time).is_less(cap)
		"p7":
			# Only co-op lands weak-point hits.
			assert_float(runs.coop.metrics.weak_hits).is_greater(0.0)
			assert_float(runs.solo.metrics.weak_hits).is_equal(0.0)
		"p8":
			# The probe's track is the better one: the first missile flies on a higher-quality track.
			var coop_shots: Array[float] = row["coop_shots"]
			var solo_shots: Array[float] = row["solo_shots"]
			var gain: float = PairHarness.gain(
				coop_shots[0], solo_shots[0], PairHarness.Better.HIGHER
			)
			assert_float(gain).is_greater_equal(PairHarness.min_gain(id))
			assert_float(solo_shots[0]).is_greater_equal(StrikeScenario.FIRE_QUALITY)
		"p13":
			# A contact beyond the sensors is scanned only through the probe.
			var sensors: float = TestDefs.corvette().sensor_range
			assert_float(runs.coop.metrics.scan_range).is_greater(sensors)
			assert_float(runs.coop.metrics.scan_on_probe).is_equal(1.0)
			assert_float(runs.solo.metrics.scan_range).is_less_equal(sensors)
			assert_float(runs.solo.metrics.scan_on_probe).is_equal(0.0)
		"p14":
			assert_float(runs.solo.metrics.reputation).is_equal(0.0)
