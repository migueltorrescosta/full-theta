extends GdUnitTestSuite
## L3 tests of guests and the host's lobby options over loopback (#40 D2, D10; gp-03, gp-04,
## gp-11): an eliminated co-op crew takes free light stations of a friendly ship as guests,
## never Helm, Weapons or Captain, without counting for its coverage, and goes home on
## relaunch; GameMode carries the two host options; the host rerolls the run modifier.

const SECRET: String = "c0ffee"
const GRACE: float = 0.6

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


## The `picked` answer to `c` picking (ship, seat): its reason, "" when it was taken.
func _pick_reason(c: NetClient, ship: int, seat: String) -> String:
	var from: int = h.mark(c)
	c.pick(ship, seat)
	var e: Dictionary = await h.next_event(
		c,
		NetProtocol.EVENT_PICKED,
		from,
		func(ev: Dictionary) -> bool: return ev["payload"]["seat"] == seat
	)
	return "missing" if e.is_empty() else str(e["payload"]["reason"])


## Gives each ship the co-op relaunch's price before it is lost, so its side may relaunch it
## (gp-10: the lost ship's purse pays).
static func _fund(server: NetServer, ships: Array) -> void:
	for ship: int in ships:
		Economy.add_credits(server.world, ship, server.world.run_def.relaunch_cost)


func _fleet(c: NetClient, from: int, pred: Callable) -> Dictionary:
	var e: Dictionary = await h.next_event(c, NetProtocol.EVENT_FLEET, from, pred)
	return {} if e.is_empty() else e["payload"]


# FT: FT-NET-050, FT-MIS-030
# Co-op, two ships (dev seats: one crew player covers a ship's coverage), ship 1's player on
# Tactical with fill bots on the light stations. Ship 0 is destroyed: its two players view
# ship 1 as guests; one takes Relay (the fill bot gives way and still counts), the other is
# refused Helm and the Captain seat, and Relay once taken; a guest never counts for coverage.
# The ship relaunches by its crew's vote and the guests go home to their stations.
func test_guests_take_free_light_stations_and_go_home_on_relaunch() -> void:
	var server: NetServer = h.fleet_server(GameRules.Mode.COOP, 2, [], true, GRACE)
	server.game.lobby.fill_bots = true
	var ana: NetClient = await h.joined(server, "ana", StationCatalogue.ALL, 0)
	var bo: NetClient = await h.joined(server, "bo", "viewer", 0)
	var cy: NetClient = await h.joined(server, "cy", "tactical", 1)
	server.game.fleet.rules.relaunch[GameRules.CREW_FACTIONS[0]] = RelaunchPolicy.unlimited()
	h.all_ready(server)
	ana.start()
	assert_bool(await h.until(func() -> bool: return server.game.sim_running())).is_true()
	assert_bool(server.game.lobby.bots[1].has("relay")).is_true()
	_fund(server, [0])
	server.world.kin.alive[0] = 0
	var guest: NetSession = h.session_of(server, ana)
	assert_bool(await h.until(func() -> bool: return guest.ship == 1)).is_true()
	assert_int(guest.guest_from).is_equal(0)
	assert_str(guest.seat).is_equal(StationCatalogue.VIEWER)
	assert_str(await _pick_reason(ana, 1, "helm")).is_equal(CommandGate.NOT_ALLOWED)
	assert_str(await _pick_reason(ana, 1, StationCatalogue.CAPTAIN)).is_equal(
		CommandGate.NOT_ALLOWED
	)
	assert_str(await _pick_reason(ana, 1, "ops")).is_equal(CommandGate.NOT_ALLOWED)
	assert_str(await _pick_reason(ana, 1, "relay")).is_empty()
	# The fill bot gives way but stays: the ship never depends on its guest.
	assert_bool(server.game.lobby.bots[1].has("relay")).is_true()
	assert_bool(server.game.lobby.active_bots(1).has("relay")).is_false()
	assert_bool(server.game.lobby.seats_of(1).count("relay") == 1).is_true()
	var row: Dictionary = {}
	for r: Dictionary in server.game.lobby_state(1)["seats"]:
		if r["name"] == "ana":
			row = r
	assert_bool(row.get("guest", false)).is_true()
	var other: NetSession = h.session_of(server, bo)
	assert_bool(await h.until(func() -> bool: return other.ship == 1)).is_true()
	assert_str(await _pick_reason(bo, 1, "relay")).is_equal(FleetMessages.TAKEN)
	assert_str(await _pick_reason(bo, 1, "comms")).is_empty()
	# The relaunch vote of ship 0's crew: both go home.
	ana.vote_relaunch(0, true)
	assert_bool(await h.until(func() -> bool: return guest.ship == 0)).is_true()
	assert_int(guest.guest_from).is_equal(-1)
	assert_str(guest.seat).is_equal(StationCatalogue.ALL)
	assert_bool(server.game.lobby.active_bots(1).has("relay")).is_true()


