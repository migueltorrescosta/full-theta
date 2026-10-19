extends GdUnitTestSuite
## S9 spike: the packed snapshot codec and per-view-key encoding (spike
## evidence for FT-NET-008, FT-NET-028 and FT-NET-040; the ids stay pending
## until #6 promotes the code).


func test_quaternion_smallest_three_round_trip() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 3
	for i: int in range(500):
		var axis: Vector3 = Vector3(rng.randf() - 0.5, rng.randf() - 0.5, rng.randf() - 0.5)
		var q: Quaternion = Quaternion(axis.normalized(), rng.randf_range(-PI, PI))
		var back: Quaternion = S9Codec.unpack_quat(S9Codec.pack_quat(q))
		# Within 0.2 degrees.
		assert_float(absf(back.dot(q))).is_greater(cos(deg_to_rad(0.2) * 0.5))


## predict rounds v dt / PRED_DEN half up: +0.5 unit goes to 1, -0.5 to 0.
func test_integer_prediction_rounds_half_up() -> void:
	assert_that(S9Codec.PRED_OFF).is_equal(Vector3i(62914800, 62914800, 62914800))
	var half: Vector3i = S9Codec.predict(Vector3i.ZERO, Vector3i(120, -120, -121), 1)
	assert_that(half).is_equal(Vector3i(1, 0, -1))
	var p: Vector3i = S9Codec.predict(Vector3i(0, 0, 0), Vector3i(9600, -9600, 64), 2)
	# 150 m/s for 2 ticks is 5 m = 80 units; 1 m/s for 2 ticks is 0.53 units.
	assert_that(p).is_equal(Vector3i(80, -80, 1))


func test_kinematic_record_round_trip_all_modes() -> void:
	var model: Dictionary = {7: [Vector3i(100, 200, 300), Vector3i(64, 0, -64), 10]}
	var cases: Array = [
		[Vector3i(105, 199, 296), Vector3i(64, 0, -64)],
		[Vector3i(2000, 199, 296), Vector3i(100, 0, -64)],
		[Vector3i(900000, -5, 296), Vector3i(9000, 0, -64)],
	]
	for c: Array in cases:
		var entry: Array = model[7]
		var pred: Vector3i = S9Codec.predict(entry[0], entry[1], 4)
		var buf: StreamPeerBuffer = StreamPeerBuffer.new()
		S9Codec.put_kin(buf, 7, c[0], c[1], pred, entry[1], false)
		buf.seek(0)
		var rec: Array = S9Codec.get_kin(buf, model, 14)
		assert_that(rec[1]).is_equal(c[0])
		assert_that(rec[2]).is_equal(c[1])


## Clients that join at different times and follow the delta stream hold
## exactly the server's model, and every known contact's dead-reckoned
## position stays within the tolerance of the true one.
func test_views_track_server_model_and_truth() -> void:
	var world: S9World = S9World.new(5)
	world.setup_benchmark(100, 500)
	var b: S9Builder = S9Builder.new(world, {"ships": 6, "pos_tol": 0.5})
	var seats: Array = [[0, "helm"], [1, "engineering"], [2, "viewer"], [3, "relay"]]
	var states: Array[S9ViewState] = []
	for s: Array in seats:
		states.append(null)
	for snap: int in range(1, 91):
		world.step()
		b.note_tick_events()
		world.step()
		b.note_tick_events()
		b.build(snap, 0)
		for i: int in range(seats.size()):
			# Seat i joins at snapshot 1 + 20 i with a full snapshot.
			if snap < 1 + 20 * i:
				continue
			var is_full: bool = states[i] == null
			if is_full:
				states[i] = S9ViewState.new()
			var ok: bool = states[i].apply(b.message(seats[i][0], seats[i][1], "normal", is_full))
			assert_bool(ok).is_true()
	assert_int(b.take_counts()["delta_messages"]).is_less_equal(90 * seats.size())
	for i: int in range(seats.size()):
		var st: S9ViewState = states[i]
		var ship: int = seats[i][0]
		assert_int(st.out_of_order).is_equal(0)
		assert_dict(st.radar).is_equal(b.radar_model(0))
		assert_int(st.radar.size()).is_equal(100)
		var entry: String = seats[i][1]
		if S9Views.SECTIONS[entry].has(S9Near.KIND):
			assert_dict(st.near).is_equal(b.near_model(ship))
			assert_array(st.proj.keys()).contains_exactly_in_any_order(b.proj_model(ship).keys())
		else:
			assert_dict(st.near).is_empty()
		for id: int in st.radar:
			var e: Array = st.radar[id]
			var pred: Vector3i = S9Codec.predict(e[0], e[1], st.tick - int(e[2]))
			var err: float = S9Codec.pos_of(pred).distance_to(world.ship_pos(id))
			assert_float(err).is_less(0.5 * sqrt(3.0) + 0.1)


func test_message_shared_per_view_key() -> void:
	var world: S9World = S9World.new(6)
	world.setup_benchmark(100, 500)
	var b: S9Builder = S9Builder.new(world)
	world.step()
	b.build(1, 0)
	b.take_counts()
	var first: PackedByteArray = b.message(0, "viewer", "normal", false)
	for i: int in range(5):
		assert_that(b.message(0, "viewer", "normal", false)).is_equal(first)
	b.message(1, "viewer", "normal", false)
	b.message(0, "helm", "normal", false)
	var c: Dictionary = b.take_counts()
	assert_int(c["delta_messages"]).is_equal(3)


func test_projectile_refire_bumps_generation() -> void:
	var world: S9World = S9World.new(7)
	world.setup_benchmark(10, 20)
	var before: int = 0
	for g: int in world.proj_gen:
		before += g
	assert_int(before).is_equal(20)
	for i: int in range(200):
		world.step()
	var after: int = 0
	for g: int in world.proj_gen:
		after += g
	# Every projectile lives at most 180 ticks, so each was refired.
	assert_int(after).is_greater_equal(40)
