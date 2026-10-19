extends GdUnitTestSuite
## T034: shared spatial callouts (spec §6.1): clock, height words, range bands and the
## frame rule. Angles are tested 0.1° either side of each boundary; float32 offsets put
## an angle within about 1e-5° of its intended value, far inside that margin.


## Ship-frame offset at a bearing and elevation (degrees): -Z bow, +X starboard, +Y up.
func _dir(bearing_deg: float, elevation_deg: float, dist: float = 2300.0) -> Vector3:
	var b: float = deg_to_rad(bearing_deg)
	var e: float = deg_to_rad(elevation_deg)
	return Vector3(sin(b) * cos(e), sin(e), -cos(b) * cos(e)) * dist


# FT: FT-SPA-004
# Clock in the deck plane: 12 bow, 3 starboard, 6 stern, 9 port; each hour spans ±15°.
func test_clock_positions() -> void:
	var cases: Array[Array] = [
		[0.0, 12],
		[14.9, 12],
		[15.1, 1],
		[90.0, 3],
		[120.0, 4],
		[180.0, 6],
		[270.0, 9],
		[345.1, 12],
		[344.9, 11],
	]
	for c: Array in cases:
		var got: int = Callout.clock(_dir(c[0], 10.0))
		assert_int(got).override_failure_message(str(c, " got ", got)).is_equal(c[1])


# FT: FT-SPA-003, FT-SPA-004
# Height words at the ±15° and ±60° boundaries; beyond ±60° the clock is dropped.
func test_height_words_at_boundaries() -> void:
	var cases: Array[Array] = [
		[0.0, "level", "4 level"],
		[14.9, "level", "4 level"],
		[-14.9, "level", "4 level"],
		[15.1, "high", "4 high"],
		[-15.1, "low", "4 low"],
		[59.9, "high", "4 high"],
		[-59.9, "low", "4 low"],
		[60.1, "overhead", "overhead"],
		[-60.1, "under", "under"],
		[90.0, "overhead", "overhead"],
		[-90.0, "under", "under"],
	]
	for c: Array in cases:
		var local: Vector3 = _dir(120.0, c[0])
		assert_str(Callout.height_word(local)).override_failure_message(str(c)).is_equal(c[1])
		assert_str(Callout.clock_height(local)).override_failure_message(str(c)).is_equal(c[2])


# FT: FT-SPA-003
# Range bands: close < 1 km, mid 1-10 km inclusive, far > 10 km.
func test_range_bands() -> void:
	var cases: Array[Array] = [
		[0.0, "close"],
		[999.9, "close"],
		[1000.0, "mid"],
		[5000.0, "mid"],
		[10000.0, "mid"],
		[10000.1, "far"],
		[140000.0, "far"],
	]
	for c: Array in cases:
		assert_str(Callout.range_band(c[0])).override_failure_message(str(c)).is_equal(c[1])


# FT: FT-SPA-003
# Exact range text switches unit on the rounded value.
func test_range_text() -> void:
	var cases: Array[Array] = [
		[650.4, "650 m"],
		[999.4, "999 m"],
		[999.7, "1.0 km"],
		[2300.0, "2.3 km"],
		[99940.0, "99.9 km"],
		[99960.0, "100 km"],
		[140000.0, "140 km"],
	]
	for c: Array in cases:
		assert_str(Callout.range_text(c[0])).override_failure_message(str(c)).is_equal(c[1])


# FT: FT-SPA-003
# Chips read callsign, clock and height (or only overhead/under), range band.
func test_chip_text() -> void:
	assert_str(Callout.chip("H2", _dir(120.0, 30.0), 50.0)).is_equal("H2 · 4 high · mid ▲closing")
	assert_str(Callout.chip("H2", _dir(120.0, 70.0), -20.0)).is_equal(
		"H2 · overhead · mid ▼opening"
	)
	assert_str(Callout.chip("U3", _dir(270.0, -5.0, 650.0), 0.5)).is_equal("U3 · 9 level · close")
	assert_str(Callout.chip("F1", _dir(180.0, -40.0, 25000.0), 0.0)).is_equal("F1 · 6 low · far")


