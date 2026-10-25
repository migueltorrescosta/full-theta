extends GdUnitTestSuite
## L3 tests of the lobby's data-shortcut toggles over loopback (Toggles message, ServerSession):
## only the host sets them, they lock at Start, every view follows, and difficulty never
## changes the sim's hidden stats.

const PLAYER: int = NetHarness.PLAYER
const ENEMY: int = NetHarness.ENEMY
const SECRET: String = "s3cret"

var h: NetHarness


func before_test() -> void:
	h = NetHarness.new(self)


func after_test() -> void:
	await h.free_all()


func _rejected(c: NetClient, from: int) -> String:
	var e: Dictionary = await h.next_event(
		c,
		NetProtocol.EVENT_REQUEST_REJECTED,
		from,
		func(ev: Dictionary) -> bool: return ev["payload"]["request"] == NetProtocol.Type.TOGGLES
	)
	return e.get("payload", {}).get("reason", "")


func _view_follows(server: NetServer, c: NetClient, code: String) -> bool:
	return await h.until(func() -> bool: return h.session_of(server, c).toggles == code)


func _has_status(c: NetClient) -> bool:
	return c.view.blocks.has(StationViews.Section.STATUS)


func _has_shields(c: NetClient) -> bool:
	return c.view.blocks.get(StationViews.Section.STATUS, {}).get("shields", 0.0) > 0.0


func _lobby_code(c: NetClient) -> String:
	return str(h.last_event(c, NetProtocol.EVENT_LOBBY).get("payload", {}).get("toggles", ""))


# FT: FT-PAIR-017, FT-STN-016
# A first launch is Easy; only the host changes the toggles, a malformed set is refused, and
# the lobby event tells every client the code.
func test_only_the_host_sets_the_toggles() -> void:
	var server: NetServer = h.server(false, 10.0, SECRET)
	var host: NetClient = await h.welcomed(server, "host", "", SECRET)
	var guest: NetClient = await h.welcomed(server, "guest")
	assert_bool(await h.until(func() -> bool: return _lobby_code(guest) == "easy")).is_true()
	assert_str(server.session.toggles.encode()).is_equal("easy")
	var from: int = h.mark(guest)
	guest.set_toggles("hard")
	assert_str(await _rejected(guest, from)).is_equal(ServerSession.NOT_HOST)
	from = h.mark(host)
	host.set_toggles("extreme")
	assert_str(await _rejected(host, from)).is_equal(ServerSession.BAD_TOGGLES)
	assert_str(server.session.toggles.encode()).is_equal("easy")
	var custom: String = DataToggles.of_preset("normal").with_value(&"routes", 0).encode()
	host.set_toggles(custom)
	assert_bool(await h.until(func() -> bool: return _lobby_code(guest) == custom)).is_true()
	assert_bool(await h.until(func() -> bool: return _lobby_code(host) == custom)).is_true()
	assert_bool(DataToggles.parse(custom).is_custom()).is_true()
	# A session that joins later gets the set at once.
	var late: NetClient = await h.welcomed(server, "late")
	assert_bool(await h.until(func() -> bool: return _lobby_code(late) == custom)).is_true()
	assert_str(h.session_of(server, late).toggles).is_equal(custom)


