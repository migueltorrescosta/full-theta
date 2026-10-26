extends GdUnitTestSuite

func test_probe() -> void:
	var w: SimWorld = P9Scenario.build()
	for i: int in 1800:
		P9Scenario.environment(w)
		P9Scenario.solo(w)
		w.step()
		if i % 120 == 0:
			print("T ", i, " hull ", DamageSystem.hull_fraction(w, 1), " shield ", w.shields.strength[1] if w.shields.get("strength") != null else "?", " energy ", w.power.weapon_energy[0], " intent ", w.knowledge.intent[w.knowledge.row_for(1,1)] if w.knowledge.row_for(1,1) >= 0 else -1)
	assert_bool(true).is_true()
