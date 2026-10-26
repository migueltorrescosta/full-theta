extends GdUnitTestSuite

func test_probe() -> void:
	var w: SimWorld = P15Scenario.build()
	for i: int in 30000:
		P15Scenario.environment(w)
		P15Scenario.coop(w)
		w.step()
		if i % 1500 == 0:
			print("T ", i, " d ", w.kin.relative_to_point(0, P15Scenario.TRUTH.x, P15Scenario.TRUTH.y, P15Scenario.TRUTH.z).length(), " sp ", w.helm.throttle_setpoint[0], " tk ", w.helm.target_kind[0], " marked ", StoryRules.is_marked(w, 0))
	assert_bool(true).is_true()
