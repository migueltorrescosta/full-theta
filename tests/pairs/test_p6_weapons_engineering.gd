extends GdUnitTestSuite
## P6 Weapons + Engineering pair test (spec §7.4): scenario and scripts in
## p6_scenario.gd. §7.4's other P6 test points are covered in tests/sim: damage with
## weapon pips 3 > 1 (the energy store recharges with the weapons' pips,
## tests/sim/power/test_power.gd) and the overheat lock and its cooldown
## (tests/sim/combat/test_ordnance.gd). Zero Engineering input completing is the solo run.

const BETTER: Dictionary = {"time": PairHarness.Better.LOWER}


# FT: FT-PAIR-001, FT-PAIR-004, FT-PAIR-015, FT-TST-006
# Co-op (Engineering puts the spare pips on the weapons) beats solo (nominal pips) by P6's
# pair_min_gain on time to damage; solo completes and the co-op's heat guard keeps it
# fault-free.
func test_coop_beats_solo() -> void:
	var p6: PairDef = load("res://content/pairs/p6.tres") as PairDef
	var runs: Dictionary[String, PairHarness.Run] = P6Scenario.harness().compare(
		P6Scenario.coop, P6Scenario.solo
	)
	var failures: Array[String] = PairHarness.check(runs, BETTER, p6.pair_min_gain)
	(
		assert_array(failures)
		. override_failure_message("\n".join(failures) + "\n" + PairHarness.summary(runs))
		. is_empty()
	)
	assert_float(runs.coop.metrics.heat_faults).is_equal(0.0)


# FT: FT-PAIR-004, FT-WPN-006
# D212: the corvette's one mount, firing at its cooldown, draws more energy than two weapon
# pips recharge, so the store runs dry and the shots come at the recharge rate, not the
# cooldown's; with four pips the recharge keeps up with what the cooldown (or heat) allows.
func test_sustained_fire_from_one_mount_runs_the_store_dry() -> void:
	var weapon: WeaponDef = TestDefs.corvette().mounts[0].weapon
	var power: PowerDef = TestDefs.corvette().power
	var shots: Dictionary[String, int] = {}
	for variant: String in ["solo", "coop"]:
		var w: SimWorld = P6Scenario.build()
		var crew: Callable = P6Scenario.solo if variant == "solo" else P6Scenario.coop
		var low: float = INF
		for i: int in 10 * SimWorld.HZ:
			crew.call(w)
			w.step()
			low = minf(low, w.power.weapon_energy[P6Scenario.PLAYER])
		shots[variant] = SimFixture.of_kind(w.drain_events(), &"fired").size()
		if variant == "solo":
			assert_float(low).is_less(weapon.energy_per_shot)
	var recharge: float = power.reactor_output * 2.0 / power.reactor_pips
	var by_energy: float = (power.weapons_capacity + 10.0 * recharge) / weapon.energy_per_shot
	var by_cooldown: float = 10.0 / weapon.cooldown
	assert_float(weapon.energy_per_shot / weapon.cooldown).is_greater(recharge)
	assert_int(shots["solo"]).is_less_equal(ceili(by_energy))
	assert_float(float(shots["solo"])).is_less(0.6 * by_cooldown)
	assert_int(shots["coop"]).is_greater(shots["solo"])


# FT: FT-PAIR-015
# The same seed gives the same run (the state hash matches).
func test_runs_are_deterministic() -> void:
	var a: PairHarness.Run = P6Scenario.harness().run(P6Scenario.coop)
	var b: PairHarness.Run = P6Scenario.harness().run(P6Scenario.coop)
	assert_str(a.state_hash).is_equal(b.state_hash)
