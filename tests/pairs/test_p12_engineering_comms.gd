extends GdUnitTestSuite
## P12 Engineering + Comms pair test (spec §7.4, D57, D68, FT-PAIR-010): scenario and scripts
## in p12_scenario.gd. Exempt from "co-op beats solo" (FT-PAIR-015): what Comms buys must
## reach Engineering's COND, an infeasible offer can be accepted and failing it costs
## reputation within its range, and Comms has the hull band only.


func _ready_world() -> SimWorld:
	var w: SimWorld = P12Scenario.build()
	P12Scenario.environment(w)
	w.step()
	return w


# FT: FT-PAIR-004, FT-PAIR-015, FT-PAIR-011
# Parts Comms buys appear in Engineering's spares at once, and the credits are Comms' to
# spend.
func test_parts_comms_buys_reach_engineerings_spares() -> void:
	var w: SimWorld = _ready_world()
	var hull: int = w.damage.hull_row(P12Scenario.PLAYER)
	var before: int = w.damage.spare_parts[hull]
	assert_bool(P12Scenario.buy(w, &"parts", 5)).is_true()
	assert_int(w.damage.spare_parts[hull]).is_equal(before + 5)
	assert_int(Economy.held(w, P12Scenario.PLAYER, &"parts")).is_equal(before + 5)
	assert_int(Economy.credits(w, P12Scenario.PLAYER)).is_equal(P12Scenario.CREDITS - 5 * 25)


# FT: FT-PAIR-004, FT-PAIR-015
# A dock repair Comms buys clears the engines' fault and restores their health.
func test_a_dock_repair_comms_buys_clears_the_fault() -> void:
	var w: SimWorld = _ready_world()
	var row: int = w.damage.find_subsystem(P12Scenario.PLAYER, &"engines")
	assert_str(w.damage.fault_cause[row]).is_equal("coolant_leak")
	assert_bool(P12Scenario.buy(w, &"repair:engines")).is_true()
	assert_str(w.damage.fault_cause[row]).is_equal("")
	var index: int = row - w.damage.hull_row(P12Scenario.PLAYER) - 1
	assert_float(w.damage.health[row]).is_equal(
		w.defs[P12Scenario.PLAYER].subsystems[index].health_max
	)
	assert_int(Economy.credits(w, P12Scenario.PLAYER)).is_less(P12Scenario.CREDITS)


# FT: FT-PAIR-004, FT-PAIR-015, FT-MIS-019
# An offer needing tractor power 2 while the tractor is damaged can be accepted (never a
# hard block); failing it costs reputation by a draw inside rep.complete_mission.fail's
# range and pays nothing.
func test_an_infeasible_offer_can_be_accepted_and_failing_it_costs_reputation() -> void:
	var dist: RepDistDef = (
		load("res://content/economy/rep/complete_mission_fail.tres") as RepDistDef
	)
	var runs: Dictionary[String, PairHarness.Run] = P12Scenario.harness().compare(
		P12Scenario.coop, P12Scenario.solo
	)
	assert_bool(runs.solo.completed).is_true()
	var w: SimWorld = _ready_world()
	assert_bool(StoryRules.needs_met(w, 0, 1)).is_false()
	var accept: AcceptCardCommand = AcceptCardCommand.new()
	accept.card = 1
	assert_bool(StoryFixture.run(w, 0, accept)).is_true()
	assert_int(w.story.state[1]).is_equal(StoryTable.State.ACCEPTED)
	assert_float(runs.solo.metrics.rep_lost).is_between(-dist.hi, -dist.lo)
	assert_float(runs.solo.metrics.credits).is_equal(float(P12Scenario.CREDITS))
	# With the tractor mended the same offer is feasible.
	P12Scenario.set_tractor(w, 1.0)
	assert_bool(StoryRules.needs_met(w, 0, 1)).is_true()


# FT: FT-PAIR-004, FT-PAIR-015
# What Engineering says by voice saves the reputation: Comms told about the tractor declines
# and loses nothing, where Comms alone accepts and loses reputation. (No gain is asserted:
# P12 is exempt from pair_min_gain.)
func test_what_engineering_says_saves_reputation() -> void:
	var runs: Dictionary[String, PairHarness.Run] = P12Scenario.harness().compare(
		P12Scenario.coop, P12Scenario.solo
	)
	assert_float(runs.coop.metrics.rep_lost).is_equal(0.0)
	assert_float(runs.solo.metrics.rep_lost).is_greater(0.0)


# FT: FT-PAIR-010, FT-PAIR-019
# No Engineering data reaches a separate Comms player: its block has no subsystem, spare
# part or fault field, only the hull as one of the health bands, whatever the ship's state.
func test_comms_sees_the_hull_band_and_nothing_of_condition() -> void:
	var w: SimWorld = _ready_world()
	var block: Dictionary = CommsView.block(w, 0)
	var fields: Array[String] = []
	for entry: Array in CommsView.SCHEMA:
		fields.append(entry[0])
	assert_array(block.keys()).contains_exactly_in_any_order(fields)
	for banned: String in ["subsystems", "parts", "spares", "fault", "heat", "health"]:
		assert_bool(fields.has(banned)).override_failure_message(banned).is_false()
	var band: int = block["hull_band"]
	var damaged: SimWorld = _ready_world()
	damaged.damage.health[damaged.damage.hull_row(0)] *= 0.5
	damaged.damage.health[damaged.damage.find_subsystem(0, &"sensors")] = 0.0
	assert_int(CommsView.block(damaged, 0)["hull_band"]).is_not_equal(band)
	var seen: Dictionary = CommsView.block(damaged, 0)
	seen.erase("hull_band")
	var base: Dictionary = block.duplicate()
	base.erase("hull_band")
	assert_dict(seen).is_equal(base)
