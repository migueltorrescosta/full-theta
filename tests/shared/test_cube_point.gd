extends GdUnitTestSuite
## CubePoint (shared/, D104, D401, FT-SIM-035): one 64-bit point at every position API,
## three float64 columns in a table, and the column helpers hot loops use.

## A coordinate float32 cannot hold: at 200 km its spacing is 1/64 m (D104).
const FINE: float = 199999.0 + 1.0 / 1024.0


# FT: FT-SIM-035
func test_a_point_keeps_64_bit_coordinates() -> void:
	var p: PackedFloat64Array = CubePoint.make(FINE, -FINE, 0.5)
	assert_float(p[0]).is_equal(FINE)
	assert_float(p[1]).is_equal(-FINE)
	assert_bool(CubePoint.is_valid(p)).is_true()
	assert_float(CubePoint.to_vector3(p).x).is_not_equal(FINE)
	assert_array(CubePoint.make()).is_equal(PackedFloat64Array([0.0, 0.0, 0.0]))
	assert_array(CubePoint.of(Vector3(1, 2, 3))).is_equal(CubePoint.make(1, 2, 3))


# FT: FT-SIM-035
func test_only_three_finite_coordinates_are_a_point() -> void:
	assert_bool(CubePoint.is_valid(PackedFloat64Array())).is_false()
	assert_bool(CubePoint.is_valid(PackedFloat64Array([1.0, 2.0]))).is_false()
	assert_bool(CubePoint.is_valid(CubePoint.make(0.0, NAN, 0.0))).is_false()
	assert_bool(CubePoint.is_valid(CubePoint.make(INF, 0.0, 0.0))).is_false()


# FT: FT-SIM-035
func test_columns_round_trip_a_point() -> void:
	var xs: PackedFloat64Array = PackedFloat64Array()
	var ys: PackedFloat64Array = PackedFloat64Array()
	var zs: PackedFloat64Array = PackedFloat64Array()
	CubePoint.append(xs, ys, zs, CubePoint.make(1, 2, 3))
	CubePoint.append(xs, ys, zs, CubePoint.make())
	CubePoint.write(xs, ys, zs, 1, CubePoint.make(FINE, 5, 6))
	assert_array(CubePoint.read(xs, ys, zs, 0)).is_equal(CubePoint.make(1, 2, 3))
	assert_array(CubePoint.read(xs, ys, zs, 1)).is_equal(CubePoint.make(FINE, 5, 6))


# FT: FT-SIM-035
# The helpers never change their arguments: packed arrays are shared by reference.
func test_helpers_leave_their_arguments_alone() -> void:
	var p: PackedFloat64Array = CubePoint.make(1, 2, 3)
	var q: PackedFloat64Array = CubePoint.plus(p, Vector3(10, 0, 0))
	assert_array(q).is_equal(CubePoint.make(11, 2, 3))
	assert_array(p).is_equal(CubePoint.make(1, 2, 3))
	var w: SimWorld = SimWorld.new(1)
	var wrapped: PackedFloat64Array = w.kin.wrap_point(p)
	wrapped[0] = 99.0
	assert_array(p).is_equal(CubePoint.make(1, 2, 3))


# FT: FT-SIM-035
# The minimum image across the seam, in 64-bit.
func test_delta_is_the_minimum_image() -> void:
	var kin: Kinematics = SimWorld.new(1).kin
	var h: float = 0.5 * kin.period
	var a: PackedFloat64Array = CubePoint.make(-h + 10.0, 0.0, FINE)
	var b: PackedFloat64Array = CubePoint.make(h - 10.0, 0.0, FINE - 1.0)
	assert_vector(kin.delta(a, b)).is_equal(Vector3(20.0, 0.0, 1.0))
	assert_vector(kin.delta(b, a)).is_equal(Vector3(-20.0, 0.0, -1.0))


# FT: FT-SIM-035
# Kinematics' column helper gives what the point helper gives, with no point per row.
func test_relative_to_column_matches_relative_to_point() -> void:
	var w: SimWorld = SimWorld.new(1)
	var half: float = 0.5 * w.kin.period
	var ship: int = w.spawn_ship(TestDefs.corvette(), 1, CubePoint.make(half - 10.0, 0.0, FINE))
	var xs: PackedFloat64Array = PackedFloat64Array([0.0, -half + 30.0])
	var ys: PackedFloat64Array = PackedFloat64Array([0.0, 5.0])
	var zs: PackedFloat64Array = PackedFloat64Array([0.0, FINE + 2.0])
	var at: PackedFloat64Array = CubePoint.read(xs, ys, zs, 1)
	var rel: Vector3 = w.kin.relative_to_column(ship, xs, ys, zs, 1)
	assert_vector(rel).is_equal(w.kin.relative_to_point(ship, at))
	assert_vector(rel).is_equal(Vector3(40.0, 5.0, 2.0))
