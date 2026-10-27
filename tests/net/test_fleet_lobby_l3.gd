extends GdUnitTestSuite
## L3 tests of the multi-ship lobby and the PvP session rules over loopback (#11, E11, E12;
## owner M4-Q3, M4-Q4, M4-Q6, M4-Q10): any player adds ships up to 6, each with its own picks
## and coverage check; the universe starts all together; a ship nobody crewed vanishes at
## Start; the host picks the mode and its options; `session_over` relays the session's
## outcome.

const SECRET: String = "c0ffee"

var h: NetHarness


func before_test() -> void:
	h = NetHarness.new(self)


func after_test() -> void:
	await h.free_all()


## The latest `fleet` event a client got at or after `from` matching pred, waiting for it.
func _fleet(c: NetClient, from: int, pred: Callable = Callable()) -> Dictionary:
	var e: Dictionary = await h.next_event(c, NetProtocol.EVENT_FLEET, from, pred)
	return {} if e.is_empty() else e["payload"]


func _rejected(c: NetClient, type: int, from: int) -> String:
	var e: Dictionary = await h.next_event(
		c,
		NetProtocol.EVENT_REQUEST_REJECTED,
		from,
		func(ev: Dictionary) -> bool: return ev["payload"]["request"] == type
	)
	return "" if e.is_empty() else str(e["payload"]["reason"])


## One "all" player per ship (dev_all: one crew player covers a ship).
func _crews(server: NetServer, ships: Array[int]) -> Array[NetClient]:
	var out: Array[NetClient] = []
	for ship: int in ships:
		out.append(await h.joined(server, "crew-%d" % ship, StationViews.ALL, ship))
	return out


func _running(server: NetServer) -> bool:
	return await h.until(
		func() -> bool: return server.session.sim_running() and server.world.tick > 2
	)


# FT: FT-GEN-001
# Any player adds ships up to 6 (ShipAdd, M4-Q3); every session hears `fleet`, the
# Catalogue lists the new ships, and a seventh is refused `fleet_full`.
func test_ships_added_up_to_six() -> void:
	var server: NetServer = h.fleet_server(SessionRules.Mode.COOP, 1)
	var ana: NetClient = await h.welcomed(server, "ana")
	var bo: NetClient = await h.welcomed(server, "bo")
	var from: int = h.mark(bo)
	for i: int in 5:
		ana.add_ship("Wren %d" % i)
	var six: Callable = func(ev: Dictionary) -> bool: return ev["payload"]["ships"].size() == 6
	var fleet: Dictionary = await _fleet(bo, from, six)
	assert_str(FleetMessages.check(NetProtocol.EVENT_FLEET, fleet)).is_empty()
	assert_int(fleet["max_ships"]).is_equal(SessionRules.MAX_SHIPS)
	assert_str(fleet["ships"][5]["name"]).is_equal("Wren 4")
	assert_bool(fleet["started"]).is_false()
	assert_bool(await h.until(func() -> bool: return bo.catalogue["ships"].size() == 6)).is_true()
	assert_int(server.session.crew_ships().size()).is_equal(6)
	from = h.mark(ana)
	ana.add_ship("One too many")
	assert_str(await _rejected(ana, NetProtocol.Type.SHIP_ADD, from)).is_equal("fleet_full")


# FT: FT-GEN-001
# Each ship has its own picks and coverage check in `fleet`: a crewed ship is ready, the
# other shows its own uncovered stations.
func test_each_ship_has_its_own_coverage() -> void:
	var server: NetServer = h.fleet_server(SessionRules.Mode.COOP, 2)
	await h.crew_of(server, 0)
	var lone: NetClient = await h.joined(server, "lone", "ops", 1)
	var from: int = 0
	var both: Callable = func(ev: Dictionary) -> bool:
		var ships: Array = ev["payload"]["ships"]
		return ships[0]["crew"] == 3 and ships[1]["crew"] == 1
	var fleet: Dictionary = await _fleet(lone, from, both)
	assert_bool(fleet["ships"][0]["ready"]).is_true()
	assert_array(fleet["ships"][0]["uncovered"]).is_empty()
	assert_bool(fleet["ships"][1]["ready"]).is_false()
	assert_array(fleet["ships"][1]["uncovered"]).contains(["helm", "weapons"])
	assert_array(fleet["ships"][1]["uncovered"]).not_contains(["relay", "comms"])
	assert_array(fleet["waiting"]).is_equal([0, 1])


