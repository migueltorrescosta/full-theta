extends GdUnitTestSuite
## L3 tests of the grace period, the universe pause and its exits (T045): rejoin,
## abandon by vote or by the host, and takeover by the Captain or a Viewer.

const PLAYER: int = NetHarness.PLAYER
const GRACE_S: float = 0.6

var h: NetHarness


func before_test() -> void:
	h = NetHarness.new(self)


func after_test() -> void:
	await h.free_all()


## A started ship with Tactical, Systems and Ops, plus any extra entries.
func _running(server: NetServer, extra: Array[String] = []) -> Array[NetClient]:
	var crew: Array[NetClient] = await h.crew3(server)
	for entry: String in extra:
		crew.append(await h.joined(server, entry, entry))
	assert_bool(await h.start(server, crew[0])).is_true()
	return crew


## Drops a crew client for good and waits for the pause it causes; returns the pause
## event another client got.
func _lose(server: NetServer, gone: NetClient, watcher: NetClient) -> Dictionary:
	var session: NetSession = h.session_of(server, gone)
	var from: int = h.mark(watcher)
	await h.drop(server, gone)
	await h.lapsed(session)
	return await h.next_event(watcher, NetProtocol.EVENT_PAUSE, from)


## Whether the sim stays at one tick for ms while snapshots keep arriving at c.
func _frozen(server: NetServer, c: NetClient, ms: int) -> bool:
	var tick: int = server.world.tick
	var snaps: int = c.stats["snapshots"]
	await h.wait(ms)
	return server.world.tick == tick and c.stats["snapshots"] > snaps + 3


## Whether the sim steps again.
func _running_again(server: NetServer) -> bool:
	var tick: int = server.world.tick
	return await h.until(func() -> bool: return server.world.tick > tick + 3)


# FT: FT-NET-033, FT-NET-034
# A dropped crew player's pick and claims stay for the grace period (wall clock) and
# the run goes on; when it ends and coverage fails, the whole universe pauses (no sim
# step, snapshots keep flowing) and every client is told the ship and the uncovered
# stations. The grace timer of a second drop runs while paused.
func test_grace_then_universe_pause() -> void:
	var server: NetServer = h.server(false, GRACE_S)
	var crew: Array[NetClient] = await _running(server, ["viewer"])
	var tac: NetSession = h.session_of(server, crew[0])
	assert_int(server.session.claims.holder(PLAYER, "flight")).is_equal(tac.id)
	var from: int = h.mark(crew[3])
	var t0: int = Time.get_ticks_msec()
	await h.drop(server, crew[0])
	# Within the grace: pick and claims kept, no pause.
	assert_str(tac.entry).is_equal("tactical")
	assert_int(server.session.claims.holder(PLAYER, "flight")).is_equal(tac.id)
	assert_bool(server.session.sim_running()).is_true()
	assert_bool(await h.lapsed(tac)).is_true()
	assert_int(Time.get_ticks_msec() - t0).is_greater_equal(int(GRACE_S * 1000))
	var pause: Dictionary = await h.next_event(crew[3], NetProtocol.EVENT_PAUSE, from)
	assert_int(pause["payload"]["ship"]).is_equal(PLAYER)
	assert_array(pause["payload"]["uncovered"]).is_equal(["helm", "weapons"])
	assert_int(pause["payload"]["crew"]).is_equal(2)
	assert_dict(await h.next_event(crew[1], NetProtocol.EVENT_PAUSE, from)).is_not_empty()
	assert_int(server.session.claims.holder(PLAYER, "flight")).is_equal(-1)
	assert_bool(await _frozen(server, crew[3], 400)).is_true()
	# A second drop during the pause: its grace runs on the wall clock all the same.
	var sys: NetSession = h.session_of(server, crew[1])
	var tick: int = server.world.tick
	from = h.mark(crew[3])
	t0 = Time.get_ticks_msec()
	await h.drop(server, crew[1])
	assert_bool(await h.lapsed(sys)).is_true()
	assert_int(Time.get_ticks_msec() - t0).is_greater_equal(int(GRACE_S * 1000))
	assert_int(server.world.tick).is_equal(tick)
	var more: Dictionary = await h.next_event(crew[3], NetProtocol.EVENT_PAUSE, from)
	assert_array(more["payload"]["uncovered"]).is_equal(
		["helm", "weapons", "engineering", "science"]
	)


