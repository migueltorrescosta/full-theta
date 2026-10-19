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
# The catalogue offers the six stations, Tactical, Systems, Ops, Captain and Viewer, in
# that order, each with its StationDef and load tag, and nothing else without the dev
# flag.
func test_catalogue_offers_m1_entries_with_load_tags() -> void:
	var server: NetServer = h.server()
	var c: NetClient = await h.welcomed(server, "a")
	assert_bool(await h.until(func() -> bool: return not c.catalogue.is_empty())).is_true()
	var entries: Array = c.catalogue["entries"]
	var ids: Array = entries.map(func(e: Dictionary) -> String: return e["id"])
	assert_array(ids).is_equal(
		[
			"helm",
			"weapons",
			"engineering",
			"science",
			"relay",
			"comms",
			"tactical",
			"systems",
			"ops",
			"captain",
			"viewer"
		]
	)
	var tags: Array = entries.map(func(e: Dictionary) -> String: return e["load_tag"])
	assert_array(tags).is_equal(
		[
			"intense",
			"intense",
			"busy",
			"busy",
			"light",
			"light",
			"intense",
			"busy",
			"light",
			"light",
			""
		]
	)
	for e: Dictionary in entries:
		assert_dict(e).is_equal(StationViews.def(e["id"]).to_dict())
	assert_array(c.catalogue["load_tags"]).is_equal(["light", "busy", "intense"])
	c.pick(PLAYER, StationViews.ALL)
	var answer: Dictionary = await h.next_event(c, NetProtocol.EVENT_PICKED)
	assert_str(answer["payload"]["reason"]).is_equal(ServerSession.BAD_PICK)
	var from: int = h.mark(c)
	c.pick(PLAYER, "p2")
	answer = await h.next_event(c, NetProtocol.EVENT_PICKED, from)
	assert_str(answer["payload"]["reason"]).is_equal(ServerSession.BAD_PICK)


# FT: FT-NET-015, FT-NET-016
# A player holds exactly one entry (a new pick replaces the old); any number may share
# a station or a joint view; a second Captain on the same ship is refused until the
# seat is free again.
func test_one_pick_sharing_and_one_captain() -> void:
	var server: NetServer = h.server()
	var a: NetClient = await h.joined(server, "a", "helm")
	var b: NetClient = await h.joined(server, "b", "helm")
	var c: NetClient = await h.joined(server, "c", "tactical")
	var d: NetClient = await h.joined(server, "d", "tactical")
	assert_array(server.session.entries_of(PLAYER)).contains_exactly_in_any_order(
		["helm", "helm", "tactical", "tactical"]
	)
	assert_bool(await h.pick(a, "systems")).is_true()
	assert_str(h.session_of(server, a).entry).is_equal("systems")
	assert_array(server.session.entries_of(PLAYER)).contains_exactly_in_any_order(
		["systems", "helm", "tactical", "tactical"]
	)
	assert_bool(a.view.blocks.has(StationViews.Section.ENGINEERING)).is_true()
	assert_bool(a.view.blocks.has(StationViews.Section.HELM)).is_false()
	assert_bool(await h.pick(b, "captain")).is_true()
	var from: int = h.mark(c)
	c.pick(PLAYER, "captain")
	var refused: Dictionary = await h.next_event(c, NetProtocol.EVENT_PICKED, from)
	assert_str(refused["payload"]["reason"]).is_equal(ServerSession.CAPTAIN_TAKEN)
	assert_str(h.session_of(server, c).entry).is_equal("tactical")
	var lobby: Dictionary = h.last_event(d, NetProtocol.EVENT_LOBBY)
	assert_str(lobby["payload"]["captain"]).is_equal("b")
	b.release_pick()
	assert_bool(await h.until(func() -> bool: return h.session_of(server, b).entry == "")).is_true()
	assert_bool(await h.pick(c, "captain")).is_true()


