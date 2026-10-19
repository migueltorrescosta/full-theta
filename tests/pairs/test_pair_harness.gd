extends GdUnitTestSuite
## The pair harness itself (T039): gain is the share saved or added (D121), check()
## names each failure, and runs are deterministic and stop at the predicate or the
## tick limit. The toy scenario: a corvette throttles up; done once 500 m out.


func _harness() -> PairHarness:
	var build: Callable = func() -> SimWorld:
		var w: SimWorld = SimWorld.new(7, "harness")
		w.spawn_ship(TestDefs.corvette(), 1, 0)
		return w
	var done: Callable = func(w: SimWorld) -> bool:
		return w.kin.relative_to_point(0, 0.0, 0.0, 0.0).length() > 500.0
	var measure: Callable = func(w: SimWorld) -> Dictionary:
		return {"time": w.tick * SimWorld.DT, "speed": w.kin.vel[0].length()}
	return PairHarness.new(build, func(_w: SimWorld) -> void: pass, done, measure, 60 * 30)


func _throttle(boost: bool) -> Callable:
	return func(w: SimWorld) -> void:
		if w.tick == 0:
			var c: HelmInputCommand = HelmInputCommand.new()
			c.ship_id = 0
			c.throttle = 1.0
			w.submit(c)
			if boost:
				var b: BoostCommand = BoostCommand.new()
				b.ship_id = 0
				w.submit(b)


# FT: FT-PAIR-015
# Gains for both directions, and the zero-denominator edge.
func test_gain() -> void:
	assert_float(PairHarness.gain(8.0, 10.0, PairHarness.Better.LOWER)).is_equal_approx(0.2, 1e-12)
	assert_float(PairHarness.gain(12.5, 10.0, PairHarness.Better.HIGHER)).is_equal_approx(
		0.25, 1e-12
	)
	assert_float(PairHarness.gain(12.0, 10.0, PairHarness.Better.LOWER)).is_less(0.0)
	assert_float(PairHarness.gain(0.0, 3.0, PairHarness.Better.LOWER)).is_equal(1.0)
	assert_float(PairHarness.gain(0.0, 0.0, PairHarness.Better.LOWER)).is_equal(0.0)


# FT: FT-PAIR-004, FT-PAIR-015
# A boosted run beats a plain one; the same script twice gives the same state hash and
# metrics; check() passes a met threshold and reports a missed gain and an incomplete
# run, one readable line each.
func test_compare_and_check() -> void:
	var h: PairHarness = _harness()
	var runs: Dictionary[String, PairHarness.Run] = h.compare(_throttle(true), _throttle(false))
	var again: PairHarness.Run = h.run(_throttle(true))
	assert_str(again.state_hash).is_equal(runs.coop.state_hash)
	assert_dict(again.metrics).is_equal(runs.coop.metrics)
	assert_bool(runs.solo.completed).is_true()
	assert_int(runs.coop.ticks).is_less(runs.solo.ticks)
	var better: Dictionary = {"time": PairHarness.Better.LOWER}
	assert_array(PairHarness.check(runs, better, 0.05)).is_empty()
	var missed: Array[String] = PairHarness.check(runs, better, 2.0)
	assert_int(missed.size()).is_equal(1)
	assert_str(missed[0]).starts_with("time (lower is better): co-op ")
	var stuck: PairHarness.Run = h.run(func(_w: SimWorld) -> void: pass)
	assert_bool(stuck.completed).is_false()
	assert_int(stuck.ticks).is_equal(60 * 30)
	runs.solo = stuck
	assert_array(PairHarness.check(runs, {}, 0.25)).contains_exactly(
		["solo did not complete within 1800 ticks"]
	)
