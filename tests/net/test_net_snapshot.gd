extends GdUnitTestSuite
## The packed snapshot pipeline on the real M1 sim (T040, T041): sections per owner,
## view-key messages shared, clients that follow the stream hold the server's model, and
## dead reckoning stays wrap-aware across a site seam (D124, D125).

const ENEMY: int = M1Encounter.ENEMY_SHIP
const PLAYER: int = M1Encounter.PLAYER_SHIP


## A section of any size (the oversize test).
class BigSection:
	extends SnapshotSection
	var bytes: PackedByteArray

	func update(_world: SimWorld) -> PackedByteArray:
		return bytes

	func full() -> PackedByteArray:
		return bytes


func _world(world_seed: int = 3) -> SimWorld:
	return M1Encounter.new(world_seed, "test", TestDefs.corvette(), TestDefs.raider_enemy()).build()


## Steps two ticks, the snapshot interval.
func _step2(world: SimWorld) -> void:
	world.step()
	world.step()
	world.drain_events()


# FT: FT-NET-008, FT-NET-040
# Four views join at different times and follow the delta stream: each holds exactly
# the server's contact, near and block models, and every contact's dead-reckoned
# position stays within the tolerance of the copied truth.
func test_views_track_server_model() -> void:
	var world: SimWorld = _world()
	var helm: HelmInputCommand = HelmInputCommand.new()
	helm.ship_id = PLAYER
	helm.throttle = 1.0
	helm.rotation = Vector3(0.2, 0.3, 0.0)
	world.submit(helm)
	var b: SnapshotBuilder = SnapshotBuilder.new()
	var keys: Array = [
		StationViews.key(PLAYER, "helm"),
		StationViews.key(PLAYER, "engineering"),
		# Relay and Science shared their shortcuts with Tactical (D210), so its view is
		# the unfiltered truth.
		StationViews.key(PLAYER, "tactical", "easy#track_feeds,weak_points"),
		StationViews.key(PLAYER, "viewer"),
	]
	var p_units: int = NetCodec.period_units(world.kin.period)
	var states: Array[NetViewState] = [null, null, null, null]
	var copy: SimWorld
	for snap: int in range(1, 121):
		_step2(world)
		if snap == 100:
			var fire: FireCommand = FireCommand.new()
			fire.ship_id = PLAYER
			world.submit(fire)
		copy = SimCopy.of(world)
		b.build(copy, snap, keys)
		for i: int in keys.size():
			if snap < 1 + 25 * i:
				continue
			var is_full: bool = states[i] == null
			if is_full:
				states[i] = NetViewState.new(p_units)
			assert_bool(states[i].apply(b.message(keys[i], is_full))).is_true()
	var contacts: ContactsSection = b.section(
		StationViews.Section.CONTACTS, world.faction_of(PLAYER)
	)
	assert_int(contacts.model.size()).is_equal(2)
	for i: int in keys.size():
		var st: NetViewState = states[i]
		assert_int(st.rejected).is_equal(0)
		assert_int(st.full_count).is_equal(1)
		assert_dict(st.contacts["model"]).is_equal(contacts.model)
		assert_dict(st.contacts["info"]).is_equal(contacts.info)
		assert_str(st.callsign(ENEMY)).is_not_empty()
		var entry: String = StationViews.parse_key(keys[i])[1]
		for kind: int in StationViews.sections_of(entry):
			if StationViews.BLOCKS.has(kind):
				var truth: Dictionary = NetBlock.decode(
					StationViews.BLOCKS[kind], StationViews.block_bytes(kind, copy, PLAYER)
				)
				assert_dict(st.blocks[kind]).is_equal(truth)
		if StationViews.sections_of(entry).has(StationViews.Section.NEAR):
			var near: NearSection = b.section(StationViews.Section.NEAR, PLAYER)
			assert_dict(st.near).is_equal(near.client_model())
		for id: int in st.contacts["model"]:
			var truth: PackedFloat64Array = copy.kin.point_at(id, Vector3.ZERO)
			var err: float = st.contact_position(id).distance_to(
				Vector3(truth[0], truth[1], truth[2])
			)
			assert_float(err).is_less(0.5 * sqrt(3.0) + 0.1)
	# Helm, Tactical and the viewer see the shot as a tracer; Engineering doesn't.
	var proj: ProjectilesSection = b.section(StationViews.Section.PROJECTILES, PLAYER)
	assert_int(proj.model.size()).is_equal(1)
	for i: int in [0, 2, 3]:
		assert_dict(states[i].projectiles).is_equal(proj.model)
	assert_dict(states[1].projectiles).is_empty()
	assert_bool(states[1].blocks.has(StationViews.Section.ENGINEERING)).is_true()
	assert_bool(states[1].blocks.has(StationViews.Section.HELM)).is_false()
	assert_bool(states[2].blocks.has(StationViews.Section.MOUNTS)).is_true()


