extends GdUnitTestSuite
## T034: shared spatial callouts (spec §6.1): clock, height words, range bands and the
## frame rule. Angles are tested 0.1° either side of each boundary; float32 offsets put
## an angle within about 1e-5° of its intended value, far inside that margin.


## Ship-frame offset at a bearing and elevation (degrees): -Z bow, +X starboard, +Y up.
func _dir(bearing_deg: float, elevation_deg: float, dist: float = 2300.0) -> Vector3:
	var b: float = deg_to_rad(bearing_deg)
	var e: float = deg_to_rad(elevation_deg)
	return Vector3(sin(b) * cos(e), sin(e), -cos(b) * cos(e)) * dist


## Callout for a world-frame offset seen from a ship with this orientation.
func _spoken(world_offset: Vector3, orientation: Quaternion) -> String:
	return Callout.clock_height(orientation.inverse() * world_offset)


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


# FT: FT-SPA-026, FT-SPA-004
# The words are ship frame: rolling the ship 180° about its bow turns "12 high" into
# "12 low"; yawing it 90° to port moves the contact from 12 to 3.
func test_rolled_ship_flips_high_and_low() -> void:
	var world_offset: Vector3 = Vector3(0.0, 1000.0, -2000.0)
	assert_str(_spoken(world_offset, Quaternion.IDENTITY)).is_equal("12 high")
	var rolled: Quaternion = Quaternion(Vector3.FORWARD, PI)
	assert_str(_spoken(world_offset, rolled)).is_equal("12 low")
	var yawed: Quaternion = Quaternion(Vector3.UP, PI / 2.0)
	assert_str(_spoken(world_offset, yawed)).is_equal("3 high")


# FT: FT-SPA-026, FT-ARC-021
# Frame rule, as a table over orientations: callouts use only the clock and
# level/high/low/overhead/under and change with the ship's attitude; there are no
# world-frame words (D124: no privileged up, no world grid).
func test_frame_rule_word_sets() -> void:
	var ship_words: RegEx = RegEx.create_from_string(
		"^([1-9]|1[0-2]) (level|high|low)$|^overhead$|^under$"
	)
	var attitudes: Array[Quaternion] = [
		Quaternion.IDENTITY,
		Quaternion(Vector3.FORWARD, PI),
		Quaternion(Vector3.RIGHT, PI / 2.0),
		Quaternion(Vector3(1, 1, 0).normalized(), 2.0),
	]
	var offsets: Array[Vector3] = [
		Vector3(3500, 1000, 3200),
		Vector3(-500, -1600, 800),
		Vector3(0, 9000, -100),
		Vector3(7000, 0, -7000),
		Vector3(-2000, -300, 50),
	]
	for offset: Vector3 in offsets:
		var seen: Dictionary[String, bool] = {}
		for q: Quaternion in attitudes:
			var spoken: String = _spoken(offset, q)
			(
				assert_bool(ship_words.search(spoken) != null)
				. override_failure_message(spoken)
				. is_true()
			)
			seen[spoken] = true
		assert_int(seen.size()).override_failure_message(str(offset)).is_greater(1)


# FT: FT-SPA-026, FT-SPA-006
# A far point is said relative to a mark or site with ship-frame words and a spoken range;
# the same offset from the same reference reads differently once the ship has turned.
func test_far_point_is_said_relative_to_a_mark_or_site() -> void:
	var cases: Array = [
		# [reference, offset from it in the ship frame, spoken]
		["Bravo", Vector3(0.0, 800.0, -2900.0), "Bravo, 12 high, 3 km"],
		["Bravo", Vector3(2500.0, 0.0, 0.0), "Bravo, 3 level, 2.5 km"],
		["Kestrel Yard", Vector3(-1000.0, -4000.0, 12000.0), "Kestrel Yard, 6 low, 13 km"],
		["Bravo", Vector3(0.0, 4000.0, -100.0), "Bravo, overhead, 4 km"],
		["Charlie", Vector3(0.0, -9000.0, 0.0), "Charlie, under, 9 km"],
		["Alpha", Vector3(0.0, 0.0, -840.0), "Alpha, 12 level, 800 m"],
	]
	for c: Array in cases:
		assert_str(Callout.relative(c[0], c[1])).override_failure_message(str(c)).is_equal(c[2])
	# Ship frame: turning the ship 90° to port moves the same world offset from 12 to 3.
	var world: Vector3 = Vector3(0.0, 800.0, -2900.0)
	var turned: Quaternion = Quaternion(Vector3.UP, PI / 2.0)
	assert_str(Callout.relative("Bravo", turned.inverse() * world)).is_equal("Bravo, 3 high, 3 km")