# FT: FT-NET-019, FT-NET-020, FT-NET-021, FT-GEN-004, FT-GEN-005, FT-GEN-006, FT-GEN-007
# Start works only once the coverage check passes: with Tactical and Systems (2 crew)
# plus a Captain and a Viewer the lobby lists Relay and Comms as uncovered and refuses
# Start; Captain and Viewer can't start; Ops makes it pass, and Start starts the run
# (the sim steps from then on, not before).
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
	assert_bool(lobby["payload"]["ready"]).is_false()
	var tick: int = server.world.tick
	var from: int = h.mark(tac)
	tac.set_ready(true)
	var refused: Dictionary = await h.next_event(tac, ServerSession.EVENT_REQUEST_REJECTED, from)
	assert_str(refused["payload"]["reason"]).is_equal(ServerSession.NOT_COVERED)
	assert_array(refused["payload"]["uncovered"]).is_equal(["relay", "comms"])
	from = h.mark(cap)
	cap.set_ready(true)
	refused = await h.next_event(cap, ServerSession.EVENT_REQUEST_REJECTED, from)
	assert_str(refused["payload"]["reason"]).is_equal(ServerSession.NOT_CREW)
	await h.wait(300)
	assert_int(server.world.tick).is_equal(tick)
	assert_bool(server.session.launched.is_empty()).is_true()
	var ops: NetClient = await h.joined(server, "ops", "ops")
	var ready_ok: Callable = func(e: Dictionary) -> bool: return e["payload"]["ready"]
	lobby = await h.next_event(sys, NetProtocol.EVENT_LOBBY, 0, ready_ok)
	assert_array(lobby["payload"]["uncovered"]).is_empty()
	assert_int(lobby["payload"]["crew"]).is_equal(3)
	assert_bool(await h.start(server, ops)).is_true()
	var go: Dictionary = await h.next_event(view, NetProtocol.EVENT_STARTED)
	assert_int(go["payload"]["ship"]).is_equal(PLAYER)
	var started: Callable = func(e: Dictionary) -> bool: return e["payload"]["started"]
	assert_dict(await h.next_event(view, NetProtocol.EVENT_LOBBY, 0, started)).is_not_empty()
	assert_bool(server.session.sim_running()).is_true()


# FT: FT-NET-029, FT-M1-015
# With --dev-all-stations the catalogue offers the dev entry, one client holds every
# station with it, and it can start alone (the 3-player minimum is bypassed); its
# snapshots carry every station's sections.
func test_dev_flag_lets_one_client_hold_all_stations() -> void:
	var server: NetServer = h.server(true)
	var c: NetClient = await h.joined(server, "solo", StationViews.ALL)
	assert_bool(c.welcome["dev_all"]).is_true()
	var ids: Array = (c.catalogue["entries"] as Array).map(
		func(e: Dictionary) -> String: return e["id"]
	)
	assert_array(ids).contains([StationViews.ALL])
	for kind: int in [
		StationViews.Section.HELM, StationViews.Section.ENGINEERING, StationViews.Section.MOUNTS
	]:
		assert_bool(c.view.blocks.has(kind)).is_true()
	assert_bool(await h.start(server, c)).is_true()
	# Alone on every station: every claim is its own (FT-NET-044).
	var me: int = h.session_of(server, c).id
	for item: String in ["flight", "shield_facing", "mount:0", "crew:0", "crew:1"]:
		assert_int(server.session.claims.holder(PLAYER, item)).is_equal(me)
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
	assert_str(h.session_of(server, crew[0]).entry).is_equal("tactical")
	from = h.mark(crew[2])
	crew[2].release_pick()
	rejected = await h.next_event(crew[2], NetProtocol.EVENT_COMMAND_REJECTED, from)
	assert_str(rejected["payload"]["reason"]).is_equal(CommandGate.BREAKS_COVERAGE)
	# A fourth player takes Weapons; now Tactical may move to Helm.
	var extra: NetClient = await h.joined(server, "weapons", "weapons")
	assert_str(h.session_of(server, extra).entry).is_equal("weapons")
	assert_bool(await h.pick(crew[0], "helm")).is_true()
	assert_bool(server.session.sim_running()).is_true()
