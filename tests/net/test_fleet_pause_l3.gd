extends GdUnitTestSuite
## L3 tests of multi-ship play over loopback (#11, E11; owner M4-Q2, M4-Q8, M4-Q10): a ship
## out of play never holds a pause; abandoning a paused ship eliminates it and the rest
## resumes; allies take over a paused ship's uncovered station, enemies never; eliminated
## crews view a friendly ship or go to the scoreboard; an eliminated side relaunches by vote.

const GRACE_S: float = 0.3

var h: NetHarness


func before_test() -> void:
	h = NetHarness.new(self)


func after_test() -> void:
	await h.free_all()


func _rejected(c: NetClient, type: int, from: int) -> String:
	var e: Dictionary = await h.next_event(
		c,
		NetProtocol.EVENT_REQUEST_REJECTED,
		from,
		func(ev: Dictionary) -> bool: return ev["payload"]["request"] == type
	)
	return "" if e.is_empty() else str(e["payload"]["reason"])


## A fleet server with --dev-all-stations (one crew player covers a ship) and a short grace.
func _server(mode: SessionRules.Mode, n: int, teams: Array[int] = []) -> NetServer:
	return h.fleet_server(mode, n, teams, true, GRACE_S)


## One "all" player per ship.
func _alls(server: NetServer, ships: Array) -> Array[NetClient]:
	var out: Array[NetClient] = []
	for ship: int in ships:
		out.append(await h.joined(server, "all-%d" % ship, StationViews.ALL, ship))
	return out


## Presses Start on every client given and waits until the sim steps.
func _start(server: NetServer, clients: Array[NetClient]) -> bool:
	for c: NetClient in clients:
		c.set_ready(true)
	return await h.until(
		func() -> bool: return server.session.sim_running() and server.world.tick > 2
	)


func _stepping(server: NetServer) -> bool:
	var tick: int = server.world.tick
	return await h.until(func() -> bool: return server.world.tick > tick + 3)


## Drops a client and waits until its grace ran out and a pause holds on `ship`.
func _lapse(server: NetServer, c: NetClient, ship: int) -> bool:
	var gone: NetSession = h.session_of(server, c)
	await h.drop(server, c)
	await h.lapsed(gone)
	return await h.until(func() -> bool: return server.session.paused.has(ship))


func _event(c: NetClient, type: String, from: int, ship: int) -> Dictionary:
	var e: Dictionary = await h.next_event(
		c, type, from, func(ev: Dictionary) -> bool: return ev["payload"]["ship"] == ship
	)
	return {} if e.is_empty() else e["payload"]


# FT: FT-NET-034, FT-NET-035
# A destroyed ship leaves play (CLASH-1 b): a later pause on another ship holds only that
# ship, and resumes once it passes coverage though the destroyed ship never will.
func test_out_of_play_ship_never_holds_a_pause() -> void:
	var server: NetServer = _server(SessionRules.Mode.COOP, 2)
	var alls: Array[NetClient] = await _alls(server, [0, 1])
	assert_bool(await _start(server, alls)).is_true()
	var from: int = h.mark(alls[0])
	server.world.kin.alive[0] = 0
	var gone: Dictionary = await _event(alls[0], NetProtocol.EVENT_ELIMINATED, from, 0)
	assert_str(gone.get("reason", "")).is_equal("destroyed")
	assert_dict(await _event(alls[0], NetProtocol.EVENT_HANDOVER, from, 0)).is_not_empty()
	assert_bool(await _lapse(server, alls[1], 1)).is_true()
	assert_array(server.session.paused.keys()).is_equal([1])
	# The former crew of ship 0, now a viewer of ship 1, takes the uncovered stations over.
	alls[0].takeover(1, StationViews.ALL)
	assert_bool(await h.until(func() -> bool: return server.session.paused.is_empty())).is_true()
	assert_bool(await _stepping(server)).is_true()
	assert_bool(server.session.in_play(0)).is_false()


# FT: FT-NET-041
# During a pause the paused ship's remaining crew abandon it by majority: it is eliminated
# (`eliminated` abandoned), its crew view the surviving friendly ship, and the rest resumes.
func test_abandon_in_a_pause_eliminates_and_the_rest_resumes() -> void:
	var server: NetServer = _server(SessionRules.Mode.COOP, 2)
	var crew: Array[NetClient] = await h.crew_of(server, 0)
	var other: Array[NetClient] = await _alls(server, [1])
	assert_bool(await _start(server, [crew[0], other[0]])).is_true()
	assert_bool(await _lapse(server, crew[2], 0)).is_true()
	var from: int = h.mark(crew[0])
	crew[0].vote_abandon(0, true)
	crew[1].vote_abandon(0, true)
	var gone: Dictionary = await _event(crew[0], NetProtocol.EVENT_ELIMINATED, from, 0)
	assert_str(gone.get("reason", "")).is_equal("abandoned")
	assert_bool(server.session.paused.is_empty()).is_true()
	assert_bool(await _stepping(server)).is_true()
	assert_bool(server.session.in_play(1)).is_true()
	var to: Dictionary = await _event(crew[0], NetProtocol.EVENT_HANDOVER, from, 0)
	assert_int(to.get("to_ship", -2)).is_equal(1)


