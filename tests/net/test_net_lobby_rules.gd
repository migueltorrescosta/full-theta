extends GdUnitTestSuite
## The coverage check as a pure rule (NetCoverage, T043).


# FT: FT-NET-019, FT-NET-020, FT-GEN-004, FT-GEN-005, FT-GEN-006
# Coverage passes with at least 3 crew covering all six stations; Captain and Viewer
# picks never count; uncovered stations are listed in station order.
func test_coverage_needs_three_crew_and_six_stations() -> void:
	assert_bool(NetCoverage.passes(["tactical", "systems", "ops"])).is_true()
	assert_bool(NetCoverage.passes(["tactical", "systems", "ops", "captain", "viewer"])).is_true()
	assert_bool(NetCoverage.passes(["tactical", "systems", "captain", "viewer"])).is_false()
	assert_array(NetCoverage.uncovered(["tactical", "systems", "captain", "viewer"])).is_equal(
		["relay", "comms"]
	)
	assert_int(NetCoverage.crew_count(["tactical", "captain", "viewer", "helm"])).is_equal(2)
	# Six stations covered by two players: still short of 3 crew (D66).
	assert_bool(NetCoverage.passes(["all", "helm"])).is_false()
	assert_array(NetCoverage.uncovered(["all", "helm"])).is_empty()
	# Single stations work as well as joint views; shared stations are fine.
	var singles: Array = ["helm", "weapons", "engineering", "science", "relay", "comms", "helm"]
	assert_bool(NetCoverage.passes(singles)).is_true()
	assert_array(NetCoverage.uncovered([])).is_equal(StationViews.CREW)
	# Captain alone: nothing covered (the seat is never required, FT-GEN-006).
	assert_array(NetCoverage.uncovered(["captain"])).is_equal(StationViews.CREW)


# FT: FT-NET-029, FT-M1-015
# With the dev flag the minimum is one crew player, so one client holding every station
# passes.
func test_dev_minimum_is_one() -> void:
	assert_bool(NetCoverage.passes(["all"], 1)).is_true()
	assert_bool(NetCoverage.passes(["all"])).is_false()
	assert_bool(NetCoverage.passes(["tactical"], 1)).is_false()


# FT: FT-GEN-007
# No station can be left off or to automation: with any one of the six stations
# uncovered, even with five crew on the other five (and a Captain and a Viewer), the
# check fails and names exactly that station, so Start is refused and a run pauses.
# The dev entry's lower minimum doesn't change that.
func test_no_station_may_be_left_off() -> void:
	for missing: String in StationViews.CREW:
		var entries: Array = ["captain", "viewer"]
		for station: String in StationViews.CREW:
			if station != missing:
				entries.append(station)
		assert_bool(NetCoverage.passes(entries)).is_false()
		assert_bool(NetCoverage.passes(entries, 1)).is_false()
		assert_array(NetCoverage.uncovered(entries)).is_equal([missing])
