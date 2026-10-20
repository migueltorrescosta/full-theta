extends GdUnitTestSuite
## Bindings: the player's rebinds and toggles over IntentTable's defaults.


# FT: FT-STN-007
func test_rebind_replaces_defaults_per_device() -> void:
	var b: Bindings = Bindings.new()
	assert_array(Array(b.bindings("cycle_target", "kbm"))).is_equal(["T"])
	b.rebind("cycle_target", "kbm", PackedStringArray(["U", "Tab"]))
	assert_array(Array(b.bindings("cycle_target", "kbm"))).is_equal(["U", "Tab"])
	assert_array(Array(b.bindings("cycle_target", "pad"))).is_equal(["RB"])
	assert_array(b.intents_bound_to("U", "kbm")).is_equal(["cycle_target"])
	b.rebind("cycle_target", "pad", PackedStringArray())
	assert_array(Array(b.bindings("cycle_target", "pad"))).is_empty()


# FT: FT-STN-007
func test_reset_one_or_all() -> void:
	var b: Bindings = Bindings.new()
	b.rebind("cycle_target", "kbm", PackedStringArray(["U"]))
	b.rebind("ping", "kbm", PackedStringArray(["P"]))
	b.reset("cycle_target")
	assert_array(Array(b.bindings("cycle_target", "kbm"))).is_equal(["T"])
	assert_array(Array(b.bindings("ping", "kbm"))).is_equal(["P"])
	b.reset()
	assert_array(Array(b.bindings("ping", "kbm"))).is_equal(["MMB"])


# FT: FT-STN-007, FT-STN-014
func test_dict_round_trip() -> void:
	var b: Bindings = Bindings.new()
	b.rebind("cycle_target", "kbm", PackedStringArray(["U"]))
	b.set_toggle("face", true)
	var data: Variant = JSON.parse_string(JSON.stringify(b.to_dict()))
	var c: Bindings = Bindings.new()
	c.from_dict(data)
	assert_array(Array(c.bindings("cycle_target", "kbm"))).is_equal(["U"])
	assert_array(Array(c.bindings("cycle_target", "pad"))).is_equal(["RB"])
	assert_bool(c.is_toggle("face")).is_true()


# FT: FT-STN-007, FT-STN-014
func test_unknown_ids_devices_and_non_hold_toggles_are_dropped() -> void:
	var b: Bindings = Bindings.new()
	b.rebind("no_such_intent", "kbm", PackedStringArray(["U"]))
	assert_dict(b.overrides).is_empty()
	b.set_toggle("ping", true)
	assert_bool(b.is_toggle("ping")).is_false()
	(
		b
		. from_dict(
			{
				"overrides": {"gone": {"kbm": ["U"]}, "ping": {"wheel": ["U"], "kbm": ["P"]}},
				"toggles": ["gone", "ping", "approach"],
			}
		)
	)
	assert_array(b.overrides.keys()).is_equal(["ping"])
	assert_array(b.overrides["ping"].keys()).is_equal(["kbm"])
	assert_array(b.toggles.keys()).is_equal(["approach"])


# FT: FT-STN-007
# A hand-edited file with values of the wrong type loads what it can, without errors.
func test_wrongly_typed_data_is_dropped() -> void:
	var b: Bindings = Bindings.new()
	b.from_dict({"overrides": ["ping"], "toggles": 3})
	assert_dict(b.overrides).is_empty()
	assert_dict(b.toggles).is_empty()
	(
		b
		. from_dict(
			{
				"overrides":
				{"ping": {"kbm": 5}, "mark": {"kbm": ["P", 3]}, "claim": {"pad": ["A"]}},
				"toggles": "approach",
			}
		)
	)
	assert_array(b.overrides.keys()).is_equal(["claim"])
	assert_array(Array(b.bindings("ping", "kbm"))).is_equal(["MMB"])
	assert_dict(b.toggles).is_empty()