# FT: FT-NET-035, FT-NET-026
# The dropped player relaunches after its grace: its pick comes back, coverage passes
# and the universe resumes.
func test_rejoin_ends_the_pause() -> void:
	var server: NetServer = h.server(false, GRACE_S)
	var crew: Array[NetClient] = await _running(server)
	var token: String = crew[2].token
	var pause: Dictionary = await _lose(server, crew[2], crew[0])
	assert_array(pause["payload"]["uncovered"]).is_equal(["relay", "comms"])
	assert_bool(await _frozen(server, crew[0], 300)).is_true()
	var from: int = h.mark(crew[0])
	var again: NetClient = await h.welcomed(server, "ops'", token)
	assert_str(again.welcome["entry"]).is_equal("ops")
	assert_dict(await h.next_event(crew[0], NetProtocol.EVENT_RESUME, from)).is_not_empty()
	assert_bool(await _running_again(server)).is_true()


# FT: FT-NET-036
# Captain and Viewer drops never pause, even after their grace ends.
func test_captain_and_viewer_drops_never_pause() -> void:
	var server: NetServer = h.server(false, GRACE_S)
	var crew: Array[NetClient] = await _running(server, ["captain", "viewer"])
	var cap: NetSession = h.session_of(server, crew[3])
	var view: NetSession = h.session_of(server, crew[4])
	await h.drop(server, crew[3])
	await h.drop(server, crew[4])
	assert_bool(await h.lapsed(cap)).is_true()
	assert_bool(await h.lapsed(view)).is_true()
	await h.wait(200)
	assert_bool(server.session.sim_running()).is_true()
	assert_array(h.events_of(crew[0], NetProtocol.EVENT_PAUSE)).is_empty()
	assert_bool(await _running_again(server)).is_true()


# FT: FT-NET-041, FT-M1-012
# CLASH-1 a: a 3-player crew loses one player for good. During the pause each remaining
# crew player may cast or withdraw an abandon vote (every client sees the voters); a
# Viewer may not vote; 2 of 2 abandon the ship, which leaves play, ends the pause and
# ends the encounter as a loss through the sim's outcome path.
func test_remaining_crew_abandon_by_vote() -> void:
	var server: NetServer = h.server(false, GRACE_S)
	var crew: Array[NetClient] = await _running(server, ["viewer"])
	var tac: NetClient = crew[0]
	var sys: NetClient = crew[1]
	var viewer: NetClient = crew[3]
	var from: int = h.mark(tac)
	tac.vote_abandon(PLAYER, true)
	var early: Dictionary = await h.next_event(tac, ServerSession.EVENT_REQUEST_REJECTED, from)
	assert_str(early["payload"]["reason"]).is_equal(ServerSession.NOT_PAUSED)
	await _lose(server, crew[2], viewer)
	from = h.mark(viewer)
	tac.vote_abandon(PLAYER, true)
	var one: Callable = func(e: Dictionary) -> bool: return e["payload"]["voters"] == ["tactical"]
	var votes: Dictionary = await h.next_event(viewer, NetProtocol.EVENT_ABANDON_VOTES, from, one)
	assert_int(votes["payload"]["needed"]).is_equal(2)
	var none: Callable = func(e: Dictionary) -> bool: return e["payload"]["voters"] == []
	from = h.mark(viewer)
	tac.vote_abandon(PLAYER, false)
	(
		assert_dict(await h.next_event(viewer, NetProtocol.EVENT_ABANDON_VOTES, from, none))
		. is_not_empty()
	)
	from = h.mark(viewer)
	viewer.vote_abandon(PLAYER, true)
	var refused: Dictionary = await h.next_event(viewer, ServerSession.EVENT_REQUEST_REJECTED, from)
	assert_str(refused["payload"]["reason"]).is_equal(ServerSession.NOT_CREW)
	assert_bool(server.session.paused.has(PLAYER)).is_true()
	from = h.mark(viewer)
	tac.vote_abandon(PLAYER, true)
	sys.vote_abandon(PLAYER, true)
	var gone: Dictionary = await h.next_event(viewer, NetProtocol.EVENT_ABANDONED, from)
	assert_int(gone["payload"]["ship"]).is_equal(PLAYER)
	assert_str(gone["payload"]["by"]).is_equal("vote")
	assert_dict(await h.next_event(viewer, NetProtocol.EVENT_RESUME, from)).is_not_empty()
	var loss: Callable = func(e: Dictionary) -> bool: return e["payload"]["tag"] == "loss"
	assert_dict(await h.next_event(sys, &"outcome", from, loss)).is_not_empty()
	assert_int(server.world.run.status[PLAYER]).is_equal(RunTable.Status.ABANDONED)
	assert_int(server.world.run.outcome[PLAYER]).is_equal(RunTable.Outcome.LOSS)
	assert_int(OutcomeSystem.encounter_outcome(server.world)).is_equal(RunTable.Outcome.LOSS)
	assert_bool(server.session.in_play(PLAYER)).is_false()
	(
		assert_bool(
			server.world.accepted_commands().any(
				func(c: SimCommand) -> bool: return c.kind() == &"abandon_ship"
			)
		)
		. is_true()
	)
	# The abandoned ship takes no more crew commands.
	from = h.mark(tac)
	tac.helm(1.0)
	var rejected: Dictionary = await h.next_event(tac, NetProtocol.EVENT_COMMAND_REJECTED, from)
	assert_str(rejected["payload"]["reason"]).is_equal(CommandGate.SHIP_ABANDONED)