# FT: FT-NET-042
# A player of an allied ship takes over a paused ship's uncovered station (M4-Q8): the side
# hears `takeover`; a station already covered is refused `taken`, and a crew player whose own
# ship would fail coverage is refused `breaks_coverage`.
func test_ally_takes_over_an_uncovered_station() -> void:
	var server: NetServer = _server(SessionRules.Mode.COOP, 2)
	var crew: Array[NetClient] = await h.crew_of(server, 0)
	var ally: NetClient = (await _alls(server, [1]))[0]
	var spare: NetClient = await h.joined(server, "spare", "helm", 1)
	assert_bool(await _start(server, [crew[0], ally])).is_true()
	assert_bool(await _lapse(server, crew[2], 0)).is_true()
	var from: int = h.mark(crew[0])
	var from_ally: int = h.mark(ally)
	var from_spare: int = h.mark(spare)
	ally.takeover(0, "ops")
	var why: String = await _rejected(ally, NetProtocol.Type.TAKEOVER, from_ally)
	assert_str(why).is_equal("breaks_coverage")
	spare.takeover(0, "tactical")
	assert_str(await _rejected(spare, NetProtocol.Type.TAKEOVER, from_spare)).is_equal("taken")
	spare.takeover(0, "ops")
	var took: Dictionary = await _event(crew[0], NetProtocol.EVENT_TAKEOVER, from, 0)
	assert_str(FleetMessages.check(NetProtocol.EVENT_TAKEOVER, took)).is_empty()
	assert_dict(took).contains_key_value("by", "spare").contains_key_value("from_ship", 1)
	assert_dict(await _event(ally, NetProtocol.EVENT_TAKEOVER, from_ally, 0)).is_not_empty()
	assert_bool(await h.until(func() -> bool: return server.session.paused.is_empty())).is_true()
	assert_int(h.session_of(server, spare).ship).is_equal(0)
	assert_bool(await _stepping(server)).is_true()


# FT: FT-NET-042
# Enemies never take over (M4-Q8): a race rival's spare player is refused `enemy_ship`.
func test_enemy_never_takes_over() -> void:
	var server: NetServer = _server(SessionRules.Mode.RACE, 2)
	var alls: Array[NetClient] = await _alls(server, [0, 1])
	var spare: NetClient = await h.joined(server, "spare", "helm", 1)
	assert_bool(await _start(server, alls)).is_true()
	assert_bool(await _lapse(server, alls[0], 0)).is_true()
	var from: int = h.mark(spare)
	spare.takeover(0, StationViews.ALL)
	assert_str(await _rejected(spare, NetProtocol.Type.TAKEOVER, from)).is_equal("enemy_ship")
	assert_bool(server.session.paused.has(0)).is_true()


# FT: FT-MIS-030
# By default an eliminated crew views a surviving friendly ship's main screen (D91).
func test_eliminated_crew_view_a_friendly_ship() -> void:
	var server: NetServer = _server(SessionRules.Mode.COOP, 2)
	var alls: Array[NetClient] = await _alls(server, [0, 1])
	assert_bool(await _start(server, alls)).is_true()
	var from: int = h.mark(alls[0])
	server.world.kin.alive[0] = 0
	var to: Dictionary = await _event(alls[0], NetProtocol.EVENT_HANDOVER, from, 0)
	assert_str(FleetMessages.check(NetProtocol.EVENT_HANDOVER, to)).is_empty()
	assert_int(to["to_ship"]).is_equal(1)
	var s: NetSession = h.session_of(server, alls[0])
	assert_int(s.ship).is_equal(1)
	assert_str(s.entry).is_equal(StationViews.VIEWER)
	assert_bool(server.session.sim_running()).is_true()


