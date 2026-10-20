extends MatcherSuite
## InputMatcher axes: pairs, dead zones, chord suppression, pitch inversion, the mouse
## stick and device switching.


# FT: FT-STN-005
func test_button_pair_axes() -> void:
	_feed(_key("W", true), 0)
	assert_float(_m.axis("helm_surge")).is_equal(1.0)
	_feed(_key("S", true), 10)
	assert_float(_m.axis("helm_surge")).is_equal(0.0)
	_feed(_key("W", false), 20)
	assert_float(_m.axis("helm_surge")).is_equal(-1.0)
	assert_float(_m.axis("all_stop")).is_equal(0.0)


# FT: FT-STN-005
func test_stick_dead_zone_and_rescale() -> void:
	_feed(_motion(JOY_AXIS_LEFT_X, 0.15), 0)
	assert_float(_m.axis("helm_yaw")).is_equal(0.0)
	assert_str(_m.device).is_equal("kbm")
	_feed(_motion(JOY_AXIS_LEFT_X, 0.6), 10)
	assert_float(_m.axis("helm_yaw")).is_equal_approx(0.5, 0.0001)
	assert_str(_m.device).is_equal("pad")
	# Radial: a full diagonal deflection keeps its direction.
	_feed(_motion(JOY_AXIS_LEFT_Y, 0.8), 20)
	assert_float(_m.axis("helm_yaw")).is_equal_approx(0.6, 0.0001)
	assert_float(_m.axis("helm_pitch")).is_equal_approx(0.8, 0.0001)
	# Triggers: linear dead zone 0.1; "-RS_Y" inverts.
	_feed(_motion(JOY_AXIS_TRIGGER_RIGHT, 0.55), 30)
	assert_float(_m.axis("helm_surge")).is_equal_approx(0.5, 0.0001)
	_feed(_motion(JOY_AXIS_RIGHT_Y, 1.0), 40)
	assert_float(_m.axis("helm_heave")).is_equal_approx(-1.0, 0.0001)


# FT: FT-STN-005
func test_lb_ls_x_rolls_and_suppresses_yaw() -> void:
	_feed(_motion(JOY_AXIS_LEFT_X, 1.0), 0)
	assert_float(_m.axis("helm_yaw")).is_equal(1.0)
	assert_float(_m.axis("helm_roll")).is_equal(0.0)
	_feed(_pad("LB", true), 10)
	assert_float(_m.axis("helm_yaw")).is_equal(0.0)
	assert_float(_m.axis("helm_roll")).is_equal(1.0)
	_feed(_pad("LB", false), 900)
	assert_float(_m.axis("helm_yaw")).is_equal(1.0)


# FT: FT-STN-005
func test_invert_pitch_flips_pitch_axes_only() -> void:
	_feed(_motion(JOY_AXIS_LEFT_Y, 1.0), 0)
	assert_float(_m.axis("helm_pitch")).is_equal(1.0)
	_m.invert_pitch = true
	assert_float(_m.axis("helm_pitch")).is_equal(-1.0)
	_feed(_motion(JOY_AXIS_LEFT_Y, 0.0), 10)
	_feed(_motion(JOY_AXIS_LEFT_X, 1.0), 20)
	assert_float(_m.axis("helm_yaw")).is_equal(1.0)


# FT: FT-STN-005
func test_mouse_stick_feeds_mouse_axes_and_recentres() -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(50, 0)
	_m.feed(motion, 0)
	assert_float(_m.axis("helm_yaw")).is_equal_approx(0.3, 0.0001)
	_m.update(100, 0.12)
	assert_float(_m.axis("helm_yaw")).is_equal_approx(0.15, 0.0001)


# FT: FT-STN-005
func test_device_ignores_noise() -> void:
	_feed(_pad("A", true), 0)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(1, 0)
	_m.feed(motion, 10)
	assert_str(_m.device).is_equal("pad")
	motion.relative = Vector2(5, 0)
	_m.feed(motion, 20)
	assert_str(_m.device).is_equal("kbm")
	_feed(_motion(JOY_AXIS_RIGHT_X, 0.1), 30)
	assert_str(_m.device).is_equal("kbm")