# FT: FT-NET-041
# The host (the client presenting the host secret, D127) abandons a paused ship alone;
# another crew player can't.
func test_host_abandons_alone() -> void:
	var server: NetServer = h.server(false, GRACE_S, "f00d")
	var host: NetClient = await h.welcomed(server, "host", "", "f00d")
	assert_bool(await h.pick(host, "tactical")).is_true()
	var sys: NetClient = await h.joined(server, "systems", "systems")
	var ops: NetClient = await h.joined(server, "ops", "ops")
	assert_bool(await h.start(server, host)).is_true()
	await _lose(server, ops, sys)
	var from: int = h.mark(sys)
	sys.abandon(PLAYER)
	var refused: Dictionary = await h.next_event(sys, ServerSession.EVENT_REQUEST_REJECTED, from)
	assert_str(refused["payload"]["reason"]).is_equal(ServerSession.NOT_HOST)
	assert_bool(server.session.paused.has(PLAYER)).is_true()
	host.abandon(PLAYER)
	var gone: Dictionary = await h.next_event(sys, NetProtocol.EVENT_ABANDONED, from)
	assert_str(gone["payload"]["by"]).is_equal("host")
	assert_dict(await h.next_event(sys, NetProtocol.EVENT_RESUME, from)).is_not_empty()
	(
		assert_bool(await h.until(func() -> bool: return server.world.run.outcome[PLAYER] != 0))
		. is_true()
	)
	assert_int(server.world.run.outcome[PLAYER]).is_equal(RunTable.Outcome.LOSS)


# FT: FT-NET-042
# During a pause a Viewer of the ship takes over the uncovered station and the pause
# ends; later the Captain does the same. Outside a pause, or from a crew player, a
# takeover is refused.
func test_viewer_or_captain_takes_over() -> void:
	var server: NetServer = h.server(false, GRACE_S)
	var crew: Array[NetClient] = await _running(server, ["viewer", "captain"])
	var viewer: NetClient = crew[3]
	var cap: NetClient = crew[4]
	var from: int = h.mark(viewer)
	viewer.takeover(PLAYER, "ops")
	var early: Dictionary = await h.next_event(viewer, ServerSession.EVENT_REQUEST_REJECTED, from)
	assert_str(early["payload"]["reason"]).is_equal(ServerSession.NOT_PAUSED)
	await _lose(server, crew[2], crew[0])
	from = h.mark(crew[1])
	crew[1].takeover(PLAYER, "ops")
	var crew_refused: Dictionary = await h.next_event(
		crew[1], ServerSession.EVENT_REQUEST_REJECTED, from
	)
	assert_str(crew_refused["payload"]["reason"]).is_equal(CommandGate.NOT_ALLOWED)
	from = h.mark(viewer)
	viewer.takeover(PLAYER, "ops")
	var picked: Dictionary = await h.next_event(viewer, NetProtocol.EVENT_PICKED, from)
	assert_str(picked["payload"]["reason"]).is_equal("")
	assert_dict(await h.next_event(viewer, NetProtocol.EVENT_RESUME, from)).is_not_empty()
	assert_str(h.session_of(server, viewer).entry).is_equal("ops")
	assert_bool(await _running_again(server)).is_true()
	await _lose(server, crew[1], crew[0])
	from = h.mark(cap)
	cap.takeover(PLAYER, "systems")
	assert_dict(await h.next_event(cap, NetProtocol.EVENT_RESUME, from)).is_not_empty()
	assert_str(h.session_of(server, cap).entry).is_equal("systems")
	assert_bool(await _running_again(server)).is_true()


# FT: FT-NET-033, FT-NET-035
# Grace expiry frees the pick: a new player (no token) takes the uncovered entry and
# the universe resumes.
func test_new_player_takes_a_freed_pick() -> void:
	var server: NetServer = h.server(false, GRACE_S)
	var crew: Array[NetClient] = await _running(server)
	await _lose(server, crew[1], crew[0])
	var from: int = h.mark(crew[0])
	var fresh: NetClient = await h.joined(server, "newcomer", "systems")
	assert_str(h.session_of(server, fresh).entry).is_equal("systems")
	assert_dict(await h.next_event(crew[0], NetProtocol.EVENT_RESUME, from)).is_not_empty()
	assert_bool(await _running_again(server)).is_true()