# FT: FT-GEN-001
# The universe starts all together (M4-Q4): the first ship's Start waits for the other,
# listed in `waiting`; the second's starts both.
func test_ships_start_all_together() -> void:
	var server: NetServer = h.fleet_server(SessionRules.Mode.COOP, 2, [], true)
	var crews: Array[NetClient] = await _crews(server, [0, 1])
	var from: int = h.mark(crews[1])
	crews[0].set_ready(true)
	var one: Callable = func(ev: Dictionary) -> bool: return ev["payload"]["waiting"] == [1]
	var fleet: Dictionary = await _fleet(crews[1], from, one)
	assert_bool(fleet["ships"][0]["started"]).is_true()
	await h.wait(200)
	assert_bool(server.session.launched.is_empty()).is_true()
	assert_int(server.world.tick).is_equal(0)
	crews[1].set_ready(true)
	assert_bool(await _running(server)).is_true()
	assert_int(server.session.launched.size()).is_equal(2)
	var started: Callable = func(ev: Dictionary) -> bool: return ev["payload"]["started"]
	fleet = await _fleet(crews[1], from, started)
	assert_array(fleet["waiting"]).is_empty()


# FT: FT-GEN-001
# A ship nobody crewed vanishes at Start (M4-Q3): the world is built from the crewed ships in
# lobby order, so ship 2's crew is moved to ship id 1 and told so.
func test_unpicked_ship_vanishes_at_start() -> void:
	var server: NetServer = h.fleet_server(SessionRules.Mode.COOP, 1, [], true)
	var crews: Array[NetClient] = await _crews(server, [0])
	crews[0].add_ship("Empty")
	crews[0].add_ship("Far")
	var three: Callable = func() -> bool: return server.session.crew_ships().size() == 3
	assert_bool(await h.until(three)).is_true()
	crews.append(await h.joined(server, "far", StationViews.ALL, 2))
	var from: int = h.mark(crews[1])
	crews[0].set_ready(true)
	crews[1].set_ready(true)
	assert_bool(await _running(server)).is_true()
	assert_int(server.session.crew_ships().size()).is_equal(2)
	assert_str(server.session.crew_ships()[1]["name"]).is_equal("Far")
	var moved: Dictionary = await h.next_event(crews[1], NetProtocol.EVENT_PICKED, from)
	assert_int(moved["payload"]["ship"]).is_equal(1)
	assert_int(h.session_of(server, crews[1]).ship).is_equal(1)
	assert_int(h.session_of(server, crews[0]).ship).is_equal(0)
	var started: Callable = func(ev: Dictionary) -> bool: return ev["payload"]["started"]
	var fleet: Dictionary = await _fleet(crews[1], from, started)
	assert_int(fleet["ships"].size()).is_equal(2)
	assert_str(fleet["ships"][1]["name"]).is_equal("Far")


