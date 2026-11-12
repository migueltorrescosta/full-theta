extends GdUnitTestSuite
## L3 lobby tests (T043): the catalogue, picks, the coverage check, Start and the dev
## flag, with real clients over loopback.

const PLAYER: int = NetHarness.PLAYER

var h: NetHarness


func before_test() -> void:
	h = NetHarness.new(self)


func after_test() -> void:
	await h.free_all()


# FT: FT-NET-015, FT-NET-017, FT-STN-015, FT-M1-018, FT-M1-006
# The catalogue offers the six stations, the 15 joint views, Captain and Viewer, in
# that order, each with its SeatDef and load tag, and nothing else without the dev
# flag.
func test_catalogue_offers_m1_seats_with_load_tags() -> void:
	var server: NetServer = h.server()
	var c: NetClient = await h.welcomed(server, "a")
	assert_bool(await h.until(func() -> bool: return not c.catalogue.is_empty())).is_true()
	var seats: Array = c.catalogue["seats"]
	var ids: Array = seats.map(func(e: Dictionary) -> String: return e["id"])
	assert_array(ids).is_equal(
		[
			"helm",
			"weapons",
			"engineering",
			"science",
			"relay",
			"comms",
			"drive",
			"tactical",
			"survey",
			"nav",
			"approach",
			"gunnery",
			"targeting",
			"fire_control",
			"parley",
			"systems",
			"logistics",
			"quartermaster",
			"sensors",
			"intel",
			"ops",
			"captain",
			"viewer"
		]
	)
	var tags: Array = seats.map(func(e: Dictionary) -> String: return e["load_tag"])
	assert_array(tags).is_equal(
		[
			"intense",
			"intense",
			"busy",
			"busy",
			"light",
			"light",
			"intense",
			"intense",
			"intense",
			"intense",
			"intense",
			"intense",
			"intense",
			"intense",
			"intense",
			"busy",
			"busy",
			"busy",
			"busy",
			"busy",
			"light",
			"light",
			""
		]
	)
	for e: Dictionary in seats:
		assert_dict(e).is_equal(StationCatalogue.def(e["id"]).to_dict())
	assert_array(c.catalogue["load_tags"]).is_equal(["light", "busy", "intense"])
	c.pick(PLAYER, StationCatalogue.ALL)
	var answer: Dictionary = await h.next_event(c, NetProtocol.EVENT_PICKED)
	assert_str(answer["payload"]["reason"]).is_equal(NetGame.BAD_PICK)
	var from: int = h.mark(c)
	c.pick(PLAYER, "p2")
	answer = await h.next_event(c, NetProtocol.EVENT_PICKED, from)
	assert_str(answer["payload"]["reason"]).is_equal(NetGame.BAD_PICK)


# FT: FT-NET-015, FT-NET-016
# A player holds exactly one seat (a new pick replaces the old); any number may share
# a station or a joint view; a second Captain on the same ship is refused until the
# seat is free again.
func test_one_pick_sharing_and_one_captain() -> void:
	var server: NetServer = h.server()
	var a: NetClient = await h.joined(server, "a", "helm")
	var b: NetClient = await h.joined(server, "b", "helm")
	var c: NetClient = await h.joined(server, "c", "tactical")
	var d: NetClient = await h.joined(server, "d", "tactical")
	assert_array(server.game.seats_of(PLAYER)).contains_exactly_in_any_order(
		["helm", "helm", "tactical", "tactical"]
	)
	assert_bool(await h.pick(a, "systems")).is_true()
	assert_str(h.session_of(server, a).seat).is_equal("systems")
	assert_array(server.game.seats_of(PLAYER)).contains_exactly_in_any_order(
		["systems", "helm", "tactical", "tactical"]
	)
	assert_bool(a.snap.blocks.has(StationCatalogue.Section.ENGINEERING)).is_true()
	assert_bool(a.snap.blocks.has(StationCatalogue.Section.HELM)).is_false()
	assert_bool(await h.pick(b, "captain")).is_true()
	var from: int = h.mark(c)
	c.pick(PLAYER, "captain")
	var refused: Dictionary = await h.next_event(c, NetProtocol.EVENT_PICKED, from)
	assert_str(refused["payload"]["reason"]).is_equal(NetGame.CAPTAIN_TAKEN)
	assert_str(h.session_of(server, c).seat).is_equal("tactical")
	var lobby: Dictionary = h.last_event(d, NetProtocol.EVENT_LOBBY)
	assert_str(lobby["payload"]["captain"]).is_equal("b")
	# The station grid names who sits where (D216), and who is Ready (#37 C1).
	var seats: Array = lobby["payload"]["seats"]
	(
		assert_array(seats.map(func(r: Dictionary) -> Array: return [r["name"], r["seat"]]))
		. contains_exactly_in_any_order(
			[["a", "systems"], ["b", "captain"], ["c", "tactical"], ["d", "tactical"]]
		)
	)
	var ids: Array = [a, b, c, d].map(func(x: NetClient) -> int: return h.session_of(server, x).id)
	for r: Dictionary in seats:
		assert_bool(r["ready"]).is_false()
		assert_array(ids).contains([r["session"]])
	b.release_pick()
	assert_bool(await h.until(func() -> bool: return h.session_of(server, b).seat == "")).is_true()
	assert_bool(await h.pick(c, "captain")).is_true()