# FT: FT-NET-050, FT-MIS-030
# A guest's host ship is eliminated in turn: the guest moves on to a surviving ship, still a
# guest of its own ship, and stays off the host ship's crew list: the host ship's relaunch
# seats only its own crew, the guest's own ship's relaunch takes the guest home.
func test_guests_of_an_eliminated_ship_stay_guests_of_their_own() -> void:
	var server: NetServer = h.fleet_server(GameRules.Mode.COOP, 3, [], true, GRACE)
	server.game.lobby.fill_bots = true
	var ana: NetClient = await h.joined(server, "ana", StationCatalogue.ALL, 0)
	var cy: NetClient = await h.joined(server, "cy", "tactical", 1)
	await h.joined(server, "dee", StationCatalogue.ALL, 2)
	server.game.fleet.rules.relaunch[GameRules.CREW_FACTIONS[0]] = RelaunchPolicy.unlimited()
	h.all_ready(server)
	ana.start()
	assert_bool(await h.until(func() -> bool: return server.game.sim_running())).is_true()
	var guest: NetSession = h.session_of(server, ana)
	_fund(server, [0, 1])
	server.world.kin.alive[0] = 0
	assert_bool(await h.until(func() -> bool: return guest.ship == 1)).is_true()
	assert_str(await _pick_reason(ana, 1, "relay")).is_empty()
	var host: NetSession = h.session_of(server, cy)
	server.world.kin.alive[1] = 0
	assert_bool(await h.until(func() -> bool: return guest.ship == 2 and host.ship == 2)).is_true()
	assert_int(guest.guest_from).is_equal(0)
	assert_str(guest.seat).is_equal(StationCatalogue.VIEWER)
	assert_int(host.guest_from).is_equal(1)
	cy.vote_relaunch(1, true)
	assert_bool(await h.until(func() -> bool: return host.ship == 1)).is_true()
	await h.wait(200)
	assert_int(guest.ship).is_equal(2)
	ana.vote_relaunch(0, true)
	assert_bool(await h.until(func() -> bool: return guest.ship == 0)).is_true()
	assert_str(guest.seat).is_equal(StationCatalogue.ALL)


# FT: FT-NET-050
# Race sends eliminated crews to the scoreboard: nobody is a guest there.
func test_no_guests_in_race() -> void:
	var server: NetServer = h.fleet_server(GameRules.Mode.RACE, 2, [], true, GRACE)
	var ana: NetClient = await h.joined(server, "ana", StationCatalogue.ALL, 0)
	await h.joined(server, "bo", StationCatalogue.ALL, 1)
	h.all_ready(server)
	ana.start()
	assert_bool(await h.until(func() -> bool: return server.game.sim_running())).is_true()
	server.world.kin.alive[0] = 0
	var s: NetSession = h.session_of(server, ana)
	assert_bool(await h.until(func() -> bool: return s.ship == -1 and s.seat == "")).is_true()
	assert_int(s.guest_from).is_equal(-1)