# FT: FT-MIS-030, FT-NET-010
# A mode that sends eliminated crews to the lobby (last ship standing, D91): the crew gets
# `handover` to -1 and the live scoreboard, status and progress only (M4-Q9).
func test_eliminated_crew_go_to_the_scoreboard() -> void:
	var server: NetServer = _server(SessionRules.Mode.LAST_STANDING, 3)
	var alls: Array[NetClient] = await _alls(server, [0, 1, 2])
	assert_bool(await _start(server, alls)).is_true()
	var from: int = h.mark(alls[2])
	server.world.kin.alive[2] = 0
	var to: Dictionary = await _event(alls[2], NetProtocol.EVENT_HANDOVER, from, 2)
	assert_int(to.get("to_ship", -2)).is_equal(FleetMessages.TO_SCOREBOARD)
	assert_bool(h.session_of(server, alls[2]).has_pick()).is_false()
	var board: Dictionary = await h.next_event(alls[2], NetProtocol.EVENT_SCOREBOARD, from)
	assert_dict(board).is_not_empty()
	var payload: Dictionary = board["payload"]
	assert_str(FleetMessages.check(NetProtocol.EVENT_SCOREBOARD, payload)).is_empty()
	var rows: Array = payload["rows"]
	assert_int(rows.size()).is_equal(3)
	assert_str(rows[2]["state"]).is_equal(FleetMessages.DESTROYED)
	assert_str(rows[0]["state"]).is_equal(FleetMessages.IN_PLAY)
	assert_str(rows[1]["name"]).is_equal("Ship 2")
	assert_bool(server.session.fleet.is_over()).is_false()
	assert_bool(await _stepping(server)).is_true()


# FT: FT-MIS-030
# A side whose policy allows it relaunches by its crew's vote (M4-Q2): the holdout's finite
# side is eliminated with its lives left, votes, and the server sends RelaunchShipCommand;
# the sim accepts it and the crew is back on its stations (`relaunched`).
func test_relaunch_by_vote() -> void:
	var server: NetServer = _server(SessionRules.Mode.HOLDOUT, 2, [0, 1])
	var alls: Array[NetClient] = await _alls(server, [0, 1])
	assert_bool(await _start(server, alls)).is_true()
	var from: int = h.mark(alls[1])
	server.world.kin.alive[1] = 0
	var gone: Dictionary = await _event(alls[1], NetProtocol.EVENT_ELIMINATED, from, 1)
	assert_int(gone.get("lives", -2)).is_equal(SessionRules.HOLDOUT_LIVES)
	assert_dict(await _event(alls[1], NetProtocol.EVENT_HANDOVER, from, 1)).is_not_empty()
	var from_rival: int = h.mark(alls[0])
	alls[0].vote_relaunch(1, true)
	var why: String = await _rejected(alls[0], NetProtocol.Type.RELAUNCH, from_rival)
	assert_str(why).is_equal("not_crew")
	alls[1].vote_relaunch(1, true)
	var votes: Dictionary = await _event(alls[1], NetProtocol.EVENT_RELAUNCH_VOTES, from, 1)
	assert_str(FleetMessages.check(NetProtocol.EVENT_RELAUNCH_VOTES, votes)).is_empty()
	assert_int(votes["needed"]).is_equal(1)
	var sent: Callable = func() -> bool:
		for c: SimCommand in server.world.command_log:
			if c is RelaunchShipCommand and (c as RelaunchShipCommand).ship == 1:
				return true
		return false
	assert_bool(await h.until(sent)).is_true()
	var back: Dictionary = await _event(alls[1], NetProtocol.EVENT_RELAUNCHED, from, 1)
	assert_str(FleetMessages.check(NetProtocol.EVENT_RELAUNCHED, back)).is_empty()
	assert_int(back.get("lives", -2)).is_equal(SessionRules.HOLDOUT_LIVES - 1)
	var s: NetSession = h.session_of(server, alls[1])
	assert_int(s.ship).is_equal(1)
	assert_str(s.entry).is_equal(StationViews.ALL)
	assert_bool(server.session.in_play(1)).is_true()


# FT: FT-MIS-030
# Co-op has no relaunch: the vote is refused `no_relaunch`.
func test_coop_has_no_relaunch() -> void:
	var server: NetServer = _server(SessionRules.Mode.COOP, 2)
	var alls: Array[NetClient] = await _alls(server, [0, 1])
	assert_bool(await _start(server, alls)).is_true()
	var from: int = h.mark(alls[0])
	server.world.kin.alive[0] = 0
	assert_dict(await _event(alls[0], NetProtocol.EVENT_ELIMINATED, from, 0)).is_not_empty()
	alls[0].vote_relaunch(0, true)
	assert_str(await _rejected(alls[0], NetProtocol.Type.RELAUNCH, from)).is_equal("no_relaunch")