# FT: FT-NET-019, FT-NET-020, FT-NET-021, FT-GEN-004, FT-GEN-005, FT-GEN-006
# Start works only once the coverage check passes: with Tactical and Systems (2 crew)
# plus a Captain and a Viewer the lobby lists Relay and Comms as uncovered and refuses
# a Ready crew player's Start (no host here, #37 C1); Captain and Viewer can't say Ready or
# start; Ops makes it pass, and Start starts the run (the sim steps from then on, not before).
func test_start_needs_three_crew_covering_six_stations() -> void:
	var server: NetServer = h.server()
	var tac: NetClient = await h.joined(server, "tac", "tactical")
	var sys: NetClient = await h.joined(server, "sys", "systems")
	var cap: NetClient = await h.joined(server, "cap", "captain")
	var view: NetClient = await h.joined(server, "view", "viewer")
	var uncovered_ok: Callable = func(e: Dictionary) -> bool:
		return e["payload"]["uncovered"] == ["relay", "comms"]
	var lobby: Dictionary = await h.next_event(view, NetProtocol.EVENT_LOBBY, 0, uncovered_ok)
	assert_int(lobby["payload"]["crew"]).is_equal(2)
	assert_bool(lobby["payload"]["covered"]).is_false()
	var tick: int = server.world.tick
	var from: int = h.mark(tac)
	tac.set_ready(true)
	tac.start()
	var refused: Dictionary = await h.next_event(tac, NetProtocol.EVENT_REQUEST_REJECTED, from)
	assert_int(refused["payload"]["request"]).is_equal(NetProtocol.Type.START)
	assert_str(refused["payload"]["reason"]).is_equal(NetGame.NOT_COVERED)
	assert_array(refused["payload"]["uncovered"]).is_equal(["relay", "comms"])
	from = h.mark(cap)
	cap.set_ready(true)
	refused = await h.next_event(cap, NetProtocol.EVENT_REQUEST_REJECTED, from)
	assert_int(refused["payload"]["request"]).is_equal(NetProtocol.Type.READY)
	assert_str(refused["payload"]["reason"]).is_equal(NetGame.NOT_CREW)
	from = h.mark(cap)
	cap.start()
	refused = await h.next_event(cap, NetProtocol.EVENT_REQUEST_REJECTED, from)
	assert_str(refused["payload"]["reason"]).is_equal(NetGame.NOT_CREW)
	await h.wait(300)
	assert_int(server.world.tick).is_equal(tick)
	assert_bool(server.game.lobby.launched.is_empty()).is_true()
	var ops: NetClient = await h.joined(server, "ops", "ops")
	var ready_ok: Callable = func(e: Dictionary) -> bool: return e["payload"]["covered"]
	lobby = await h.next_event(sys, NetProtocol.EVENT_LOBBY, 0, ready_ok)
	assert_array(lobby["payload"]["uncovered"]).is_empty()
	assert_int(lobby["payload"]["crew"]).is_equal(3)
	assert_bool(await h.start(server, ops)).is_true()
	var go: Dictionary = await h.next_event(view, NetProtocol.EVENT_STARTED)
	assert_int(go["payload"]["ship"]).is_equal(PLAYER)
	var started: Callable = func(e: Dictionary) -> bool: return e["payload"]["started"]
	assert_dict(await h.next_event(view, NetProtocol.EVENT_LOBBY, 0, started)).is_not_empty()
	assert_bool(server.game.sim_running()).is_true()