# FT: FT-SPA-026, FT-SPA-004
# The words are ship frame: rolling the ship 180° about its bow turns "12 high" into
# "12 low"; yawing it 90° to port moves the contact from 12 to 3.
func test_rolled_ship_flips_high_and_low() -> void:
	var world_offset: Vector3 = Vector3(0.0, 1000.0, -2000.0)
	assert_str(Callout.ship_callout(world_offset, Quaternion.IDENTITY)).is_equal("12 high")
	var rolled: Quaternion = Quaternion(Vector3.FORWARD, PI)
	assert_str(Callout.ship_callout(world_offset, rolled)).is_equal("12 low")
	var yawed: Quaternion = Quaternion(Vector3.UP, PI / 2.0)
	assert_str(Callout.ship_callout(world_offset, yawed)).is_equal("3 high")


# FT: FT-SPA-026, FT-ARC-021
# Frame rule, as a table over orientations: ship-frame callouts use only the clock and
# level/high/low/overhead/under and change with the ship's attitude; world height is
# only `up N` / `down N` after a grid square, in grid layers, and ignores attitude.
func test_frame_rule_word_sets() -> void:
	var ship_words: RegEx = RegEx.create_from_string(
		"^([1-9]|1[0-2]) (level|high|low)$|^overhead$|^under$"
	)
	var grid_words: RegEx = RegEx.create_from_string(
		"^grid [A-Z]+[1-9][0-9]*(, (up|down) [1-9][0-9]*)?$"
	)
	var attitudes: Array[Quaternion] = [
		Quaternion.IDENTITY,
		Quaternion(Vector3.FORWARD, PI),
		Quaternion(Vector3.RIGHT, PI / 2.0),
		Quaternion(Vector3(1, 1, 0).normalized(), 2.0),
	]
	var origin: Vector3 = Vector3(-10000.0, 0.0, -10000.0)
	var offsets: Array[Vector3] = [
		Vector3(3500, 1000, 3200),
		Vector3(-500, -1600, 800),
		Vector3(0, 9000, -100),
		Vector3(7000, 0, -7000),
		Vector3(-2000, -300, 50),
	]
	for offset: Vector3 in offsets:
		var grid: String = Callout.grid_callout(offset, origin, 1000.0, 500.0)
		assert_bool(grid_words.search(grid) != null).override_failure_message(grid).is_true()
		var seen: Dictionary[String, bool] = {}
		for q: Quaternion in attitudes:
			var spoken: String = Callout.ship_callout(offset, q)
			(
				assert_bool(ship_words.search(spoken) != null)
				. override_failure_message(spoken)
				. is_true()
			)
			seen[spoken] = true
		assert_int(seen.size()).override_failure_message(str(offset)).is_greater(1)


# FT: FT-SPA-026
# Grid squares: letters along +X, numbers from 1 along +Z, from the map corner; height
# in whole layers from the map plane, rounded; nothing off the map.
func test_grid_callout_table() -> void:
	var origin: Vector3 = Vector3.ZERO
	var cases: Array[Array] = [
		[Vector3(3500, 1000, 3200), "grid D4, up 2"],
		[Vector3(500, -600, 500), "grid A1, down 1"],
		[Vector3(500, 240, 999), "grid A1"],
		[Vector3(25999, 0, 0), "grid Z1"],
		[Vector3(26000, 0, 0), "grid AA1"],
		[Vector3(1000, 0, 11000), "grid B12"],
		[Vector3(-1, 0, 0), ""],
		[Vector3(0, 0, -1), ""],
	]
	for c: Array in cases:
		var got: String = Callout.grid_callout(c[0], origin, 1000.0, 500.0)
		assert_str(got).override_failure_message(str(c, " got ", got)).is_equal(c[1])
	assert_str(Callout.grid_square(Vector3(4500, 0, -500), Vector3(0, 0, -1000), 1000.0)).is_equal(
		"E1"
	)
