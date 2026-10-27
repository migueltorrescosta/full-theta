extends GdUnitTestSuite
## L3: who switches the main screen over loopback, and what the Captain and the status
## view get. The Captain switches it; Relay only while no Captain is seated, counting the
## Captain's reconnect grace; nobody else. The view reaches every screen of the ship.

const PLAYER: int = NetHarness.PLAYER
const S = StationViews.Section

var h: NetHarness


func before_test() -> void:
	h = NetHarness.new(self)


func after_test() -> void:
	await h.free_all()


func _rejected(c: NetClient, from: int) -> String:
	var e: Dictionary = await h.next_event(
		c,
		NetProtocol.EVENT_REQUEST_REJECTED,
		from,
		func(ev: Dictionary) -> bool: return ev["payload"]["request"] == NetProtocol.Type.MAIN_VIEW
	)
	return str(e.get("payload", {}).get("reason", ""))


## The latest main_view event's view at the client, waiting for `view`.
func _sees(c: NetClient, view: int) -> bool:
	return await h.until(
		func() -> bool:
			return (
				int(h.last_event(c, NetProtocol.EVENT_MAIN_VIEW).get("payload", {}).get("view", -1))
				== view
			)
	)


# FT: FT-MSC-005, FT-RLY-010, FT-CPT-001
# With no Captain seated Relay switches the view for every screen of the ship; the
# others (a gunner, a viewer) can't.
func test_relay_switches_the_view_without_a_captain() -> void:
	var server: NetServer = h.server()
	var relay: NetClient = await h.joined(server, "relay", "relay")
	var helm: NetClient = await h.joined(server, "helm", "helm")
	var viewer: NetClient = await h.joined(server, "viewer", StationViews.VIEWER)
	relay.set_main_view(MainScreen.View.TACTICAL)
	assert_bool(await _sees(viewer, MainScreen.View.TACTICAL)).is_true()
	assert_bool(await _sees(helm, MainScreen.View.TACTICAL)).is_true()
	assert_str(h.last_event(viewer, NetProtocol.EVENT_MAIN_VIEW)["payload"]["by"]).is_equal("relay")
	for c: NetClient in [helm, viewer]:
		var from: int = h.mark(c)
		c.set_main_view(MainScreen.View.STATUS)
		assert_str(await _rejected(c, from)).is_equal(CommandGate.NOT_ALLOWED)
	var from: int = h.mark(relay)
	relay.set_main_view(9)
	assert_str(await _rejected(relay, from)).is_equal(MainScreen.BAD_VIEW)


# FT: FT-MSC-005, FT-RLY-010, FT-CPT-001
# A seated Captain alone switches it, and the seat counts through the reconnect grace;
# once the grace lapses Relay has it again.
func test_the_captain_alone_switches_while_seated_even_in_grace() -> void:
	var server: NetServer = h.server(false, 1.0)
	var relay: NetClient = await h.joined(server, "relay", "relay")
	var cap: NetClient = await h.joined(server, StationViews.CAPTAIN, StationViews.CAPTAIN)
	var viewer: NetClient = await h.joined(server, "viewer", StationViews.VIEWER)
	var from: int = h.mark(relay)
	relay.set_main_view(MainScreen.View.CHASE)
	assert_str(await _rejected(relay, from)).is_equal(MainScreen.CAPTAIN_SEATED)
	cap.set_main_view(MainScreen.View.TARGET)
	assert_bool(await _sees(viewer, MainScreen.View.TARGET)).is_true()
	assert_bool(await _sees(relay, MainScreen.View.TARGET)).is_true()
	var session: NetSession = h.session_of(server, cap)
	assert_bool(await h.drop(server, cap)).is_true()
	from = h.mark(relay)
	relay.set_main_view(MainScreen.View.CHASE)
	assert_str(await _rejected(relay, from)).is_equal(MainScreen.CAPTAIN_SEATED)
	assert_bool(await h.lapsed(session)).is_true()
	relay.set_main_view(MainScreen.View.CHASE)
	assert_bool(await _sees(viewer, MainScreen.View.CHASE)).is_true()


# FT: FT-MSC-006, FT-CPT-001, FT-CPT-004
# The Captain and the viewer get the status view's data: subsystem health and the
# encounter objective; the Captain gets no station block.
func test_captain_and_viewer_get_the_status_block() -> void:
	var server: NetServer = h.server()
	var crew: Array[NetClient] = await h.crew3(server)
	var cap: NetClient = await h.joined(server, StationViews.CAPTAIN, StationViews.CAPTAIN)
	var viewer: NetClient = await h.joined(server, "viewer", StationViews.VIEWER)
	assert_bool(await h.start(server, crew[0])).is_true()
	for c: NetClient in [cap, viewer]:
		assert_bool(await h.until(func() -> bool: return c.view.blocks.has(S.CAPTAIN))).is_true()
		var block: Dictionary = c.view.blocks[S.CAPTAIN]
		assert_int((block["subsystems"] as Array).size()).is_equal(6)
		assert_float(block["subsystems"][0]["health"]).is_greater(0.0)
		assert_int(block["objectives"][0]["kind"]).is_equal(Objectives.Kind.DESTROY_HOSTILES)
		assert_int(block["objectives"][0]["left"]).is_equal(1)
		# The Captain also gets the ship's open request chips (FT-CPT-004).
		var keys: Array = [S.STATUS, S.CAPTAIN] + ([S.CHIPS, S.COMMS] if c == cap else [])
		assert_array(c.view.blocks.keys()).is_equal(keys)