# FT: FT-NET-019, FT-NET-021
# Ready is a toggle per crew player (#37 C1): the lobby's seat rows show it, Ready{false}
# takes it back, a seat change clears it; a crew player not Ready can't start, and the
# others' names come with `not_ready`.
func test_ready_is_a_toggle_that_a_seat_change_clears() -> void:
	var server: NetServer = h.server()
	var crew: Array[NetClient] = await h.crew3(server)
	var tac: NetClient = crew[0]
	var seat_ready: Callable = func(e: Dictionary, name: String, want: bool) -> bool:
		for row: Dictionary in e["payload"]["seats"]:
			if row["name"] == name:
				return row["ready"] == want
		return false
	var from: int = h.mark(tac)
	tac.set_ready(true)
	var on: Dictionary = await h.next_event(
		tac, NetProtocol.EVENT_LOBBY, from, seat_ready.bind("tactical", true)
	)
	assert_dict(on).is_not_empty()
	assert_bool(h.session_of(server, tac).ready).is_true()
	tac.set_ready(false)
	assert_bool(await h.until(func() -> bool: return not h.session_of(server, tac).ready)).is_true()
	tac.set_ready(true)
	assert_bool(await h.until(func() -> bool: return h.session_of(server, tac).ready)).is_true()
	from = h.mark(tac)
	tac.start()
	var refused: Dictionary = await h.next_event(tac, NetProtocol.EVENT_REQUEST_REJECTED, from)
	assert_str(refused["payload"]["reason"]).is_equal(NetGame.NOT_READY)
	assert_array(refused["payload"]["waiting"]).is_equal(["systems", "ops"])
	from = h.mark(crew[1])
	crew[1].start()
	refused = await h.next_event(crew[1], NetProtocol.EVENT_REQUEST_REJECTED, from)
	assert_str(refused["payload"]["reason"]).is_equal(NetGame.NOT_READY)
	assert_bool(await h.pick(tac, "drive")).is_true()
	assert_bool(h.session_of(server, tac).ready).is_false()
	assert_bool(server.game.lobby.launched.is_empty()).is_true()


# FT: FT-NET-019
# The host starts the game (#37 C1): its own Start is its Ready, a crew player's Start is
# refused `not_host` while the host is connected, and the host's waits for every crew
# player's Ready. Once the host drops, a Ready crew player may Start (the no-host rule), and
# the `fleet` event says no host is here.
func test_the_host_starts_and_without_one_a_ready_player_does() -> void:
	var server: NetServer = h.server(false, 10.0, "s3cret")
	var host: NetClient = await h.welcomed(server, "host", "", "s3cret")
	await h.pick(host, "tactical")
	var sys: NetClient = await h.joined(server, "sys", "systems")
	var ops: NetClient = await h.joined(server, "ops", "ops")
	assert_bool(await h.say_ready(server, [sys])).is_true()
	var from: int = h.mark(ops)
	ops.set_ready(true)
	ops.start()
	var refused: Dictionary = await h.next_event(ops, NetProtocol.EVENT_REQUEST_REJECTED, from)
	assert_str(refused["payload"]["reason"]).is_equal(NetGame.NOT_HOST)
	ops.set_ready(false)
	assert_bool(await h.until(func() -> bool: return not h.session_of(server, ops).ready)).is_true()
	from = h.mark(host)
	host.start()
	refused = await h.next_event(host, NetProtocol.EVENT_REQUEST_REJECTED, from)
	assert_str(refused["payload"]["reason"]).is_equal(NetGame.NOT_READY)
	assert_array(refused["payload"]["waiting"]).is_equal(["ops"])
	assert_bool(server.game.lobby.host_here()).is_true()
	host.bye()
	assert_bool(await h.until(func() -> bool: return not server.game.lobby.host_here())).is_true()
	var no_host: Callable = func(e: Dictionary) -> bool: return not e["payload"]["host"]
	assert_dict(await h.next_event(sys, NetProtocol.EVENT_FLEET, 0, no_host)).is_not_empty()
	assert_bool(await h.say_ready(server, [ops])).is_true()
	assert_bool(await h.start(server, sys)).is_true()


# FT: FT-NET-029, FT-M1-015
# With --dev-all-stations the catalogue offers the dev seat, one client holds every
# station with it, and it can start alone (the 3-player minimum is bypassed); its
# snapshots carry every station's sections.
func test_dev_flag_lets_one_client_hold_all_stations() -> void:
	var server: NetServer = h.server(true)
	var c: NetClient = await h.joined(server, "solo", StationCatalogue.ALL)
	assert_bool(c.welcome["dev_all"]).is_true()
	var ids: Array = (c.catalogue["seats"] as Array).map(
		func(e: Dictionary) -> String: return e["id"]
	)
	assert_array(ids).contains([StationCatalogue.ALL])
	for kind: int in [
		StationCatalogue.Section.HELM,
		StationCatalogue.Section.ENGINEERING,
		StationCatalogue.Section.MOUNTS
	]:
		assert_bool(c.snap.blocks.has(kind)).is_true()
	assert_bool(await h.start(server, c)).is_true()
	# Alone on every station: every claim is its own (FT-NET-044).
	var me: int = h.session_of(server, c).id
	for item: String in ["flight", "shield_facing", "mount:0", "crew:0", "crew:1"]:
		assert_int(server.game.claims.holder(PLAYER, item)).is_equal(me)
	c.fire()
	c.helm(1.0)
	await h.wait(300)
	assert_array(h.events_of(c, NetProtocol.EVENT_COMMAND_REJECTED)).is_empty()


