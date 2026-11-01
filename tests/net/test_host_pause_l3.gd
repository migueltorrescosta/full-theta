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
# A PvP session (a race of two ships) has no host pause, even for the host.
func test_pvp_refuses_the_host() -> void:
	var server: NetServer = h.fleet_server(SessionRules.Mode.RACE, 2, [], true, 10.0, SECRET)
	var host: NetClient = await h.welcomed(server, "host", "", SECRET)
	await h.pick(host, StationViews.ALL, 0)
	var rival: NetClient = await h.joined(server, "rival", StationViews.ALL, 1)
	host.set_ready(true)
	rival.set_ready(true)
	assert_bool(await _stepping(server)).is_true()
	assert_bool(server.session.host_pause.is_pvp()).is_true()
	var from: int = h.mark(host)
	host.host_pause(true)
	assert_str(await _rejected(host, from)).is_equal("pvp_no_pause")
	assert_bool(server.session.host_paused).is_false()
	assert_bool(await _stepping(server)).is_true()


## A started ship whose Ops player has lapsed: a coverage pause holds, crew[2] is gone.
func _coverage_paused(server: NetServer, crew: Array[NetClient]) -> void:
	var gone: NetSession = h.session_of(server, crew[2])
	await h.drop(server, crew[2])
	await h.lapsed(gone)
	(
		assert_bool(await h.until(func() -> bool: return not server.session.paused.is_empty()))
		. is_true()
	)


# FT: FT-MIS-040, FT-NET-034
# H1 scenario A: the host pauses during a coverage pause and resumes first. Each lift
# sends its own `resume` (host true, then host false), the sim runs only after both,
# and the second names the coverage pause so a client keeps no stale flag.
func test_host_resumes_before_the_coverage_pause_lifts() -> void:
	var server: NetServer = h.server(false, 0.4, SECRET)
	var crew: Array[NetClient] = await _running(server)
	await _coverage_paused(server, crew)
	crew[0].host_pause(true)
	assert_bool(await h.until(func() -> bool: return server.session.host_paused)).is_true()
	var from: int = h.mark(crew[1])
	crew[0].host_pause(false)
	var first: Dictionary = await h.next_event(crew[1], NetProtocol.EVENT_RESUME, from)
	assert_bool(first["payload"]["host"]).is_true()
	assert_bool(server.session.sim_running()).is_false()
	assert_bool(await _frozen(server, 300)).is_true()
	from = h.mark(crew[1])
	var back: NetClient = await h.joined(server, "ops2", "ops")
	var second: Dictionary = await h.next_event(crew[1], NetProtocol.EVENT_RESUME, from)
	assert_bool(second["payload"]["host"]).is_false()
	assert_bool(back.is_welcomed()).is_true()
	assert_bool(await _stepping(server)).is_true()


# FT: FT-MIS-040, FT-NET-034
# H1 scenario B: the coverage pause lifts first while the host pause holds: the
# `resume` (host false) goes out, the sim stays frozen until the host's own resume.
func test_coverage_pause_lifts_before_the_host_resumes() -> void:
	var server: NetServer = h.server(false, 0.4, SECRET)
	var crew: Array[NetClient] = await _running(server)
	await _coverage_paused(server, crew)
	crew[0].host_pause(true)
	assert_bool(await h.until(func() -> bool: return server.session.host_paused)).is_true()
	var from: int = h.mark(crew[1])
	await h.joined(server, "ops2", "ops")
	var first: Dictionary = await h.next_event(crew[1], NetProtocol.EVENT_RESUME, from)
	assert_bool(first["payload"]["host"]).is_false()
	assert_bool(server.session.paused.is_empty()).is_true()
	assert_bool(server.session.sim_running()).is_false()
	assert_bool(await _frozen(server, 300)).is_true()
	from = h.mark(crew[1])
	crew[0].host_pause(false)
	var second: Dictionary = await h.next_event(crew[1], NetProtocol.EVENT_RESUME, from)
	assert_bool(second["payload"]["host"]).is_true()
	assert_bool(await _stepping(server)).is_true()


# FT: FT-MIS-040, FT-NET-033
# Q19, owner 2026-10-26: a host who has not returned within the reconnect grace no
# longer holds the universe; a host who returns within it still does.
func test_host_pause_lifts_when_the_host_does_not_return() -> void:
	var server: NetServer = h.server(false, 0.4, SECRET)
	var crew: Array[NetClient] = await _running(server)
	crew[0].host_pause(true)
	assert_bool(await h.until(func() -> bool: return server.session.host_paused)).is_true()
	var host_session: NetSession = h.session_of(server, crew[0])
	var from: int = h.mark(crew[1])
	await h.drop(server, crew[0])
	assert_bool(server.session.host_paused).is_true()
	await h.lapsed(host_session)
	assert_bool(server.session.host_paused).is_false()
	var resume: Dictionary = await h.next_event(crew[1], NetProtocol.EVENT_RESUME, from)
	assert_bool(resume["payload"]["host"]).is_true()
	# The host's pick lapsed too, so a coverage pause now holds the universe (Q19:
	# coverage pause rules still apply).
	assert_bool(server.session.paused.is_empty()).is_false()
	assert_bool(server.session.sim_running()).is_false()
