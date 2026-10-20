extends GdUnitTestSuite
## L3: the main screen over loopback. Any number of viewers get the main-screen state
## only (KIN, STATUS with the decoupled flag the auto-chase needs, CONTACTS, NEAR,
## PROJECTILES; no station blocks, no ownership) and can't change anything.

const PLAYER: int = NetHarness.PLAYER
const S = StationViews.Section
const MAIN_SCREEN: Array[int] = [S.KIN, S.STATUS, S.CONTACTS, S.NEAR, S.PROJECTILES]

var h: NetHarness


func before_test() -> void:
	h = NetHarness.new(self)


func after_test() -> void:
	await h.free_all()


# FT: FT-MSC-004, FT-NET-028, FT-MSC-001
func test_viewers_receive_only_main_screen_state_and_change_nothing() -> void:
	var server: NetServer = h.server()
	var crew: Array[NetClient] = await h.crew3(server)
	var viewers: Array[NetClient] = []
	for k: int in 3:
		viewers.append(await h.joined(server, "viewer%d" % k, StationViews.VIEWER))
	assert_bool(await h.start(server, crew[0])).is_true()
	crew[0].command({"kind": &"helm_decoupled", "decoupled": true})
	var decoupled: Callable = func() -> bool:
		return viewers.all(
			func(v: NetClient) -> bool:
				return bool(v.view.blocks.get(S.STATUS, {}).get("decoupled", false))
		)
	assert_bool(await h.until(decoupled)).is_true()
	for v: NetClient in viewers:
		v.keep_raw = true
	await h.wait(400)
	for v: NetClient in viewers:
		assert_array(v.view.kinds).is_equal(MAIN_SCREEN)
		assert_int(v.raw_snapshots.size()).is_greater(3)
		for data: PackedByteArray in v.raw_snapshots.values():
			for kind: int in _kinds(data):
				assert_array(MAIN_SCREEN).contains([kind])
		assert_dict(v.view.ownership).is_empty()
		assert_array(v.view.blocks.keys()).is_equal([S.STATUS])
		assert_float(v.view.blocks[S.STATUS]["hull"]).is_greater(0.0)
	# Read-only: commands, alert, marks and pings are refused.
	var viewer: NetClient = viewers[0]
	var from: int = h.mark(viewer)
	viewer.command({"kind": &"helm_decoupled", "decoupled": false})
	var refused: Dictionary = await h.next_event(viewer, NetProtocol.EVENT_COMMAND_REJECTED, from)
	assert_str(refused.get("payload", {}).get("reason", "")).is_equal("not_your_station")
	for send: Callable in [
		func() -> void: viewer.set_alert(2),
		func() -> void: viewer.place_mark(-1, "", -1, 0, Vector3.ZERO),
		func() -> void: viewer.ping("point", -1, 0, Vector3.ZERO),
	]:
		from = h.mark(viewer)
		send.call()
		var e: Dictionary = await h.next_event(viewer, NetProtocol.EVENT_REQUEST_REJECTED, from)
		assert_str(e.get("payload", {}).get("reason", "")).is_equal(ServerSession.NOT_CREW)


## Section kinds of a snapshot message.
static func _kinds(data: PackedByteArray) -> Array[int]:
	var out: Array[int] = []
	var at: int = SnapshotBuilder.HEADER_BYTES
	for i: int in data[SnapshotBuilder.HEADER_BYTES - 1]:
		out.append(data[at])
		at += 3 + data.decode_u16(at + 1)
	return out
