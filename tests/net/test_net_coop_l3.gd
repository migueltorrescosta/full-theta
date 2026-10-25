extends GdUnitTestSuite
## L3 tests of the cooperative events counted per pair for the debrief (NetCoop, CoopEvents,
## FT-PAIR-013): a data shortcut shared by a press, a mark placed by one station and used by
## another, a probe-enabled scan, and the pair table itself.

const PLAYER: int = NetHarness.PLAYER
const ENEMY: int = NetHarness.ENEMY
const SECRET: String = "s3cret"

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


# FT: FT-PAIR-013
# The 15 pairs are numbered as in spec §7.3, in either station order, and the pair of a
# station with itself is none.
func test_pair_ids_follow_the_pair_table() -> void:
	var table: Array = [
		["engineering", "helm"],
		["helm", "weapons"],
		["helm", "science"],
		["helm", "relay"],
		["helm", "comms"],
		["weapons", "engineering"],
		["weapons", "science"],
		["weapons", "relay"],
		["weapons", "comms"],
		["engineering", "science"],
		["engineering", "relay"],
		["engineering", "comms"],
		["science", "relay"],
		["science", "comms"],
		["relay", "comms"],
	]
	for i: int in table.size():
		assert_str(CoopEvents.pair_of(table[i][0], table[i][1])).is_equal("p%d" % (i + 1))
		assert_str(CoopEvents.pair_of(table[i][1], table[i][0])).is_equal("p%d" % (i + 1))
	assert_str(CoopEvents.pair_of("helm", "helm")).is_empty()
	assert_str(CoopEvents.pair_of("helm", "captain")).is_empty()
	assert_array(CoopEvents.stations_of("p6")).is_equal(["weapons", "engineering"])


# FT: FT-PAIR-013, FT-PAIR-007
# A press of a share button counts once on the pair (D210): Science's weak points to Weapons
# (P7) and its diagnosed causes to Engineering (P10) on Easy, each press again; nothing on
# Normal where the weak points travel by voice, from a station that isn't the source, or
# from a joint view that holds both stations. The hack window reaches Weapons only while
# the share lasts.
func test_a_share_press_is_counted() -> void:
	var server: NetServer = h.server(false, 10.0, SECRET)
	var crew: Dictionary = await _crew(server)
	var science: NetClient = crew["science"]
	var weapons: NetSession = h.session_of(server, crew["weapons"])
	var coop: NetCoop = server.session.coop
	var shared: Callable = func(pair: String, n: int) -> bool:
		return coop.count_of(pair, CoopEvents.SHORTCUT_SHARED) == n
	# Before a press the toggle alone delivers nothing.
	var from: int = h.mark(crew["weapons"])
	server.world.emit(&"hack_done", PLAYER, ENEMY, 10.0, Vector3.ZERO, &"engines")
	server.session.after_ticks(server.world.drain_events())
	await h.wait(150)
	assert_array(h.events_of(crew["weapons"], "hack_done").slice(from)).is_empty()
	assert_dict(coop.counts()).is_empty()
	science.share("weak_points")
	assert_bool(await h.until(shared.bind("p7", 1))).is_true()
	(
		assert_bool(
			await h.until(func() -> bool: return weapons.shares.has(ViewFilter.WEAK_POINTS))
		)
		. is_true()
	)
	server.world.emit(&"hack_done", PLAYER, ENEMY, 10.0, Vector3.ZERO, &"engines")
	server.session.after_ticks(server.world.drain_events())
	var got: Dictionary = await h.next_event(crew["weapons"], "hack_done", from)
	assert_dict(got).is_not_empty()
	science.share("weak_points")
	assert_bool(await h.until(shared.bind("p7", 2))).is_true()
	science.share("diagnosed_causes")
	assert_bool(await h.until(shared.bind("p10", 1))).is_true()
	assert_bool(CoopEvents.COOPERATIVE.has(CoopEvents.SHORTCUT_SHARED)).is_true()
	# The share ends after share_seconds and the view loses the data again.
	_run(server, ceili(DataToggles.share_seconds() * SimWorld.HZ) + 2)
	server.session.shares.step()
	assert_bool(await h.until(func() -> bool: return weapons.shares.is_empty())).is_true()
	from = h.mark(crew["weapons"])
	server.world.emit(&"hack_done", PLAYER, ENEMY, 10.0, Vector3.ZERO, &"engines")
	server.session.after_ticks(server.world.drain_events())
	await h.wait(150)
	assert_array(h.events_of(crew["weapons"], "hack_done").slice(from)).is_empty()
	# Refused: not the source, a joint view that holds both, and the toggle off.
	var rejected: Callable = func(c: NetClient, from_at: int) -> String:
		var e: Dictionary = await h.next_event(
			c,
			NetProtocol.EVENT_REQUEST_REJECTED,
			from_at,
			func(ev: Dictionary) -> bool: return ev["payload"]["request"] == NetProtocol.Type.SHARE
		)
		return e.get("payload", {}).get("reason", "")
	from = h.mark(crew["weapons"])
	crew["weapons"].share("weak_points")
	assert_str(await rejected.call(crew["weapons"], from)).is_equal(NetShares.NOT_SOURCE)
	var targeting: NetClient = await h.joined(server, "targeting", "targeting")
	from = h.mark(targeting)
	targeting.share("weak_points")
	assert_str(await rejected.call(targeting, from)).is_equal(NetShares.SAME_SCREEN)
	server.session.toggles = DataToggles.of_preset("normal")
	from = h.mark(science)
	science.share("weak_points")
	assert_str(await rejected.call(science, from)).is_equal(NetShares.OFF)
	from = h.mark(science)
	science.share("chips")
	assert_str(await rejected.call(science, from)).is_equal(NetShares.BAD_FEATURE)
	assert_int(coop.count_of("p7", CoopEvents.SHORTCUT_SHARED)).is_equal(2)