# FT: FT-MIS-031, FT-GEN-002
# The host picks the mode and its options (M4-Q6): teams split the ships 0 and 1 and a crew
# moves its ship; others are refused `not_host`, unknown modes `bad_mode`, a team outside a
# teams mode `bad_team`; after Start the lobby is closed.
func test_host_sets_mode_and_teams() -> void:
	var server: NetServer = h.fleet_server(SessionRules.Mode.COOP, 3, [], true, 10.0, SECRET)
	var host: NetClient = await h.welcomed(server, "host", "", SECRET)
	await h.pick(host, StationViews.ALL, 0)
	var crews: Array[NetClient] = await _crews(server, [1, 2])
	var from: int = h.mark(crews[0])
	crews[0].set_mode("teams", "first_to_finish")
	assert_str(await _rejected(crews[0], NetProtocol.Type.SESSION_MODE, from)).is_equal("not_host")
	var from_host: int = h.mark(host)
	host.set_mode("duel", "first_to_finish")
	var why: String = await _rejected(host, NetProtocol.Type.SESSION_MODE, from_host)
	assert_str(why).is_equal("bad_mode")
	crews[0].set_team(1, 0)
	assert_str(await _rejected(crews[0], NetProtocol.Type.SHIP_TEAM, from)).is_equal("bad_team")
	host.set_mode("teams", "first_to_finish")
	var teams: Callable = func(ev: Dictionary) -> bool: return ev["payload"]["mode"] == "teams"
	var fleet: Dictionary = await _fleet(crews[0], from, teams)
	assert_str(fleet["team_win"]).is_equal("first_to_finish")
	var split: Array = fleet["ships"].map(func(s: Dictionary) -> int: return s["team"])
	assert_array(split).is_equal([0, 1, 0])
	crews[1].set_team(2, 1)
	var moved: Callable = func(ev: Dictionary) -> bool:
		return ev["payload"]["ships"][2]["team"] == 1
	assert_dict(await _fleet(crews[0], from, moved)).is_not_empty()
	var from_b: int = h.mark(crews[1])
	crews[1].set_team(1, 0)
	assert_str(await _rejected(crews[1], NetProtocol.Type.SHIP_TEAM, from_b)).is_equal("not_crew")
	for c: NetClient in [host, crews[0], crews[1]]:
		c.set_ready(true)
	assert_bool(await _running(server)).is_true()
	assert_int(server.world.team_of(2)).is_equal(1)
	assert_int(server.world.faction_of(1)).is_equal(server.world.faction_of(2))
	assert_int(server.world.faction_of(0)).is_not_equal(server.world.faction_of(1))
	from = h.mark(host)
	host.set_mode("coop", "last_team_standing")
	assert_str(await _rejected(host, NetProtocol.Type.SESSION_MODE, from)).is_equal("lobby_closed")
	host.add_ship("Late")
	assert_str(await _rejected(host, NetProtocol.Type.SHIP_ADD, from)).is_equal("lobby_closed")


# FT: FT-MIS-031
# The lobby offers the three PvP types plus co-op and holdout; a mode whose ships can't play
# it is refused at Start (`bad_mode` with the reasons): a race of one ship.
func test_modes_offered_and_checked_at_start() -> void:
	var server: NetServer = h.fleet_server(SessionRules.Mode.COOP, 1, [], true, 10.0, SECRET)
	var host: NetClient = await h.welcomed(server, "host", "", SECRET)
	await h.pick(host, StationViews.ALL, 0)
	var from: int = h.mark(host)
	for mode: String in SessionRules.MODE_NAMES:
		host.set_mode(mode, "last_team_standing", 5)
		var named: Callable = func(ev: Dictionary) -> bool: return ev["payload"]["mode"] == mode
		assert_dict(await _fleet(host, 0, named)).override_failure_message(mode).is_not_empty()
	var finite: RelaunchPolicy = server.session.fleet.rules.relaunch_for(
		SessionRules.HOLDOUT_FINITE_TEAM
	)
	assert_int(finite.lives).is_equal(5)
	host.set_mode("race", "last_team_standing")
	from = h.mark(host)
	host.set_ready(true)
	var e: Dictionary = await h.next_event(host, NetProtocol.EVENT_REQUEST_REJECTED, from)
	assert_str(e["payload"]["reason"]).is_equal("bad_mode")
	assert_array(e["payload"]["errors"]).is_not_empty()
	assert_bool(server.session.launched.is_empty()).is_true()


# FT: FT-MIS-014
# The session ends by its mode's condition: `session_over` carries the outcome
# OutcomeSystem.session_outcome gives (here every ship of a last-ship-standing session lost).
func test_session_over_relays_the_outcome() -> void:
	var server: NetServer = h.fleet_server(SessionRules.Mode.LAST_STANDING, 2, [], true)
	var crews: Array[NetClient] = await _crews(server, [0, 1])
	for c: NetClient in crews:
		c.set_ready(true)
	assert_bool(await _running(server)).is_true()
	var from: int = h.mark(crews[0])
	server.world.kin.alive[0] = 0
	server.world.kin.alive[1] = 0
	var e: Dictionary = await h.next_event(crews[0], NetProtocol.EVENT_SESSION_OVER, from)
	assert_dict(e).is_not_empty()
	var payload: Dictionary = e["payload"]
	assert_str(FleetMessages.check(NetProtocol.EVENT_SESSION_OVER, payload)).is_empty()
	var want: SessionOutcome = OutcomeSystem.session_outcome(server.world)
	assert_str(payload["reason"]).is_equal(SessionOutcome.REASON_NAMES[want.reason])
	assert_array(payload["winners"]).is_equal(Array(want.winners))
	assert_int(h.events_of(crews[0], NetProtocol.EVENT_SESSION_OVER).size()).is_equal(1)