# FT: FT-NET-043
# Outside a pause, a mid-run catalogue change that would make the ship fail coverage
# gets CommandRejected (seq -1, breaks_coverage) and the pick stays; one that keeps
# coverage is accepted.
func test_mid_run_change_must_keep_coverage() -> void:
	var server: NetServer = h.server()
	var crew: Array[NetClient] = await h.crew3(server)
	assert_bool(await h.start(server, crew[0])).is_true()
	var from: int = h.mark(crew[0])
	crew[0].pick(PLAYER, "helm")
	var rejected: Dictionary = await h.next_event(crew[0], NetProtocol.EVENT_COMMAND_REJECTED, from)
	assert_int(rejected["payload"]["seq"]).is_equal(-1)
	assert_str(rejected["payload"]["reason"]).is_equal(CommandGate.BREAKS_COVERAGE)
	var picked: Dictionary = await h.next_event(crew[0], NetProtocol.EVENT_PICKED, from)
	assert_str(picked["payload"]["reason"]).is_equal(CommandGate.BREAKS_COVERAGE)
	assert_str(h.session_of(server, crew[0]).seat).is_equal("tactical")
	from = h.mark(crew[2])
	crew[2].release_pick()
	rejected = await h.next_event(crew[2], NetProtocol.EVENT_COMMAND_REJECTED, from)
	assert_str(rejected["payload"]["reason"]).is_equal(CommandGate.BREAKS_COVERAGE)
	# A fourth player takes Weapons; now Tactical may move to Helm.
	var extra: NetClient = await h.joined(server, "weapons", "weapons")
	assert_str(h.session_of(server, extra).seat).is_equal("weapons")
	assert_bool(await h.pick(crew[0], "helm")).is_true()
	assert_bool(server.game.sim_running()).is_true()


# FT: FT-NET-013, FT-NET-030
# The welcome says whether the server serves HTTPS and WSS (D294), so the host's lobby shows
# an https join URL.
func test_welcome_says_whether_the_server_uses_tls() -> void:
	var server: NetServer = h.server()
	var plain: NetClient = await h.welcomed(server, "plain")
	assert_bool(plain.welcome["tls"]).is_false()
	server.game.tls = true
	var secure: NetClient = await h.welcomed(server, "secure")
	assert_bool(secure.welcome["tls"]).is_true()


# FT: FT-NET-004, FT-NET-015
# #35 A5: a player renames mid-session (a phone that joined by QR code with no name): the
# lobby's seats show the new name, an empty name is ignored.
func test_rename_changes_the_seat_name_in_the_lobby() -> void:
	var server: NetServer = h.server()
	var c: NetClient = await h.joined(server, "Player", "helm")
	var other: NetClient = await h.joined(server, "bo", "weapons")
	var seat_names: Callable = func() -> Array:
		var lobby: Dictionary = h.last_event(other, NetProtocol.EVENT_LOBBY)
		var seats: Array = lobby.get("payload", {}).get("seats", [])
		return seats.map(func(s: Dictionary) -> String: return s["name"])
	c.rename("  Ana  ")
	assert_bool(await h.until(func() -> bool: return "Ana" in seat_names.call())).is_true()
	assert_str(h.session_of(server, c).name).is_equal("Ana")
	assert_str(c.name).is_equal("Ana")
	c.rename("   ")
	await h.wait(200)
	assert_str(h.session_of(server, c).name).is_equal("Ana")


# FT: FT-NET-015
# R24-13: two players with the same name are told apart: the second "Player" to join is
# "Player 2", the third "Player 3", and a rename to a taken name is numbered too.
func test_duplicate_names_are_numbered() -> void:
	var server: NetServer = h.server()
	var a: NetClient = await h.joined(server, "Player", "helm")
	var b: NetClient = await h.joined(server, "Player", "weapons")
	var c: NetClient = await h.joined(server, "Player", "engineering")
	assert_str(h.session_of(server, a).name).is_equal("Player")
	assert_str(h.session_of(server, b).name).is_equal("Player 2")
	assert_str(h.session_of(server, c).name).is_equal("Player 3")
	a.rename("Ana")
	(
		assert_bool(await h.until(func() -> bool: return h.session_of(server, a).name == "Ana"))
		. is_true()
	)
	c.rename("Ana")
	var numbered: Callable = func() -> bool: return h.session_of(server, c).name == "Ana 2"
	assert_bool(await h.until(numbered)).is_true()
