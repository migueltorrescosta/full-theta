extends GdUnitTestSuite
## L3 tests of Comms' pairs over loopback (strand F of #10, P5, P9, P14, P15): their shortcuts
## need a press like every other (D210, PROVISIONAL (Q10)), the approach lane reaches Helm
## only after Comms' press, and the cooperative events are counted for the debrief.

const PLAYER: int = NetHarness.PLAYER
const ENEMY: int = NetHarness.ENEMY
const SECRET: String = "s3cret"
const YARD_AT: Vector3 = Vector3(0.0, 0.0, -5000.0)

var h: NetHarness


func before_test() -> void:
	h = NetHarness.new(self)


func after_test() -> void:
	await h.free_all()


func _crew(server: NetServer) -> Dictionary:
	var out: Dictionary = {}
	for station: String in StationViews.CREW:
		out[station] = await h.joined(server, station, station)
	return out


func _run(server: NetServer, ticks: int = 1) -> void:
	for i: int in ticks:
		server.world.step()
		server.session.after_ticks(server.world.drain_events())
		server.session.coop.step()


func _do(server: NetServer, c: SimCommand, ticks: int = 1) -> void:
	c.ship_id = PLAYER
	server.world.submit(c)
	_run(server, ticks)


func _rejection(c: NetClient, from: int) -> String:
	var e: Dictionary = await h.next_event(
		c,
		NetProtocol.EVENT_REQUEST_REJECTED,
		from,
		func(ev: Dictionary) -> bool: return ev["payload"]["request"] == NetProtocol.Type.SHARE
	)
	return e.get("payload", {}).get("reason", "")


func _lanes(c: NetClient) -> Array:
	return h.last_event(c, NetProtocol.EVENT_LANES).get("payload", {}).get("lanes", [])


# FT: FT-PAIR-007, FT-PAIR-013
# Comms' shortcuts share like the others (Q10): Comms' lanes and contract flags, Science's
# verify chip and Relay's mission icon each count on their pair; a station that isn't the
# source, a joint view holding both stations and the toggle off are refused.
func test_comms_shortcuts_are_shared_by_a_press() -> void:
	var server: NetServer = h.server(false, 10.0, SECRET)
	var crew: Dictionary = await _crew(server)
	var coop: NetCoop = server.session.coop
	var shared: Callable = func(pair: String) -> bool:
		return coop.count_of(pair, CoopEvents.SHORTCUT_SHARED) == 1
	crew["comms"].share("lanes")
	assert_bool(await h.until(shared.bind("p5"))).is_true()
	crew["comms"].share("contract_flags")
	assert_bool(await h.until(shared.bind("p9"))).is_true()
	crew["science"].share("verify_chip")
	assert_bool(await h.until(shared.bind("p14"))).is_true()
	crew["relay"].share("mission_icon")
	assert_bool(await h.until(shared.bind("p15"))).is_true()
	for feature: StringName in [
		ViewFilter.LANES, ViewFilter.CONTRACT_FLAGS, ViewFilter.VERIFY_CHIP, ViewFilter.MISSION_ICON
	]:
		assert_bool(server.session.shares.active(PLAYER, feature)).is_true()
	var from: int = h.mark(crew["helm"])
	crew["helm"].share("lanes")
	assert_str(await _rejection(crew["helm"], from)).is_equal(NetShares.NOT_SOURCE)
	var approach: NetClient = await h.joined(server, "approach", "approach")
	from = h.mark(approach)
	approach.share("lanes")
	assert_str(await _rejection(approach, from)).is_equal(NetShares.SAME_SCREEN)
	server.session.toggles = DataToggles.of_preset("hard")
	from = h.mark(crew["comms"])
	crew["comms"].share("lanes")
	assert_str(await _rejection(crew["comms"], from)).is_equal(NetShares.OFF)
	assert_int(coop.count_of("p5", CoopEvents.SHORTCUT_SHARED)).is_equal(1)