# FT: FT-NET-040
# A view key's chunks are assembled once per snapshot and the same buffers are handed
# to every client holding the key; distinct keys each cost one message.
func test_message_shared_per_view_key() -> void:
	var world: SimWorld = _world()
	var b: SnapshotBuilder = SnapshotBuilder.new()
	var keys: Array = [StationViews.key(PLAYER, "helm"), StationViews.key(PLAYER, "viewer")]
	_step2(world)
	b.build(SimCopy.of(world), 1, keys)
	b.take_counts()
	var first: Array[PackedByteArray] = b.chunks(keys[0], false)
	for i: int in 5:
		assert_bool(is_same(b.chunks(keys[0], false), first)).is_true()
	b.chunks(keys[1], false)
	b.chunks(keys[1], true)
	var c: Dictionary = b.take_counts()
	assert_int(c["delta_messages"]).is_equal(2)
	assert_int(c["full_messages"]).is_equal(1)


# FT: FT-NET-008
# Joint views see the union of their stations' sections; Captain and Viewer hold no
# crew commands; the dev entry holds every station.
func test_station_views_map_entries() -> void:
	var tactical: Array[int] = StationViews.sections_of("tactical")
	for kind: int in StationViews.sections_of("helm") + StationViews.sections_of("weapons"):
		assert_bool(tactical.has(kind)).is_true()
	assert_bool(StationViews.sections_of("science").has(StationViews.Section.HELM)).is_false()
	assert_array(StationViews.stations_of("viewer")).is_empty()
	assert_array(StationViews.stations_of(StationViews.ALL)).is_equal(StationViews.CREW)
	assert_str(StationViews.station_of_command(&"fire")).is_equal("weapons")
	assert_str(StationViews.station_of_command(&"reset_ship")).is_equal("")
	assert_bool(StationViews.is_entry(StationViews.ALL)).is_false()
	assert_bool(StationViews.is_entry(StationViews.ALL, true)).is_true()
	assert_int(StationViews.catalogue(false).size()).is_equal(6 + 15 + 2)


# FT: FT-NET-040
# The copy handed to the net thread holds the world's state (every table column, the
# RNG states) and stays unchanged while the world steps on.
func test_sim_copy_is_detached() -> void:
	var world: SimWorld = _world()
	for i: int in 30:
		world.step()
	var copy: SimWorld = SimCopy.of(world)
	var columns_at_copy: PackedByteArray = _columns(world)
	assert_bool(_columns(copy) == columns_at_copy).is_true()
	assert_array(copy.rng.states()).is_equal(world.rng.states())
	assert_str(KnowledgeSystem.callsign(copy, 1, ENEMY)).is_equal(
		KnowledgeSystem.callsign(world, 1, ENEMY)
	)
	var copy_hash: String = copy.state_hash()
	for i: int in 30:
		world.step()
	assert_bool(_columns(copy) == columns_at_copy).is_true()
	assert_bool(_columns(world) == columns_at_copy).is_false()
	assert_str(copy.state_hash()).is_equal(copy_hash)


func _columns(world: SimWorld) -> PackedByteArray:
	var out: PackedByteArray = var_to_bytes([world.tick, world.kin.period])
	for t: SimTable in world.tables():
		out.append_array(var_to_bytes(t.columns()))
	return out


