extends GdUnitTestSuite
## IdleExitTimer: a server with no connections for N minutes exits.


# FT: FT-NET-003
func test_expires_after_the_limit_without_connections() -> void:
	var timer: IdleExitTimer = IdleExitTimer.new(0.5)  # 30 s
	var t0: float = 1_000_000.0
	assert_bool(timer.update(0, t0)).is_false()
	assert_bool(timer.update(0, t0 + 29.5)).is_false()
	assert_float(timer.idle_seconds(t0 + 29.5)).is_equal_approx(29.5, 1e-6)
	assert_bool(timer.update(0, t0 + 30.0)).is_true()


# FT: FT-NET-003
func test_a_connection_resets_the_clock() -> void:
	var timer: IdleExitTimer = IdleExitTimer.new(0.5)
	var t0: float = 1_000_000.0
	timer.update(0, t0)
	assert_bool(timer.update(3, t0 + 29.0)).is_false()
	assert_float(timer.idle_seconds(t0 + 29.0)).is_equal(0.0)
	assert_bool(timer.update(0, t0 + 40.0)).is_false()  # empty again from 40 s
	assert_bool(timer.update(0, t0 + 69.0)).is_false()
	assert_bool(timer.update(0, t0 + 70.0)).is_true()


func test_a_zero_limit_never_expires() -> void:
	var timer: IdleExitTimer = IdleExitTimer.new(0)
	timer.update(0, 0.0)
	assert_bool(timer.update(0, 1e9)).is_false()


func test_runs_on_the_real_wall_clock() -> void:
	var timer: IdleExitTimer = IdleExitTimer.new(0.002)  # 0.12 s
	assert_bool(timer.update(0, Time.get_unix_time_from_system())).is_false()
	var deadline: int = Time.get_ticks_msec() + 2000
	var expired: bool = false
	while not expired and Time.get_ticks_msec() < deadline:
		OS.delay_msec(20)
		expired = timer.update(0, Time.get_unix_time_from_system())
	assert_bool(expired).is_true()