# FT: FT-PAIR-001, FT-PAIR-007, FT-PAIR-008, FT-SPA-029
# An accepted clearance is a lane Comms sees at once; Helm gets it only after Comms' press, a
# joint view with Comms has it without one, and it is gone when the ship docks (here too
# early, so uncleared).
func test_a_clearance_is_a_lane_helm_sees_after_the_press() -> void:
	var server: NetServer = h.server(false, 10.0, SECRET)
	var crew: Dictionary = await _crew(server)
	var w: SimWorld = StoryFixture.wire(server.world)
	w.sites.register(&"yard", YARD_AT, 500.0, &"station")  # WAITS ON B: the real SiteTable
	var site: int = w.sites.open(w, &"yard")
	var clearance: PostCardCommand = StoryFixture.card(StoryTable.Kind.CONTRACT, &"", site)
	clearance.source = SimCommand.Source.SERVER
	clearance.lane_open_s = 10.0
	clearance.lane_s = 30.0
	_do(server, clearance)
	var accept: AcceptCardCommand = AcceptCardCommand.new()
	accept.card = 0
	_do(server, accept)
	(
		assert_bool(await h.until(func() -> bool: return not _lanes(crew["comms"]).is_empty()))
		. is_true()
	)
	var lane: Dictionary = _lanes(crew["comms"])[0]
	assert_float(lane["z"]).is_equal(YARD_AT.z)
	assert_float(lane["open_s"]).is_between(9.0, 10.0)
	assert_float(lane["close_s"]).is_between(39.0, 40.0)
	await h.wait(150)
	assert_array(_lanes(crew["helm"])).is_empty()
	var approach: NetClient = await h.joined(server, "approach", "approach")
	assert_bool(await h.until(func() -> bool: return not _lanes(approach).is_empty())).is_true()
	crew["comms"].share("lanes")
	assert_bool(await h.until(func() -> bool: return not _lanes(crew["helm"]).is_empty())).is_true()
	# Docked before the window opens: the lane goes, Helm and Comms are told.
	StoryFixture.dock(server.world, PLAYER, site)
	_run(server, 2)
	assert_bool(await h.until(func() -> bool: return _lanes(crew["helm"]).is_empty())).is_true()
	assert_dict(await h.next_event(crew["helm"], "dock_uncleared")).is_not_empty()
	assert_dict(await h.next_event(crew["comms"], "dock_uncleared")).is_not_empty()
	assert_array(h.events_of(crew["engineering"], "dock_uncleared")).is_empty()


# FT: FT-PAIR-001, FT-PAIR-013
# Relay's mark on the contact of a mission card marks the mission, counted as a mark Comms'
# card used; a mark on some other contact marks nothing.
func test_a_relay_mark_on_a_missions_contact_marks_the_mission() -> void:
	var server: NetServer = h.server(false, 10.0, SECRET)
	var crew: Dictionary = await _crew(server)
	var w: SimWorld = StoryFixture.wire(server.world)
	var mission: PostCardCommand = StoryFixture.card(StoryTable.Kind.MISSION)
	mission.source = SimCommand.Source.SERVER
	mission.target = ENEMY
	_do(server, mission, 3)
	assert_bool(StoryRules.is_marked(w, 0)).is_false()
	var from: int = h.mark(crew["relay"])
	crew["relay"].place_mark(-1, "Quarry", ENEMY, Vector3.ZERO)
	await h.next_event(crew["relay"], NetProtocol.EVENT_MARKS, from)
	_run(server, 2)
	assert_bool(StoryRules.is_marked(w, 0)).is_true()
	assert_int(server.session.coop.count_of("p15", CoopEvents.MARK_USED)).is_equal(1)


# FT: FT-PAIR-013
# A reply that a scan fact unlocked is a cooperative event of Science and Comms (P14); a
# lane Helm docked by in its window one of Helm and Comms (P5), a marked mission one of Relay
# and Comms (P15); a surrendered contact destroyed is a debrief line of Weapons and Comms
# (P9) and no cooperative event.
func test_comms_pair_events_are_counted() -> void:
	var server: NetServer = h.server(false, 10.0, SECRET)
	var w: SimWorld = StoryFixture.wire(server.world)
	var coop: NetCoop = server.session.coop
	_run(server, 3)
	var hail: HailCommand = HailCommand.new()
	hail.target = ENEMY
	_do(server, hail)
	Story.learn_fact(w, w.faction_of(PLAYER), ENEMY, "cargo")
	var reply: ReplyCommand = ReplyCommand.new()
	reply.card = 0
	reply.option = &"o3"
	_do(server, reply)
	assert_int(coop.count_of("p14", CoopEvents.SCAN_OPTION)).is_equal(1)
	assert_int(coop.cooperative("p14")).is_equal(1)
	w.emit(&"dock_cleared", PLAYER, 0)
	w.emit(&"mission_marked", PLAYER, 0)
	w.emit(&"surrender_killed", PLAYER, ENEMY, -11.0, Vector3.ZERO, &"debrief.surrender_killed")
	server.session.after_ticks(w.drain_events())
	assert_int(coop.count_of("p5", CoopEvents.MARK_USED)).is_equal(1)
	assert_int(coop.count_of("p15", CoopEvents.MARK_USED)).is_equal(1)
	assert_int(coop.count_of("p9", CoopEvents.SURRENDER_KILLED)).is_equal(1)
	assert_int(coop.cooperative("p9")).is_equal(0)