# FT: FT-PAIR-017
# The set applies to every ship and locks once a run starts; every pick's snapshot view
# follows a change with a full snapshot filtered by the new set.
func test_toggles_lock_at_start_and_every_view_follows() -> void:
	var server: NetServer = h.server(false, 10.0, SECRET)
	var host: NetClient = await h.welcomed(server, "host", "", SECRET)
	await h.pick(host, "captain")
	var crew: Array[NetClient] = await h.crew3(server)
	var helm: NetClient = crew[0]
	var fulls: int = helm.view.full_count
	host.set_toggles("hard")
	assert_bool(await _view_follows(server, helm, "hard")).is_true()
	var key: String = h.session_of(server, helm).view_key()
	assert_str(key).is_equal(StationViews.key(PLAYER, "tactical", "hard"))
	assert_bool(await h.until(func() -> bool: return helm.view.full_count > fulls)).is_true()
	# Hard: the Helm half of Tactical sees no shields in its top bar.
	assert_bool(await h.until(_has_status.bind(helm))).is_true()
	assert_float(helm.view.blocks[StationViews.Section.STATUS]["shields"]).is_equal(0.0)
	host.set_toggles("easy")
	assert_bool(await _view_follows(server, helm, "easy")).is_true()
	assert_bool(await h.until(_has_shields.bind(helm))).is_true()
	assert_bool(await h.start(server, helm)).is_true()
	var from: int = h.mark(host)
	host.set_toggles("hard")
	assert_str(await _rejected(host, from)).is_equal(ServerSession.TOGGLES_LOCKED)
	assert_str(server.session.toggles.encode()).is_equal("easy")


# FT: FT-MIS-008
# Difficulty never changes hidden stats: the same ship and enemy definitions, and the same
# sim state after the same commands, whatever the toggle set. (The sim never reads a
# toggle; only what a snapshot says differs.)
func test_difficulty_never_changes_hidden_stats() -> void:
	var hashes: Dictionary = {}
	var defs: Dictionary = {}
	for code: String in ["easy", "normal", "hard", "easy:20000000000", "hard:01111111111"]:
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
		var thrust: HelmInputCommand = HelmInputCommand.new()
		thrust.ship_id = PLAYER
		thrust.throttle = 1.0
		thrust.rotation = Vector3(0.1, 0.2, 0.0)
		world.submit(thrust)
		for i: int in 600:
			world.step()
			if i % 60 == 59:
				server.session.after_ticks(world.drain_events())
		hashes[code] = world.state_hash()
		defs[code] = [
			TestDefs.def_hash(world.defs[PLAYER]),
			TestDefs.def_hash(world.defs[ENEMY]),
		]
	for code: String in hashes:
		assert_str(hashes[code]).override_failure_message(code).is_equal(hashes["easy"])
		assert_array(defs[code]).is_equal(defs["easy"])


# FT: FT-ENG-006, FT-PAIR-014, FT-PAIR-020
# Science's own-ship scan names an unknown fault's cause at every difficulty; with the
# diagnosed-cause toggle on (Easy) and Science's share the server also pre-fills Engineering's
# pick, through a logged command, so the repair needs no pick from Engineering (D210): a
# share before the scan pre-fills at the reveal, one after it at the press, and the toggle
# alone or a share with the toggle off pre-fills nothing.
func test_easy_prefills_the_diagnosed_cause() -> void:
	var picks: Dictionary = {}
	var known: Dictionary = {}
	for variant: String in ["easy early", "easy late", "easy never", "normal early", "hard early"]:
		var code: String = variant.split(" ")[0]
		var when: String = variant.split(" ")[1]
		var server: NetServer = h.server(false, 10.0, SECRET)
		var host: NetClient = await h.welcomed(server, "host", "", SECRET)
		var science: NetClient = await h.joined(server, "sci", "science")
		host.set_toggles(code)
		(
			assert_bool(
				await h.until(func() -> bool: return server.session.toggles.encode() == code)
			)
			. is_true()
		)
		var share: Callable = func() -> void:
			var from: int = h.mark(science)
			science.share("diagnosed_causes")
			var opened: Callable = func() -> bool:
				return (
					server.session.shares.active(PLAYER, ViewFilter.DIAGNOSED_CAUSES)
					or not (
						h
						. events_of(science, NetProtocol.EVENT_REQUEST_REJECTED)
						. slice(from)
						. is_empty()
					)
				)
			await h.until(opened)
		if when == "early":
			await share.call()
		var world: SimWorld = server.world
		var def: ShipDef = TestDefs.corvette().duplicate()
		var subs: Array[SubsystemDef] = []
		for s: SubsystemDef in def.subsystems:
			var copy: SubsystemDef = s.duplicate()
			if copy.id == &"engines":
				copy.fault_causes = [&"coolant_leak", &"short", &"software"]
			subs.append(copy)
		def.subsystems = subs
		world.defs[PLAYER] = def
		assert_bool(DamageSystem.inflict_fault(world, PLAYER, &"engines", &"short", 1e6)).is_true()
		var scan: ScienceSelfScanCommand = ScienceSelfScanCommand.new()
		scan.ship_id = PLAYER
		world.submit(scan)
		for i: int in int(world.science_def.self_scan_s * 60.0) + 4:
			world.step()
			server.session.after_ticks(world.drain_events())
		world.step()
		if when == "late":
			await share.call()
			world.step()
		var r: int = world.damage.find_subsystem(PLAYER, &"engines")
		known[variant] = DamageSystem.known_fault_cause(world, PLAYER, &"engines")
		picks[variant] = world.damage.fault_pick[r]
	for variant: String in known:
		assert_str(known[variant]).override_failure_message(variant).is_equal("short")
	assert_str(picks["easy early"]).is_equal("short")
	assert_str(picks["easy late"]).is_equal("short")
	assert_str(picks["easy never"]).is_equal("")
	assert_str(picks["normal early"]).is_equal("")
	assert_str(picks["hard early"]).is_equal("")


