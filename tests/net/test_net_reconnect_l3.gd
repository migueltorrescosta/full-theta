extends GdUnitTestSuite
## L3 reconnect tests (T045): the token survives a client relaunch; rejoining restores
## ship, pick and claims if still free, else returns the player to that ship's pick
## screen; a rejoined client converges within one snapshot interval of its full
## snapshot.

const PLAYER: int = NetHarness.PLAYER

var h: NetHarness
var _token_path: String = ""


func before_test() -> void:
	h = NetHarness.new(self)
	_token_path = "user://test_token_%d.json" % randi()


func after_test() -> void:
	SessionTokenFile.remove(_token_path)
	await h.free_all()


## Saves the client's token as the game does, drops it (a crash), and starts a new
## client process-equivalent (a fresh NetClient) from the stored file.
func _relaunch(server: NetServer, c: NetClient) -> NetClient:
	var file: SessionTokenFile = SessionTokenFile.make(c.token, "127.0.0.1", server.port())
	assert_int(file.save(_token_path)).is_equal(OK)
	if h.clients.has(c):
		await h.drop(server, c)
	var stored: SessionTokenFile = SessionTokenFile.load_from(_token_path)
	assert_object(stored).is_not_null()
	var fresh: NetClient = await h.welcomed(server, c.name + "'", stored.token)
	return fresh


# FT: FT-NET-025, FT-NET-026, FT-M1-013
# A client killed and relaunched within the grace period presents its stored token and
# gets the same session, ship, pick and claims back, with a full snapshot.
func test_relaunch_within_grace_restores_everything() -> void:
	var server: NetServer = h.server()
	var gunner: NetClient = await h.joined(server, "gunner", "weapons")
	var other: NetClient = await h.joined(server, "other", "tactical")
	var session: NetSession = h.session_of(server, gunner)
	assert_int(server.session.claims.holder(PLAYER, "mount:0")).is_equal(session.id)
	var again: NetClient = await _relaunch(server, gunner)
	assert_bool(again.welcome["resumed"]).is_true()
	assert_int(again.session_id).is_equal(session.id)
	assert_int(again.welcome["ship"]).is_equal(PLAYER)
	assert_str(again.welcome["entry"]).is_equal("weapons")
	assert_bool(await h.until(func() -> bool: return again.view.full_count >= 1)).is_true()
	assert_bool(again.view.blocks.has(StationViews.Section.MOUNTS)).is_true()
	var mine: Callable = func() -> bool:
		var claims: Dictionary = again.view.ownership.get("claims", {})
		return claims.has("mount:0") and claims["mount:0"][0] == session.id
	assert_bool(await h.until(mine)).is_true()
	assert_int(server.session.claims.holder(PLAYER, "mount:0")).is_equal(session.id)
	assert_bool(other.is_welcomed()).is_true()


# FT: FT-NET-026, FT-M1-013
# After the grace ran out: a Weapons player whose mount was claimed meanwhile gets
# Weapons back without the mount; a Captain whose seat was taken meanwhile is returned
# to that ship's pick screen (ship set, no entry, no snapshots).
func test_rejoin_after_grace_restores_only_what_is_free() -> void:
	var server: NetServer = h.server(false, 0.5)
	var gunner: NetClient = await h.joined(server, "gunner", "weapons")
	var second: NetClient = await h.joined(server, "second", "weapons")
	var cap: NetClient = await h.joined(server, "cap", "captain")
	var g_session: NetSession = h.session_of(server, gunner)
	var c_session: NetSession = h.session_of(server, cap)
	assert_int(server.session.claims.holder(PLAYER, "mount:0")).is_equal(g_session.id)
	var file: SessionTokenFile = SessionTokenFile.make(gunner.token, "127.0.0.1", server.port())
	file.save(_token_path)
	var cap_token: String = cap.token
	await h.drop(server, gunner)
	await h.drop(server, cap)
	assert_bool(await h.lapsed(g_session)).is_true()
	assert_bool(await h.lapsed(c_session)).is_true()
	# second is now alone on Weapons: it holds the mount (FT-NET-044).
	var s_id: int = h.session_of(server, second).id
	assert_int(server.session.claims.holder(PLAYER, "mount:0")).is_equal(s_id)
	var taker: NetClient = await h.joined(server, "taker", "captain")
	assert_str(h.session_of(server, taker).entry).is_equal("captain")
	var again: NetClient = await h.welcomed(
		server, "gunner'", SessionTokenFile.load_from(_token_path).token
	)
	assert_int(again.session_id).is_equal(g_session.id)
	assert_str(again.welcome["entry"]).is_equal("weapons")
	assert_int(server.session.claims.holder(PLAYER, "mount:0")).is_equal(s_id)
	var cap_again: NetClient = await h.welcomed(server, "cap'", cap_token)
	assert_int(cap_again.session_id).is_equal(c_session.id)
	assert_int(cap_again.welcome["ship"]).is_equal(PLAYER)
	assert_str(cap_again.welcome["entry"]).is_equal("")
	assert_bool(c_session.has_pick()).is_false()
	assert_dict(await h.next_event(cap_again, NetProtocol.EVENT_LOBBY)).is_not_empty()
	await h.wait(300)
	assert_int(cap_again.view.full_count).is_equal(0)


