extends GdUnitTestSuite
## The M4 contract's net harness (#11): NetHarness.fleet_server serves a lobby-built session
## of several ships, crews can pick any of them, and the new requests are answered (refused
## `not_implemented` until strand C wires them).

var h: NetHarness


func before_test() -> void:
	h = NetHarness.new(self)


func after_test() -> void:
	await h.free_all()


func test_fleet_server_serves_every_ship() -> void:
	var server: NetServer = h.fleet_server(SessionRules.Mode.TEAMS, 2)
	assert_object(server).is_not_null()
	assert_int(server.session.crew_ships().size()).is_equal(2)
	var c: NetClient = await h.joined(server, "ana", "tactical", 1)
	assert_int(h.session_of(server, c).ship).is_equal(1)


func test_new_requests_are_answered() -> void:
	var server: NetServer = h.fleet_server(SessionRules.Mode.COOP, 2)
	var c: NetClient = await h.welcomed(server, "ana")
	var from: int = h.mark(c)
	c.add_ship("Kestrel II")
	var e: Dictionary = await h.next_event(c, NetProtocol.EVENT_REQUEST_REJECTED, from)
	assert_int(e["payload"]["request"]).is_equal(NetProtocol.Type.SHIP_ADD)
	assert_str(e["payload"]["reason"]).is_equal(ServerSession.NOT_IMPLEMENTED)
