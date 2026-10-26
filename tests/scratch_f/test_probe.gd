extends GdUnitTestSuite

func test_probe() -> void:
	for r: int in [-1, 0, 1, 2, 3]:
		var run: PairHarness.Run = BluffScenario.harness().run(BluffScenario.crew(r))
		print("RUN ", r, " ", run.completed, " ", run.ticks, " ", run.metrics)
	assert_bool(true).is_true()