# FT: FT-NET-008
# A contact flying across the +X face of the site (D124) is dead reckoned through the
# seam: no absolute record after the first, and the client's position, wrapped, stays
# within the tolerance of the truth.
func test_contacts_wrap_across_the_seam() -> void:
	var world: SimWorld = _world()
	var half: float = 0.5 * world.kin.period
	world.kin.place(PLAYER, half - 1500.0, 0.0, 0.0)
	world.kin.place(ENEMY, half - 150.0, 0.0, -2000.0)
	world.kin.vel[ENEMY] = Vector3(120.0, 0.0, 0.0)
	var b: SnapshotBuilder = SnapshotBuilder.new()
	var key: String = StationViews.key(PLAYER, "relay")
	var st: NetViewState = NetViewState.new(NetCodec.period_units(world.kin.period))
	var crossed: bool = false
	var records: int = 0
	for snap: int in range(1, 91):
		_step2(world)
		world.kin.vel[ENEMY] = Vector3(120.0, 0.0, 0.0)
		var copy: SimWorld = SimCopy.of(world)
		b.build(copy, snap, [key])
		var bytes: PackedByteArray = b.message(key, snap == 1)
		assert_bool(st.apply(bytes)).is_true()
		var contacts: ContactsSection = b.section(StationViews.Section.CONTACTS, 1)
		if contacts.model[ENEMY][2] == copy.tick:
			records += 1
		var truth: PackedFloat64Array = copy.kin.point_at(ENEMY, Vector3.ZERO)
		if truth[0] < 0.0:
			crossed = true
		assert_bool(st.contacts["model"].has(ENEMY)).is_true()
		var got: Vector3 = st.contact_position(ENEMY)
		var d: Vector3 = Vector3(truth[0], truth[1], truth[2]) - got
		d.x = wrapf(d.x, -half, half)
		assert_float(d.length()).is_less(0.5 * sqrt(3.0) + 0.1)
	assert_bool(crossed).is_true()
	# 90 snapshots, refreshed at most every few: the seam itself forced no extra record.
	assert_int(records).is_less(20)


# FT: FT-NET-008
# A contact entering a ship's NEAR range gets the faction model's record, which may be
# older than the snapshot: the delta carries its age, so the client's model matches the
# server's tick for tick.
func test_near_member_added_later_carries_its_age() -> void:
	var world: SimWorld = _world()
	var orient: OrientModel = OrientModel.new()
	var near: NearSection = NearSection.new(PLAYER, orient)
	var client: Dictionary = {}
	_step2(world)
	var recorded_at: int = world.tick
	orient.update(world, {ENEMY: true})
	NearSection.apply(client, _buf(near.update_members(world, {})), false, world.tick)
	for i: int in 10:
		_step2(world)
	# The shared model isn't refreshed (another ship of the faction keeps it): ENEMY joins
	# this ship's set with the record from 20 ticks ago.
	NearSection.apply(client, _buf(near.update_members(world, {ENEMY: true})), false, world.tick)
	assert_dict(client).is_equal(near.client_model())
	assert_int(client[ENEMY][2]).is_equal(recorded_at)
	var full: Dictionary = {}
	NearSection.apply(full, _buf(near.full()), true, world.tick)
	assert_dict(full).is_equal(client)


func _buf(bytes: PackedByteArray) -> StreamPeerBuffer:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.data_array = bytes
	return buf


# FT: FT-NET-008
# A section of 0xFFFF bytes or more is sent with the long length, never dropped: the
# client reads it and every section after it, full or delta.
func test_oversize_section_is_sent_with_a_long_length() -> void:
	var world: SimWorld = _world()
	var b: SnapshotBuilder = SnapshotBuilder.new()
	var key: String = StationViews.key(PLAYER, "helm")
	_step2(world)
	b.build(SimCopy.of(world), 1, [key])
	var kin: PackedByteArray = b.section(StationViews.Section.KIN, PLAYER).full()
	var big: BigSection = BigSection.new(StationViews.Section.KIN, PLAYER)
	big.bytes = kin.duplicate()
	big.bytes.resize(70_000)
	b._sections[SnapshotBuilder._skey(StationViews.Section.KIN, PLAYER)] = big
	var st: NetViewState = NetViewState.new(NetCodec.period_units(world.kin.period))
	var full: PackedByteArray = b.message(key, true)
	assert_int(full.size()).is_greater(70_000)
	assert_bool(st.apply(full)).is_true()
	assert_array(st.kinds).is_equal(StationViews.sections_of("helm"))
	assert_dict(st.kin).is_equal(KinSection.read(_buf(kin)))
	_step2(world)
	b.build(SimCopy.of(world), 2, [key])
	assert_bool(st.apply(b.message(key, false))).is_true()
	assert_int(st.rejected).is_equal(0)
