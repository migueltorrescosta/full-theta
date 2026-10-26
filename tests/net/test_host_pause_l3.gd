extends GdUnitTestSuite
## L3 tests of the host pause (FT-MIS-040): the co-op host pauses and resumes the
## universe through the pause events; others and PvP sessions are refused.

const PLAYER: int = NetHarness.PLAYER
const SECRET: String = "c0ffee"

var h: NetHarness


func before_test() -> void:
	h = NetHarness.new(self)


func after_test() -> void:
	await h.free_all()


## A started co-op ship: the host on Tactical, Systems and Ops after it.
func _running(server: NetServer) -> Array[NetClient]:
	var crew: Array[NetClient] = []
	var host: NetClient = await h.welcomed(server, "tactical", "", SECRET)
	await h.pick(host, "tactical", PLAYER)
	crew.append(host)
	for entry: String in ["systems", "ops"]:
		crew.append(await h.joined(server, entry, entry))
	assert_bool(await h.start(server, host)).is_true()
	return crew


func _rejected(c: NetClient, from: int) -> String:
	var e: Dictionary = await h.next_event(
		c,
		NetProtocol.EVENT_REQUEST_REJECTED,
		from,
		func(ev: Dictionary) -> bool: return ev["payload"]["request"] == NetProtocol.Type.HOST_PAUSE
	)
	return "" if e.is_empty() else str(e["payload"]["reason"])


func _frozen(server: NetServer, ms: int) -> bool:
	var tick: int = server.world.tick
	await h.wait(ms)
	return server.world.tick == tick


func _stepping(server: NetServer) -> bool:
	var tick: int = server.world.tick
	return await h.until(func() -> bool: return server.world.tick > tick + 3)


# FT: FT-MIS-040, FT-NET-034
# The host pauses: the sim stops, every client gets `pause` with host true, and the
# host's resume restarts the sim with a `resume`.
func test_host_pauses_and_resumes() -> void:
	var server: NetServer = h.server(false, 10.0, SECRET)
	var crew: Array[NetClient] = await _running(server)
	var from: int = h.mark(crew[1])
	crew[0].host_pause(true)
	var pause: Dictionary = await h.next_event(crew[1], NetProtocol.EVENT_PAUSE, from)
	assert_bool(pause["payload"]["host"]).is_true()
	assert_bool(server.session.host_paused).is_true()
	assert_bool(server.session.sim_running()).is_false()
	assert_bool(await _frozen(server, 300)).is_true()
	crew[0].host_pause(false)
	var resume: Dictionary = await h.next_event(crew[1], NetProtocol.EVENT_RESUME, from)
	assert_bool(resume["payload"]["host"]).is_true()
	assert_bool(await _stepping(server)).is_true()


# FT: FT-MIS-040
# Only the host may pause; anyone else is refused `not_host` and the sim keeps going.
func test_non_host_is_refused() -> void:
	var server: NetServer = h.server(false, 10.0, SECRET)
	var crew: Array[NetClient] = await _running(server)
	var from: int = h.mark(crew[1])
	crew[1].host_pause(true)
	assert_str(await _rejected(crew[1], from)).is_equal("not_host")
	assert_bool(server.session.host_paused).is_false()
	assert_bool(await _stepping(server)).is_true()


# FT: FT-MIS-040
# A dedicated server has no host: nobody may pause.
func test_dedicated_server_refuses() -> void:
	var server: NetServer = h.server()
	var crew: Array[NetClient] = await h.crew3(server)
	assert_bool(await h.start(server, crew[0])).is_true()
	var from: int = h.mark(crew[0])
	crew[0].host_pause(true)
	assert_str(await _rejected(crew[0], from)).is_equal("pvp_no_pause")
	assert_bool(server.session.host_paused).is_false()


# FT: FT-MIS-040
# Two hostile crew factions (PvP): even the host is refused.
func test_pvp_refuses_the_host() -> void:
	var server: NetServer = h.server(false, 10.0, SECRET)
	var crew: Array[NetClient] = await _running(server)
	server.session._crew_ships = [
		{"id": 0, "def": "a", "name": "A", "faction": 0},
		{"id": 1, "def": "b", "name": "B", "faction": 1},
	]
	assert_bool(server.session.host_pause.is_pvp()).is_true()
	var from: int = h.mark(crew[0])
	crew[0].host_pause(true)
	assert_str(await _rejected(crew[0], from)).is_equal("pvp_no_pause")
	assert_bool(server.session.host_paused).is_false()
	assert_bool(await _stepping(server)).is_true()


# FT: FT-MIS-040, FT-NET-034
# A host pause during a coverage pause leaves it in place when the host resumes, and
# a joining client is told of the host pause.
func test_host_pause_keeps_a_coverage_pause() -> void:
	var server: NetServer = h.server(false, 0.4, SECRET)
	var crew: Array[NetClient] = await _running(server)
	var gone: NetSession = h.session_of(server, crew[2])
	await h.drop(server, crew[2])
	await h.lapsed(gone)
	(
		assert_bool(await h.until(func() -> bool: return not server.session.paused.is_empty()))
		. is_true()
	)
	crew[0].host_pause(true)
	assert_bool(await h.until(func() -> bool: return server.session.host_paused)).is_true()
	assert_bool(crew[0].is_welcomed()).is_true()
	var from: int = h.mark(crew[1])
	crew[0].host_pause(false)
	assert_bool(await h.until(func() -> bool: return not server.session.host_paused)).is_true()
	# No resume while the coverage pause still holds the universe.
	assert_dict(await h.next_event(crew[1], NetProtocol.EVENT_RESUME, from)).is_empty()
	assert_bool(server.session.paused.is_empty()).is_false()
	assert_bool(server.session.sim_running()).is_false()
	assert_bool(await _frozen(server, 300)).is_true()