# FT: FT-PAIR-013, FT-PAIR-007
# Relay's route reaches Helm only after Relay shares it (P4, counted per press), and is
# taken away again when the share ends; on Hard a press is refused and nothing arrives.
func test_a_route_shared_to_helm_is_counted() -> void:
	var server: NetServer = h.server(false, 10.0, SECRET)
	var crew: Dictionary = await _crew(server)
	var relay: NetClient = crew["relay"]
	var from: int = h.mark(crew["helm"])
	relay.route_add(0, 0, Vector3(0.0, 0.0, -1000.0))
	await h.until(
		func() -> bool: return not server.session.crew.relay.routes_of(PLAYER)[0].is_empty()
	)
	await h.wait(150)
	assert_array(h.events_of(crew["helm"], NetProtocol.EVENT_ROUTES).slice(from)).is_empty()
	assert_dict(server.session.coop.counts()).is_empty()
	relay.share("routes")
	var got: Dictionary = await h.next_event(
		crew["helm"],
		NetProtocol.EVENT_ROUTES,
		from,
		func(e: Dictionary) -> bool: return not e["payload"]["routes"][0].is_empty()
	)
	assert_dict(got).is_not_empty()
	assert_int(server.session.coop.count_of("p4", CoopEvents.SHORTCUT_SHARED)).is_equal(1)
	# The share ends: Helm's routes are emptied.
	from = h.mark(crew["helm"])
	_run(server, ceili(DataToggles.share_seconds() * SimWorld.HZ) + 2)
	var gone: Dictionary = await h.next_event(
		crew["helm"],
		NetProtocol.EVENT_ROUTES,
		from,
		func(e: Dictionary) -> bool: return e["payload"]["routes"].is_empty()
	)
	assert_dict(gone).is_not_empty()
	# Hard: no press is possible.
	server.session.toggles = DataToggles.of_preset("hard")
	from = h.mark(crew["helm"])
	relay.share("routes")
	await h.wait(200)
	assert_array(h.events_of(crew["helm"], NetProtocol.EVENT_ROUTES).slice(from)).is_empty()
	assert_int(server.session.coop.count_of("p4", CoopEvents.SHORTCUT_SHARED)).is_equal(1)


