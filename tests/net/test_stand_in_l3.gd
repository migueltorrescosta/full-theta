extends GdUnitTestSuite
## L3 tests of the stand-in and fill bots over loopback (#40 D1, D2; gp-01 to gp-03): a dropped
## crew player's stations go to a stand-in bot when the grace ends, the run goes on and the
## player gets them back on rejoin; with the host's "Pause when someone drops" the coverage
## pause comes instead; with "Fill light stations with bots" two players start a ship.

const PLAYER: int = NetHarness.PLAYER
const GRACE_S: float = 0.6

var h: NetHarness


func before_test() -> void:
	h = NetHarness.new(self)


func after_test() -> void:
	await h.free_all()


## A server with the stand-ins on (the host's pause option off, its default).
func _server() -> NetServer:
	var server: NetServer = h.server(false, GRACE_S)
	server.game.lobby.drop_pause = false
	return server


## A started ship with Tactical, Systems and Ops, plus any extra seats.
func _running(server: NetServer, extra: Array[String] = []) -> Array[NetClient]:
	var crew: Array[NetClient] = await h.crew3(server)
	for seat: String in extra:
		crew.append(await h.joined(server, seat, seat))
	assert_bool(await h.start(server, crew[0])).is_true()
	return crew


## Drops a client and waits until its grace ran out.
func _lose(server: NetServer, c: NetClient) -> void:
	var gone: NetSession = h.session_of(server, c)
	await h.drop(server, c)
	await h.lapsed(gone)


## The ship's bot rows as the latest `lobby` event `c` got says them.
func _bots(c: NetClient) -> Array:
	var e: Dictionary = h.last_event(c, NetProtocol.EVENT_LOBBY)
	return [] if e.is_empty() else e["payload"].get("bots", [])


# FT: FT-NET-048, FT-NET-033
# Option off (the default): when the grace of Ops ends a stand-in takes Relay and Comms for
# them, the universe never pauses, the lobby names the bot for the player, and the bots act
# (their commands land in the log).
func test_stand_in_takes_over_after_the_grace() -> void:
	var server: NetServer = _server()
	var crew: Array[NetClient] = await _running(server)
	await _lose(server, crew[0])
	assert_bool(server.game.lobby.paused.is_empty()).is_true()
	assert_bool(server.game.sim_running()).is_true()
	assert_array(h.events_of(crew[1], NetProtocol.EVENT_PAUSE)).is_empty()
	var held: Dictionary = server.game.lobby.bots[PLAYER]
	assert_array(held.keys()).contains_exactly_in_any_order(["helm", "weapons"])
	assert_str(held["helm"][1]).is_equal("tactical")
	var named: Callable = func() -> bool:
		return (
			_bots(crew[1])
			== [{"seat": "helm", "for": "tactical"}, {"seat": "weapons", "for": "tactical"}]
		)
	assert_bool(await h.until(named)).is_true()
	assert_bool(server.game.lobby.covered(PLAYER)).is_true()
	var acted: Callable = func() -> bool:
		for c: SimCommand in server.world.command_log:
			if c.tick > 0 and c is HelmSelectCommand and c.ship_id == PLAYER:
				return true
		return false
	assert_bool(await h.until(acted)).is_true()


# FT: FT-NET-048, FT-NET-026
# The dropped player rejoins after the grace: the seat (and its free claims) come back to
# them and the bot leaves.
func test_rejoin_takes_the_seat_back_from_the_bot() -> void:
	var server: NetServer = _server()
	var crew: Array[NetClient] = await _running(server)
	var token: String = crew[2].token
	await _lose(server, crew[2])
	assert_array(server.game.lobby.bots[PLAYER].keys()).contains_exactly_in_any_order(
		["relay", "comms"]
	)
	var again: NetClient = await h.welcomed(server, "ops", token)
	assert_str(again.welcome["seat"]).is_equal("ops")
	assert_bool(server.game.lobby.bots[PLAYER].is_empty()).is_true()
	assert_bool(server.game.sim_running()).is_true()


# FT: FT-NET-048
# The ship's Captain takes a bot's station with a plain pick (no pause needed): that bot
# leaves, the other stays.
func test_a_player_taking_a_bot_station_sends_it_away() -> void:
	var server: NetServer = _server()
	var crew: Array[NetClient] = await _running(server, ["captain"])
	await _lose(server, crew[2])
	assert_bool(await h.pick(crew[3], "relay")).is_true()
	assert_array(server.game.lobby.bots[PLAYER].keys()).is_equal(["comms"])


# FT: FT-NET-034, FT-NET-048
# Option on: no stand-in, the grace ends in the coverage pause as before (D83).
func test_the_host_option_pauses_instead() -> void:
	var server: NetServer = _server()
	server.game.lobby.drop_pause = true
	var crew: Array[NetClient] = await _running(server)
	await _lose(server, crew[2])
	assert_bool(await h.until(func() -> bool: return server.game.lobby.any_paused())).is_true()
	assert_bool(server.game.lobby.bots.is_empty()).is_true()


# FT: FT-NET-049
# Fill light stations with bots: Helm and Weapons held by two players pass coverage ("crew
# 2/2", the light stations shown as bots to come); Start puts fill bots on the four light
# stations. One player alone, or without the option, is refused.
func test_two_players_start_with_fill_bots() -> void:
	var server: NetServer = _server()
	var helm: NetClient = await h.joined(server, "ana", "helm")
	var guns: NetClient = await h.joined(server, "bo", "weapons")
	var refused: Array = server.game.lobby.start_refusal(h.session_of(server, helm), true)
	assert_str(refused[0]).is_equal(NetGame.NOT_COVERED)
	assert_array(refused[1]["uncovered"]).is_equal(["engineering", "science", "relay", "comms"])
	server.game.lobby.fill_bots = true
	server.game.lobby.mark_dirty()
	var state: Dictionary = server.game.lobby_state(PLAYER)
	assert_bool(state["covered"]).is_true()
	assert_int(state["crew"]).is_equal(2)
	assert_int(state["min_crew"]).is_equal(2)
	assert_int((state["bots"] as Array).size()).is_equal(4)
	assert_str(state["bots"][0]["for"]).is_empty()
	guns.release_pick()
	await h.until(func() -> bool: return not h.session_of(server, guns).has_pick())
	assert_bool(server.game.lobby.covered(PLAYER)).is_false()
	assert_array(server.game.lobby.open_stations(PLAYER)).is_equal(["weapons"])
	assert_bool(await h.pick(guns, "weapons")).is_true()
	assert_bool(await h.start(server, helm)).is_true()
	assert_array(server.game.lobby.bots[PLAYER].keys()).contains_exactly_in_any_order(
		NetLobby.LIGHT_STATIONS
	)
	# A third player takes Relay from its bot later on.
	var late: NetClient = await h.joined(server, "cy", "relay")
	assert_bool(late.is_welcomed()).is_true()
	assert_bool(server.game.lobby.bots[PLAYER].has("relay")).is_false()


# FT: FT-NET-049
# One player on Tactical (Helm and Weapons) is still one player: fill bots never make a crew
# of one.
func test_fill_bots_need_two_players() -> void:
	var server: NetServer = _server()
	server.game.lobby.fill_bots = true
	await h.joined(server, "ana", "tactical")
	assert_bool(server.game.lobby.covered(PLAYER)).is_false()
	assert_array(server.game.lobby.open_stations(PLAYER)).is_empty()