# FT: FT-NET-048, FT-NET-049
# GameMode carries the host's two options (off by default): the `fleet` event says them,
# the lobby follows, and a mode change keeps the run modifier.
func test_host_options_ride_on_game_mode() -> void:
	var server: NetServer = h.fleet_server(GameRules.Mode.COOP, 1, [], false, 10.0, SECRET)
	server.game.fleet.roll_modifiers([&"calm", &"ion_storm"], 3)
	var rolled: StringName = server.game.fleet.rules.modifier_id
	var host: NetClient = await h.welcomed(server, "host", "", SECRET)
	var first: Dictionary = h.last_event(host, NetProtocol.EVENT_FLEET)["payload"]
	assert_bool(first["drop_pause"]).is_true()  # NetHarness keeps the old pause on
	assert_bool(first["fill_bots"]).is_false()
	assert_str(first["modifier"]).is_equal(String(rolled))
	assert_bool(first["rerollable"]).is_true()
	var from: int = h.mark(host)
	host.set_mode("teams", "last_team_standing", -1, false, true)
	var fleet: Dictionary = await _fleet(
		host, from, func(ev: Dictionary) -> bool: return ev["payload"]["mode"] == "teams"
	)
	assert_str(FleetMessages.check(NetProtocol.EVENT_FLEET, fleet)).is_empty()
	assert_bool(fleet["drop_pause"]).is_false()
	assert_bool(fleet["fill_bots"]).is_true()
	assert_str(fleet["modifier"]).is_equal(String(rolled))
	assert_bool(server.game.lobby.fill_bots).is_true()
	assert_int(server.game.lobby.min_crew()).is_equal(2)


# FT: FT-NET-051
# The host rerolls the run modifier before the start: another one each time, never the same;
# anyone else is refused `not_host`, a lone modifier `no_reroll`, and the world built at Start
# carries the last roll.
func test_reroll_is_host_only_and_changes_the_modifier() -> void:
	var server: NetServer = h.fleet_server(GameRules.Mode.COOP, 1, [], true, 10.0, SECRET)
	server.game.fleet.roll_modifiers([&"a", &"b", &"c"], 11)
	var host: NetClient = await h.welcomed(server, "host", "", SECRET)
	var crew: NetClient = await h.joined(server, "crew", StationCatalogue.ALL, 0)
	var from: int = h.mark(crew)
	crew.reroll_modifier()
	assert_str(await _rejected(crew, NetProtocol.Type.REROLL_MODIFIER, from)).is_equal("not_host")
	for i: int in 4:
		var was: String = String(server.game.fleet.rules.modifier_id)
		from = h.mark(host)
		host.reroll_modifier()
		var fleet: Dictionary = await _fleet(
			host, from, func(ev: Dictionary) -> bool: return ev["payload"]["modifier"] != was
		)
		assert_str(fleet.get("modifier", was)).is_not_equal(was)
	var last: StringName = server.game.fleet.rules.modifier_id
	h.all_ready(server)
	host.start()
	assert_bool(await h.until(func() -> bool: return server.game.sim_running())).is_true()
	assert_str(String(server.world.rules.modifier_id)).is_equal(String(last))
	from = h.mark(host)
	host.reroll_modifier()
	var why: String = await _rejected(host, NetProtocol.Type.REROLL_MODIFIER, from)
	assert_str(why).is_equal(FleetMessages.LOBBY_CLOSED)
	var lone: NetServer = h.fleet_server(GameRules.Mode.COOP, 1, [], true, 10.0, SECRET)
	lone.game.fleet.roll_modifiers([&"only"], 1)
	var lone_host: NetClient = await h.welcomed(lone, "host", "", SECRET)
	(
		assert_bool(h.last_event(lone_host, NetProtocol.EVENT_FLEET)["payload"]["rerollable"])
		. is_false()
	)
	from = h.mark(lone_host)
	lone_host.reroll_modifier()
	var lone_why: String = await _rejected(lone_host, NetProtocol.Type.REROLL_MODIFIER, from)
	assert_str(lone_why).is_equal(FleetMessages.NO_REROLL)
