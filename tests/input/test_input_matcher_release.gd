extends MatcherSuite
## InputMatcher: what ends held intents (context switches, rebinds, a select that ate
## the click) and the restricted set while Settings or the overlay is up.


# FT: FT-STN-014, FT-JNT-001
# Releases of intents leaving the active set go to the panel that had them.
func test_context_change_releases_to_the_old_target() -> void:
	_m.set_context(["helm", "weapons"], "weapons")
	_m.feed(_motion(JOY_AXIS_TRIGGER_RIGHT, 1.0), 0)
	_m.set_context(["helm", "weapons"], "helm")
	var up: Array[Dictionary] = _m.update(10, 0.0)
	assert_array(_ids(up)).is_equal(["fire/up"])
	assert_str(up[0]["target"]).is_equal("weapons")


# FT: FT-STN-014, FT-STN-009
# A dropped toggle flip (the click selected something, D176) is undone, both ways.
func test_cancel_undoes_a_toggle_flip_or_a_hold() -> void:
	_m.bindings.set_toggle("face", true)
	_feed(_key("F", true), 0)
	_m.cancel("face")
	assert_bool(_m.is_held("face")).is_false()
	_feed(_key("F", false), 10)
	_feed(_key("F", true), 20)
	_feed(_key("F", false), 30)
	assert_array(_feed(_key("F", true), 40)).is_equal(["face/up"])
	_m.cancel("face")
	assert_bool(_m.is_held("face")).is_true()
	_feed(_key("X", true), 50)
	_m.cancel("approach")
	assert_bool(_m.is_held("approach")).is_false()
	assert_array(_feed(_key("X", false), 60)).is_empty()


# FT: FT-STN-007, FT-STN-014
# A rebind or a hold/toggle switch releases the held intents it touches, only those.
func test_rebinding_releases_what_it_changes() -> void:
	_feed(_key("F", true), 0)
	_feed(_key("X", true), 10)
	_m.bindings.rebind("face", "kbm", PackedStringArray(["G"]))
	assert_array(_ids(_m.update(20, 0.0))).is_equal(["face/up"])
	assert_bool(_m.is_held("approach")).is_true()
	_m.bindings.set_toggle("approach", true)
	assert_array(_ids(_m.update(30, 0.0))).is_equal(["approach/up"])
	_m.bindings.rebind("cycle_target", "kbm", PackedStringArray(["U"]))
	_feed(_key("G", true), 40)
	_m.bindings.rebind("cycle_target", "kbm", PackedStringArray(["T"]))
	assert_array(_ids(_m.update(50, 0.0))).is_empty()
	assert_bool(_m.is_held("face")).is_true()


# FT: FT-STN-011
# Restricted (Settings or the overlay up), only the named intents act.
func test_restrict_limits_the_active_set() -> void:
	_m.restrict(["overlay", "menu"])
	assert_array(_feed(_key("F", true), 0)).is_empty()
	_feed(_key("W", true), 10)
	assert_float(_m.axis("helm_surge")).is_equal(0.0)
	assert_array(_feed(_key("Escape", true), 20)).is_equal(["menu"])
	_m.restrict([])
	assert_float(_m.axis("helm_surge")).is_equal(1.0)