# FT: FT-NET-027
# A client drops mid-run and rejoins: its full snapshot equals the server's model at
# that snapshot's tick (blocks and own kinematics exactly, contacts within the dead
# reckoning tolerance), and so does the next snapshot: it has converged within one
# snapshot interval.
func test_rejoined_client_converges_within_one_snapshot() -> void:
	var server: NetServer = h.server(true)
	var c: NetClient = await h.joined(server, "solo", StationViews.ALL)
	assert_bool(await h.start(server, c)).is_true()
	c.helm(1.0, Vector3(0.2, 0.1, 0.0))
	c.set_pips(SubsystemDef.Kind.ENGINES, 2)
	await h.wait(300)
	var models: Dictionary = {}
	var record: Callable = func() -> void: models[server.world.tick] = _model(server.world)
	c.drop()
	await h.until(func() -> bool: return not h.session_of(server, c).connected())
	c.keep_raw = true
	c.raw_snapshots = {}
	c.resume()
	var two: Callable = func() -> bool:
		record.call()
		return c.is_welcomed() and c.raw_snapshots.size() >= 3
	assert_bool(await h.until(two)).is_true()
	var seqs: Array = c.raw_snapshots.keys()
	seqs.sort()
	var full_seq: int = -1
	for seq: int in seqs:
		if SnapshotBuilder.peek(c.raw_snapshots[seq])[1]:
			full_seq = seq
			break
	assert_int(full_seq).is_greater(0)
	var view: NetViewState = NetViewState.new(NetCodec.period_units(c.welcome["period"]))
	for seq: int in [full_seq, full_seq + 1]:
		assert_bool(c.raw_snapshots.has(seq)).is_true()
		assert_bool(view.apply(c.raw_snapshots[seq])).is_true()
		(
			assert_bool(models.has(view.tick))
			. override_failure_message("no server model at tick %d" % view.tick)
			. is_true()
		)
		_assert_converged(view, models[view.tick])
	assert_int(view.tick).is_greater(0)


## The server's model of the player's ship at the current tick: KIN and block bytes as
## the snapshot builder would encode them, and contact positions.
func _model(world: SimWorld) -> Dictionary:
	var kin: KinSection = KinSection.new(StationViews.Section.KIN, PLAYER)
	var blocks: Dictionary = {}
	for kind: int in StationViews.BLOCKS:
		blocks[kind] = StationViews.block_bytes(kind, world, PLAYER)
	var contacts: Dictionary = {}
	for id: int in ContactsSection.known(world, world.faction_of(PLAYER)):
		var p: PackedFloat64Array = world.kin.point_at(id, Vector3.ZERO)
		contacts[id] = Vector3(p[0], p[1], p[2])
	return {"kin": kin.update(world), "blocks": blocks, "contacts": contacts}


func _assert_converged(view: NetViewState, model: Dictionary) -> void:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.data_array = model["kin"]
	assert_dict(view.kin).is_equal(KinSection.read(buf))
	for kind: int in model["blocks"]:
		var truth: Dictionary = NetBlock.decode(StationViews.BLOCKS[kind], model["blocks"][kind])
		assert_dict(view.blocks[kind]).is_equal(truth)
	var ids: Array = (view.contacts["model"] as Dictionary).keys()
	ids.sort()
	var want: Array = (model["contacts"] as Dictionary).keys()
	want.sort()
	assert_array(ids).is_equal(want)
	for id: int in want:
		var err: float = view.contact_position(id).distance_to(model["contacts"][id])
		assert_float(err).is_less(0.5 * sqrt(3.0) + 0.1)
