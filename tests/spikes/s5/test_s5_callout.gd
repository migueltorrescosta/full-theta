extends GdUnitTestSuite
## S5 spike: ship-frame clock, height and range words for chips. Spike-verified ids,
## untagged until promotion (#5 T034, #7 T050): FT-SPA-003, FT-SPA-004, FT-SPA-026.


func _dir(bearing_deg: float, elevation_deg: float) -> Vector3:
	# Local frame: -Z bow, +X starboard, +Y up.
	var b: float = deg_to_rad(bearing_deg)
	var e: float = deg_to_rad(elevation_deg)
	return Vector3(sin(b) * cos(e), sin(e), -cos(b) * cos(e)) * 2300.0


func test_clock_positions() -> void:
	var cases: Array[Array] = [
		[0.0, 12], [14.0, 12], [16.0, 1], [90.0, 3], [120.0, 4], [180.0, 6], [270.0, 9], [346.0, 12]
	]
	for c: Array in cases:
		assert_int(S5Callout.clock(_dir(c[0], 0.0))).override_failure_message(str(c)).is_equal(c[1])


func test_height_words() -> void:
	var cases: Array[Array] = [
		[0.0, "level"],
		[14.9, "level"],
		[-14.9, "level"],
		[15.1, "high"],
		[-30.0, "low"],
		[59.9, "high"],
		[60.1, "overhead"],
		[-75.0, "under"],
	]
	for c: Array in cases:
		var word: String = S5Callout.height_word(_dir(120.0, c[0]))
		assert_str(word).override_failure_message(str(c)).is_equal(c[1])


func test_chip_text_and_poles() -> void:
	assert_str(S5Callout.chip("H2", _dir(120.0, 30.0), 50.0)).is_equal(
		"H2 · 4 high · 2.3 km ▲closing"
	)
	assert_str(S5Callout.chip("H2", _dir(120.0, 70.0), -20.0)).is_equal(
		"H2 · overhead · 2.3 km ▼opening"
	)
	assert_str(S5Callout.clock_height(_dir(270.0, -5.0))).is_equal("9 level")


func test_range_bands() -> void:
	assert_str(S5Callout.range_band(999.0)).is_equal("close")
	assert_str(S5Callout.range_band(1000.0)).is_equal("mid")
	assert_str(S5Callout.range_band(10000.0)).is_equal("mid")
	assert_str(S5Callout.range_band(10001.0)).is_equal("far")
	assert_str(S5Callout.range_text(650.4)).is_equal("650 m")


# FT-SPA-026: words are ship frame: rolling the ship 180° turns "high" into "low".
func test_words_follow_ship_frame() -> void:
	var body: S5ShipBody = S5ShipBody.new()
	var world_offset: Vector3 = Vector3(0.0, 1000.0, -2000.0)
	assert_str(S5Callout.clock_height(body.to_local(world_offset))).is_equal("12 high")
	body.orientation = Quaternion(Vector3.FORWARD, PI)
	assert_str(S5Callout.clock_height(body.to_local(world_offset))).is_equal("12 low")
