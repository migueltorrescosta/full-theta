extends GdUnitTestSuite
## T032: first-order lead intercept in shared/ (FT-SIM-014, FT-ARC-021), against the
## analytic intercept. Each case is built backwards from a known answer: the shot flies
## for time t along unit u at speed s, so the target starts at s t u - v t.

# Relative error tolerated on times and aim points: the solver works in 64-bit, inputs
# are float32 Vector3 (about 1e-7 relative).
const TOL: float = 1e-5


# FT: FT-SIM-014, FT-ARC-021
func test_intercept_matches_analytic_table() -> void:
	var cases: Array[Dictionary] = [
		{"name": "stationary", "u": Vector3(0, 0, -1), "v": Vector3.ZERO, "t": 2.0},
		{"name": "crossing", "u": Vector3(1, 0, -2).normalized(), "v": Vector3(300, 0, 0)},
		{"name": "head-on", "u": Vector3(0, 0, -1), "v": Vector3(0, 0, 400), "t": 1.5},
		{"name": "receding", "u": Vector3(0, 1, -1).normalized(), "v": Vector3(0, 50, -900)},
		{"name": "diagonal", "u": Vector3(-1, -1, -1).normalized(), "v": Vector3(-120, 80, 30)},
	]
	var s: float = 1500.0
	for c: Dictionary in cases:
		var u: Vector3 = c["u"]
		var v: Vector3 = c["v"]
		var t: float = c.get("t", 3.0)
		var r: Vector3 = u * (s * t) - v * t
		var got: float = Lead.intercept_time(r, v, s)
		assert_float(got).override_failure_message(c["name"]).is_equal_approx(t, t * TOL)
		var aim: Vector3 = Lead.aim_point(r, v, got)
		assert_vector(aim).override_failure_message(c["name"]).is_equal_approx(
			u * (s * t), Vector3.ONE * (s * t * TOL)
		)
		assert_vector(Lead.aim_direction(r, v, s)).is_equal_approx(u, Vector3.ONE * TOL)


# FT: FT-SIM-014, FT-ARC-021
# A target receding faster than the shot can't be caught; one receding at exactly the
# shot's speed can't either; one closing at the shot's speed meets it halfway.
func test_no_solution_and_linear_cases() -> void:
	var s: float = 1000.0
	var ahead: Vector3 = Vector3(0, 0, -2000)
	assert_float(Lead.intercept_time(ahead, Vector3(0, 0, -1200), s)).is_equal(Lead.NONE)
	assert_vector(Lead.aim_direction(ahead, Vector3(0, 0, -1200), s)).is_equal(Vector3.ZERO)
	assert_float(Lead.intercept_time(ahead, Vector3(0, 0, -1000), s)).is_equal(Lead.NONE)
	assert_float(Lead.intercept_time(ahead, Vector3(0, 0, 1000), s)).is_equal_approx(1.0, TOL)
	assert_float(Lead.intercept_time(Vector3.ZERO, Vector3(5, 0, 0), s)).is_equal(0.0)
