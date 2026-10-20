extends GdUnitTestSuite
## The packed codec (promoted from the S9 spike tests): quaternions, integer dead
## reckoning, wrap-aware residuals (D124, D125), and the block field sets.
# FT: FT-NET-004

const P_UNITS: int = 200000 * 16


func test_quaternion_smallest_three_round_trip() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 3
	for i: int in range(500):
		var axis: Vector3 = Vector3(rng.randf() - 0.5, rng.randf() - 0.5, rng.randf() - 0.5)
		var q: Quaternion = Quaternion(axis.normalized(), rng.randf_range(-PI, PI))
		var back: Quaternion = NetCodec.unpack_quat(NetCodec.pack_quat(q))
		# Within 0.2 degrees.
		assert_float(absf(back.dot(q))).is_greater(cos(deg_to_rad(0.2) * 0.5))


## predict rounds v dt / PRED_DEN half up: +0.5 unit goes to 1, -0.5 to 0.
func test_integer_prediction_rounds_half_up() -> void:
	var half: Vector3i = NetCodec.predict(Vector3i.ZERO, Vector3i(30, -30, -31), 1, P_UNITS)
	assert_that(half).is_equal(Vector3i(1, 0, -1))
	# 150 m/s (2,400 units) for 2 ticks is 5 m = 80 units; 1 m/s for 2 ticks 0.53 units.
	var p: Vector3i = NetCodec.predict(Vector3i.ZERO, Vector3i(2400, -2400, 16), 2, P_UNITS)
	assert_that(p).is_equal(Vector3i(80, -80, 1))
	# The longest prediction at the fastest velocity stays exact in 64-bit.
	var far: Vector3i = NetCodec.predict(Vector3i.ZERO, Vector3i(32767, 0, 0), NetCodec.MAX_AGE, 0)
	assert_int(far.x).is_equal(327670)


func test_positions_wrap_into_the_cube() -> void:
	var half: float = 100000.0
	assert_that(NetCodec.quant_pos(half - 0.01, 0.0, -half, P_UNITS)).is_equal(
		Vector3i(-P_UNITS / 2, 0, -P_UNITS / 2)
	)
	(
		assert_that(
			NetCodec.diff(
				Vector3i(P_UNITS / 2 - 5, 0, 0), Vector3i(-P_UNITS / 2 + 5, 0, 0), P_UNITS
			)
		)
		. is_equal(Vector3i(-10, 0, 0))
	)
	# Predicting across the +X face comes back in at -X.
	var p: Vector3i = NetCodec.predict(
		Vector3i(P_UNITS / 2 - 16, 0, 0), Vector3i(1920, 0, 0), 60, P_UNITS
	)
	assert_that(p).is_equal(Vector3i(-P_UNITS / 2 + 1904, 0, 0))


func test_kinematic_record_round_trip_all_modes() -> void:
	var model: Dictionary = {7: [Vector3i(100, 200, 300), Vector3i(64, 0, -64), 10]}
	var cases: Array = [
		[Vector3i(105, 199, 296), Vector3i(64, 0, -64)],
		[Vector3i(2000, 199, 296), Vector3i(100, 0, -64)],
		[Vector3i(900000, -5, 296), Vector3i(9000, 0, -64)],
	]
	for c: Array in cases:
		var entry: Array = model[7]
		var pred: Vector3i = NetCodec.predict(entry[0], entry[1], 4, P_UNITS)
		var buf: StreamPeerBuffer = StreamPeerBuffer.new()
		NetCodec.put_kin(buf, 7, c[0], c[1], pred, entry[1], false, P_UNITS)
		buf.seek(0)
		var rec: Array = NetCodec.get_kin(buf, model, 14, P_UNITS)
		assert_that(rec[1]).is_equal(c[0])
		assert_that(rec[2]).is_equal(c[1])


## A contact that crossed the seam is a small residual, not an absolute record.
func test_residual_across_the_seam_is_small() -> void:
	var model: Dictionary = {3: [Vector3i(P_UNITS / 2 - 10, 0, 0), Vector3i(0, 0, 0), 0]}
	var now: Vector3i = Vector3i(-P_UNITS / 2 + 20, 0, 0)
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	var pred: Vector3i = NetCodec.predict(model[3][0], model[3][1], 2, P_UNITS)
	NetCodec.put_kin(buf, 3, now, Vector3i.ZERO, pred, Vector3i.ZERO, false, P_UNITS)
	# id 2 + flags 1 + 3 x s8 residual.
	assert_int(buf.get_size()).is_equal(6)
	buf.seek(0)
	assert_that(NetCodec.get_kin(buf, model, 2, P_UNITS)[1]).is_equal(now)


func test_residual_for_an_unknown_id_is_rejected() -> void:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	NetCodec.put_kin(
		buf, 9, Vector3i.ONE, Vector3i.ONE, Vector3i.ZERO, Vector3i.ZERO, false, P_UNITS
	)
	buf.seek(0)
	assert_array(NetCodec.get_kin(buf, {}, 1, P_UNITS)).is_empty()


func test_block_round_trip() -> void:
	for kind: int in StationViews.BLOCKS:
		var schema: Array = StationViews.BLOCKS[kind]
		var values: Dictionary = {}
		for field: Array in schema:
			values[field[0]] = _sample(field[1])
		var back: Dictionary = NetBlock.decode(schema, NetBlock.encode(schema, values))
		assert_dict(back).is_equal(values)


func _sample(type: Variant) -> Variant:
	if type is Array:
		var row: Dictionary = {}
		for field: Array in type[1]:
			row[field[0]] = _sample(field[1])
		var rows: Array[Dictionary] = [row, row.duplicate()]
		return rows
	var samples: Dictionary = {
		"bool": true,
		"u8": 200,
		"u16": 60000,
		"s16": -3,
		"u32": 4000000000,
		"s32": -70000,
		"f32": 1.5,
		"v3f": Vector3(1.5, -2.0, 0.25),
		"v3n": Vector3(0.0, -1.0, 0.0),
	}
	return samples[type]
