extends GdUnitTestSuite
## CalloutText (spec §6.1, D45, D114): chips read like the callout, translated.


func before() -> void:
	I18n.apply("en")


func after() -> void:
	I18n.apply("en")


## Ship-frame offset at a bearing and elevation (degrees).
func _dir(bearing_deg: float, elevation_deg: float, dist: float) -> Vector3:
	var b: float = deg_to_rad(bearing_deg)
	var e: float = deg_to_rad(elevation_deg)
	return Vector3(sin(b) * cos(e), sin(e), -cos(b) * cos(e)) * dist


# FT: FT-SPA-003, FT-SPA-004
func test_chip_reads_like_the_callout() -> void:
	assert_str(CalloutText.callout("H2", _dir(120.0, 30.0, 4000.0))).is_equal("H2 · 4 high · mid")
	assert_str(CalloutText.callout("U1", _dir(0.0, -5.0, 500.0))).is_equal("U1 · 12 level · close")
	assert_str(CalloutText.callout("F3", _dir(270.0, -20.0, 20000.0))).is_equal("F3 · 9 low · far")


# FT: FT-SPA-003
func test_chip_drops_the_clock_above_60_degrees() -> void:
	assert_str(CalloutText.callout("H1", _dir(90.0, 70.0, 3000.0))).is_equal("H1 · overhead · mid")
	assert_str(CalloutText.callout("H1", _dir(90.0, -75.0, 300.0))).is_equal("H1 · under · close")


# FT: FT-SPA-003
func test_chip_shows_the_band_not_the_range() -> void:
	var text: String = CalloutText.callout("N4", _dir(45.0, 0.0, 7321.0))
	assert_str(text).is_equal("N4 · 2 level · mid")
	assert_str(text).not_contains("7")


# FT: FT-SPA-003
func test_chip_words_are_translated() -> void:
	I18n.apply("it")
	assert_str(CalloutText.callout("H2", _dir(120.0, 30.0, 4000.0))).is_equal("H2 · 4 alto · medio")
	assert_str(CalloutText.callout("H2", _dir(0.0, 80.0, 400.0))).is_equal("H2 · sopra · vicino")
	I18n.apply("en")


# FT: FT-SPA-005
func test_precise_bearing_and_mark() -> void:
	assert_str(CalloutText.precise(_dir(45.0, 12.0, 1000.0))).is_equal("brg 045 · mk +12")
	assert_str(CalloutText.precise(_dir(359.6, -7.0, 1000.0))).is_equal("brg 000 · mk -7")
	assert_str(CalloutText.precise(_dir(270.0, 0.0, 1000.0))).is_equal("brg 270 · mk +0")


# FT: FT-WPN-005, FT-SPA-003
func test_clock_words_translates_the_height_word_for_every_station() -> void:
	assert_str(CalloutText.clock_words(Vector3.FORWARD)).is_equal("12 level")
	assert_str(CalloutText.clock_words(Vector3(1, 1, 0))).is_equal("3 high")
	assert_str(CalloutText.clock_words(_dir(90.0, 70.0, 3000.0))).is_equal("overhead")
	I18n.apply("it")
	assert_str(CalloutText.clock_words(_dir(120.0, 30.0, 4000.0))).is_equal("4 alto")
	I18n.apply("en")
