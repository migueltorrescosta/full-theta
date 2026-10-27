extends GdUnitTestSuite
## The data-shortcut toggle model (DataToggles, content/toggles/toggles.tres): the presets of
## spec §7.2, edited sets and their codes, the "(custom)" state.

## §7.2 written out by hand, not read from the file under test: toggle -> [Easy, Normal, Hard].
## Summaries are 2 exact, 1 banded, 0 absent; the others 1 on, 0 off or by voice.
const TABLE: Dictionary = {
	&"summaries": [2, 1, 0],
	&"chips": [1, 1, 0],
	&"routes": [1, 1, 0],
	&"lanes": [1, 1, 0],
	&"hazard_countdowns": [1, 1, 0],
	&"weak_points": [1, 0, 0],
	&"track_feeds": [1, 0, 0],
	&"diagnosed_causes": [1, 0, 0],
	&"contract_flags": [1, 0, 0],
	&"verify_chip": [1, 0, 0],
	&"mission_icon": [1, 1, 0],
}


# FT: FT-PAIR-017, FT-PAIR-018, FT-PAIR-020
# Every cross-station shortcut of §7.2 is its own toggle, and Easy, Normal and Hard set
# them to the table's values (D84, D90). Engineering with Comms has no toggle (D68).
func test_presets_match_the_spec_table() -> void:
	assert_array(DataToggles.ids()).contains_exactly_in_any_order(TABLE.keys())
	var presets: Array[String] = ["easy", "normal", "hard"]
	for i: int in 3:
		var picked: DataToggles = DataToggles.of_preset(presets[i])
		for id: StringName in TABLE:
			(
				assert_int(picked.value(id))
				. override_failure_message("%s on %s" % [id, presets[i]])
				. is_equal(TABLE[id][i])
			)
		assert_bool(picked.is_custom()).is_false()
		assert_str(picked.encode()).is_equal(presets[i])


# FT: FT-PAIR-018
# D90: Normal keeps the mission mark icon and voices contract flags and Science verify
# chips; Hard keeps marks and pings only, so every toggle is off.
func test_normal_and_hard_follow_d90() -> void:
	var normal: DataToggles = DataToggles.of_preset("normal")
	assert_bool(normal.on(&"mission_icon")).is_true()
	assert_bool(normal.on(&"contract_flags")).is_false()
	assert_bool(normal.on(&"verify_chip")).is_false()
	assert_int(normal.summaries()).is_equal(1)
	var hard: DataToggles = DataToggles.of_preset("hard")
	for id: StringName in DataToggles.ids():
		assert_bool(hard.on(id)).override_failure_message(str(id)).is_false()


# FT: FT-PAIR-017, FT-STN-016
# P9 (contract flags) and P14 (verify chip) are live since M3 (D190), so no toggle is listed
# as arriving later; a first launch is Easy.
func test_every_toggle_is_live_and_the_default_is_easy() -> void:
	var ids: Array[StringName] = DataToggles.ids()
	assert_bool(ids.has(&"contract_flags")).is_true()
	assert_bool(ids.has(&"verify_chip")).is_true()
	assert_str(String(DataToggles.def().default_preset)).is_equal("easy")
	assert_str(StationViews.DEFAULT_TOGGLES).is_equal("easy")


# FT: FT-PAIR-017
# Changing one toggle keeps the preset it started from and makes the set custom; changing it
# back makes it the preset again. The code round-trips.
func test_an_edited_set_is_custom_and_round_trips() -> void:
	var normal: DataToggles = DataToggles.of_preset("normal")
	var edited: DataToggles = normal.with_value(&"weak_points", 1)
	assert_bool(edited.is_custom()).is_true()
	assert_str(edited.preset).is_equal("normal")
	assert_bool(edited.on(&"weak_points")).is_true()
	assert_bool(normal.on(&"weak_points")).is_false()
	var code: String = edited.encode()
	assert_str(code).starts_with("normal:")
	var back: DataToggles = DataToggles.parse(code)
	assert_array(Array(back.values)).is_equal(Array(edited.values))
	assert_str(back.preset).is_equal("normal")
	assert_bool(edited.with_value(&"weak_points", 0).is_custom()).is_false()
	assert_str(edited.with_value(&"weak_points", 0).encode()).is_equal("normal")
	# A value above the toggle's maximum or an unknown toggle changes nothing.
	assert_str(normal.with_value(&"chips", 2).encode()).is_equal("normal")
	assert_str(normal.with_value(&"nope", 1).encode()).is_equal("normal")
	# Choosing another preset replaces the edits.
	assert_str(DataToggles.of_preset("hard").encode()).is_equal("hard")


# FT: FT-PAIR-017
# A malformed code is refused, never half-read.
func test_malformed_codes_are_refused() -> void:
	for code: String in [
		"",
		"extreme",
		"easy:",
		"easy:1",
		"normal:21111000000x",
		"normal:3111110000",
		"easy:21111111111:1",
		":21111111111",
	]:
		assert_bool(DataToggles.is_valid(code)).override_failure_message(code).is_false()
	assert_bool(DataToggles.is_valid("easy:21111111111")).is_true()