# FT: FT-SPA-019, FT-SPA-029, FT-PAIR-008
# On Hard the only things that still cross between stations are MARK items other than routes
# and approach lanes, and pings: a mark, a ping and a hazard zone reach every station of the
# ship, Relay's route reaches Relay alone.
func test_marks_and_pings_survive_hard_and_routes_do_not() -> void:
	var server: NetServer = h.server(false, 10.0, SECRET)
	var host: NetClient = await h.welcomed(server, "host", "", SECRET)
	var crew: Dictionary = {}
	for station: String in ["helm", "weapons", "engineering", "science", "relay", "comms"]:
		crew[station] = await h.joined(server, station, station)
	host.set_toggles("hard")
	for station: String in crew:
		assert_bool(await _view_follows(server, crew[station], "hard")).is_true()
	var from: Dictionary = {}
	for station: String in crew:
		from[station] = h.mark(crew[station])
	crew["helm"].place_mark(-1, "Rock", -1, 0, Vector3(5.0, 0.0, 0.0))
	crew["science"].ping("site", -1, 0, Vector3.ZERO)
	crew["relay"].hazard_add(1000.0, 0, Vector3(0.0, 0.0, -2000.0))
	crew["relay"].route_add(0, 0, Vector3(0.0, 0.0, -1000.0))
	for station: String in crew:
		var c: NetClient = crew[station]
		var marks: Dictionary = await h.next_event(c, NetProtocol.EVENT_MARKS, from[station])
		assert_str(marks["payload"]["marks"][0]["name"]).override_failure_message(station).is_equal(
			"Rock"
		)
		var ping: Dictionary = await h.next_event(c, NetProtocol.EVENT_PING, from[station])
		assert_str(ping["payload"]["kind"]).is_equal("site")
		var zones: Dictionary = await h.next_event(
			c,
			NetProtocol.EVENT_ZONES,
			from[station],
			func(e: Dictionary) -> bool: return not e["payload"]["zones"].is_empty()
		)
		assert_str(zones["payload"]["zones"][0]["kind"]).is_equal("hazard")
	var routes: Dictionary = await h.next_event(
		crew["relay"], NetProtocol.EVENT_ROUTES, from["relay"]
	)
	assert_dict(routes).is_not_empty()
	await h.wait(200)
	for station: String in ["helm", "weapons", "engineering", "science", "comms"]:
		var seen: Array = h.events_of(crew[station], NetProtocol.EVENT_ROUTES).slice(from[station])
		assert_array(seen).override_failure_message(station).is_empty()