# FT: FT-PAIR-013
# A mark one station placed and another pinged is a use, counted on their pair once per
# 10 s; the placer pinging its own mark, or a copy of it, counts nothing.
func test_a_mark_used_by_another_station_is_counted() -> void:
	var server: NetServer = h.server(false, 10.0, SECRET)
	var crew: Dictionary = await _crew(server)
	var from: int = h.mark(crew["weapons"])
	crew["relay"].place_mark(-1, "Rock", -1, 0, Vector3(10.0, 0.0, 0.0))
	await h.next_event(crew["weapons"], NetProtocol.EVENT_MARKS, from)
	crew["relay"].ping("mark", 0, 0, Vector3.ZERO)
	await h.wait(150)
	assert_dict(server.session.coop.counts()).is_empty()
	crew["weapons"].ping("mark", 0, 0, Vector3.ZERO)
	(
		assert_bool(
			await h.until(
				func() -> bool: return server.session.coop.count_of("p8", CoopEvents.MARK_USED) == 1
			)
		)
		. is_true()
	)
	crew["weapons"].ping("mark", 0, 0, Vector3.ZERO)
	await h.wait(150)
	assert_int(server.session.coop.count_of("p8", CoopEvents.MARK_USED)).is_equal(1)
	# Another station using it counts on its own pair.
	crew["helm"].ping("mark", 0, 0, Vector3.ZERO)
	(
		assert_bool(
			await h.until(
				func() -> bool: return server.session.coop.count_of("p4", CoopEvents.MARK_USED) == 1
			)
		)
		. is_true()
	)


# FT: FT-PAIR-013, FT-SCI-009
# The scan-position mark Science made is used by Helm when the ship reaches it (P3); counted
# once per mark.
func test_reaching_the_scan_position_is_counted() -> void:
	var server: NetServer = h.server(false, 10.0, SECRET)
	var crew: Dictionary = await _crew(server)
	# No await from here on: the launched sim would run in real time.
	server.session.launch(PLAYER)
	(
		assert_str(
			server.session.crew.add_scan_position(
				PLAYER, 0, Vector3(4000.0, 0.0, 0.0), 500.0, NetCrewState.SCIENCE_BY
			)
		)
		. is_empty()
	)
	_run(server, 60)
	assert_int(server.session.coop.count_of("p3", CoopEvents.MARK_USED)).is_equal(0)
	server.session.crew.relay.delete_zone(
		PLAYER, server.session.crew.relay.zones_of(PLAYER)[0]["id"]
	)
	(
		assert_str(
			server.session.crew.add_scan_position(
				PLAYER, 0, Vector3(100.0, 0.0, 0.0), 500.0, NetCrewState.SCIENCE_BY
			)
		)
		. is_empty()
	)
	_run(server, 60)
	assert_int(server.session.coop.count_of("p3", CoopEvents.MARK_USED)).is_equal(1)
	_run(server, 120)
	assert_int(server.session.coop.count_of("p3", CoopEvents.MARK_USED)).is_equal(1)
	assert_object(crew).is_not_null()


# FT: FT-PAIR-013, FT-PAIR-014, FT-SCI-009
# A scan that a probe's bubble made possible counts on P13 when it finishes, at every
# difficulty; one outside any bubble counts nothing.
func test_a_probe_enabled_scan_is_counted() -> void:
	for code: String in ["easy", "hard"]:
		var server: NetServer = h.server(false, 10.0, SECRET)
		var host: NetClient = await h.welcomed(server, "host", "", SECRET)
		host.set_toggles(code)
		(
			assert_bool(
				await h.until(func() -> bool: return server.session.toggles.encode() == code)
			)
			. is_true()
		)
		var world: SimWorld = server.world
		KnowledgeSystem.step(world)
		var scan: ScienceScanCommand = ScienceScanCommand.new()
		scan.contact = ENEMY
		_do(server, scan)
		_do(server, ScienceFixture.submit_cmd(ScienceFixture.solution(world)))
		assert_int(server.session.coop.count_of("p13", CoopEvents.PROBE_SCAN)).is_equal(0)
		ScienceFixture.cover(world, ENEMY)
		var again: ScienceScanCommand = ScienceScanCommand.new()
		again.contact = ENEMY
		_do(server, again)
		_do(server, ScienceFixture.submit_cmd(ScienceFixture.solution(world)))
		(
			assert_int(server.session.coop.count_of("p13", CoopEvents.PROBE_SCAN))
			. override_failure_message(code)
			. is_equal(1)
		)
		assert_int(server.session.coop.cooperative("p13")).is_equal(1)
