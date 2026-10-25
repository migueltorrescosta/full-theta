extends GdUnitTestSuite
## L3 Science tests (E01): the SCIENCE section, the scan and hack over the wire with the
## server verifying every solution, the one-at-a-time claim of the active scan or hack
## (FT-NET-022), and the hack window a spoken relay can use (FT-PAIR-023).

const PLAYER: int = NetHarness.PLAYER
const ENEMY: int = NetHarness.ENEMY
const S = StationViews.Section

var h: NetHarness


func before_test() -> void:
	h = NetHarness.new(self)


func after_test() -> void:
	await h.free_all()


## Sends a command; returns the CommandRejected reason, or "" once the sim applied it.
func _verdict(server: NetServer, c: NetClient, cmd: Dictionary) -> String:
	var from: int = h.mark(c)
	var seq: int = c.command(cmd)
	var tick: int = server.world.tick
	var reason: Array[String] = []
	var done: Callable = func() -> bool:
		for e: Dictionary in h.events[c].slice(from):
			if e["type"] == NetProtocol.EVENT_COMMAND_REJECTED and e["payload"]["seq"] == seq:
				reason.append(e["payload"]["reason"])
				return true
		return server.world.tick > tick + 6 and server.session._pending.is_empty()
	await h.until(done)
	await h.wait(100)
	done.call()
	return reason[0] if not reason.is_empty() else ""


func _block(c: NetClient) -> Dictionary:
	return c.view.blocks.get(S.SCIENCE, {})


## The enemy's card in the client's SCIENCE section, or {}.
func _card(c: NetClient) -> Dictionary:
	for card: Dictionary in _block(c).get("cards", []):
		if card["contact"] == ENEMY:
			return card
	return {}


## Whether the enemy's card shows a good scan with its class revealed.
func _scanned(c: NetClient) -> bool:
	var card: Dictionary = _card(c)
	return card.get("scan", 0.0) > 0.8 and card.get("class_id", 0) != 0


## Seconds left of the faction's hack window on the enemy in the client's section.
func _window_left(c: NetClient) -> float:
	var rows: Array = _block(c).get("hacks", [])
	return rows[0]["left"] if rows.size() == 1 and rows[0]["target"] == ENEMY else 0.0


# FT: FT-NET-022, FT-NET-023, FT-SCI-004
# The active scan is one claimable item: the claimer opens a scan, the other Science
# player is refused with `claimed` until the claim moves; Helm has no Science commands.
func test_the_scan_is_claimed_one_at_a_time() -> void:
	var server: NetServer = h.server(false, 10.0)
	var ana: NetClient = await h.joined(server, "ana", "science")
	var bo: NetClient = await h.joined(server, "bo", "survey")
	server.session.launch(PLAYER)
	var scan: Dictionary = {"kind": "science_scan", "contact": ENEMY}
	# Ana was alone on Science first and holds the scan; Bo sees her name.
	(
		assert_bool(
			await h.until(func() -> bool: return bo.view.claimer(StationViews.CLAIM_SCAN) == "ana")
		)
		. is_true()
	)
	assert_str(await _verdict(server, bo, scan)).is_equal(CommandGate.CLAIMED)
	assert_str(await _verdict(server, ana, scan)).is_equal("")
	assert_bool(await h.until(func() -> bool: return _block(ana).get("session", 0) == 1)).is_true()
	# Bo can still use the free controls of the station (mode, ping, select).
	assert_str(await _verdict(server, bo, {"kind": "science_ping"})).is_equal("")
	# Release and claim: now Bo may open a scan, but the one in flight is Ana's: busy.
	ana.release_claim(StationViews.CLAIM_SCAN)
	(
		assert_bool(
			await h.until(func() -> bool: return bo.view.claimer(StationViews.CLAIM_SCAN) == "")
		)
		. is_true()
	)
	bo.claim(StationViews.CLAIM_SCAN)
	(
		assert_bool(
			await h.until(func() -> bool: return bo.view.claimer(StationViews.CLAIM_SCAN) == "bo")
		)
		. is_true()
	)
	assert_str(await _verdict(server, ana, {"kind": "science_cancel"})).is_equal(
		CommandGate.CLAIMED
	)
	assert_str(await _verdict(server, bo, {"kind": "science_cancel"})).is_equal("")
	assert_int(server.world.science.kind[PLAYER]).is_equal(ScienceTable.Session.NONE)


# FT: FT-NET-006
# A Helm-only client cannot send Science commands.
func test_helm_cannot_send_science_commands() -> void:
	var server: NetServer = h.server(false, 10.0)
	var helm: NetClient = await h.joined(server, "hal", "helm")
	server.session.launch(PLAYER)
	assert_str(await _verdict(server, helm, {"kind": "science_ping"})).is_equal(
		CommandGate.NOT_YOUR_STATION
	)


# FT: FT-SCI-011, FT-SCI-004, FT-SCI-016, FT-SCI-001, FT-SCI-002
# A scan over the wire: the section carries the puzzle (wireframe, cloud, axes) but not
# the pose; wrong angles score low on the server, exact ones lock; the contact card then
# shows the scan confidence.
func test_scan_is_generated_and_verified_on_the_server() -> void:
	var server: NetServer = h.server(false, 10.0)
	var sci: NetClient = await h.joined(server, "ana", "science")
	server.session.launch(PLAYER)
	assert_bool(await h.until(func() -> bool: return _card(sci).get("detect", 0.0) > 0.0)).is_true()
	assert_str(await _verdict(server, sci, {"kind": "science_scan", "contact": ENEMY})).is_equal("")
	assert_bool(await h.until(func() -> bool: return _block(sci).get("session", 0) == 1)).is_true()
	var block: Dictionary = _block(sci)
	assert_int((block["wire"] as Array).size()).is_equal(server.world.science_def.wire_vertices)
	assert_int((block["cloud"] as Array).size()).is_greater_equal((block["wire"] as Array).size())
	assert_int(block["axes"]).is_equal(server.world.science.axes[PLAYER])
	var from: int = h.mark(sci)
	sci.command({"kind": "science_scan_submit", "ax": 0.0, "ay": 0.0, "az": 0.0})
	var bad: Dictionary = await h.next_event(sci, "scan_done", from)
	assert_float(bad["payload"]["value"]).is_less(0.85)
	assert_str(await _verdict(server, sci, {"kind": "science_scan", "contact": ENEMY})).is_equal("")
	var truth: Vector3 = ScanPuzzle.target_angles(
		server.world.science_def,
		server.world.science.puzzle_seed[PLAYER],
		server.world.science.axes[PLAYER]
	)
	from = h.mark(sci)
	sci.command({"kind": "science_scan_submit", "ax": truth.x, "ay": truth.y, "az": truth.z})
	var good: Dictionary = await h.next_event(sci, "scan_done", from)
	assert_str(good["payload"]["tag"]).is_equal("locked")
	assert_float(good["payload"]["value"]).is_greater(0.8)
	assert_bool(await h.until(func() -> bool: return _scanned(sci))).is_true()
	assert_int(_block(sci)["session"]).is_equal(0)


# FT: FT-SCI-006, FT-SCI-008, FT-PAIR-023
# A hack over the wire: the route is walked move by move (the server refuses a
# non-adjacent node), and the window it opens shows in the faction's hacks with at least
# 8 s left.
func test_hack_window_reaches_the_snapshot() -> void:
	var server: NetServer = h.server(false, 10.0)
	var sci: NetClient = await h.joined(server, "ana", "science")
	var wpn: NetClient = await h.joined(server, "wes", "weapons")
	server.session.launch(PLAYER)
	var w: SimWorld = server.world
	# Fixture: the crew has already scanned the raider.
	await h.until(func() -> bool: return w.knowledge.row_for(1, ENEMY) >= 0)
	ScienceKnowledge.record(w, 1, ENEMY, 1.0)
	(
		assert_str(
			await _verdict(
				server, sci, {"kind": "science_hack", "contact": ENEMY, "subsystem_id": "weapons"}
			)
		)
		. is_equal("")
	)
	assert_bool(await h.until(func() -> bool: return _block(sci).get("session", 0) == 2)).is_true()
	var block: Dictionary = _block(sci)
	assert_int(block["hack_cols"]).is_equal(w.science_def.hack_cols)
	assert_int((block["edges"] as Array).size()).is_equal(block["hack_cols"] * block["hack_rows"])
	assert_str(await _verdict(server, sci, {"kind": "science_hack_move", "node": 14})).is_equal(
		CommandGate.SIM_REJECTED
	)
	var route: Array[int] = ScienceFixture.route(w, PLAYER)
	var from: int = h.mark(sci)
	for node: int in route:
		sci.command({"kind": "science_hack_move", "node": node})
		await h.wait(60)
	var done: Dictionary = await h.next_event(sci, "hack_done", from)
	assert_float(done["payload"]["value"]).is_greater_equal(8.0)
	assert_str(done["payload"]["tag"]).is_equal("weapons")
	assert_bool(await h.until(func() -> bool: return _window_left(sci) > 6.0)).is_true()
	# Weapons gets the window too (P7): the hack events reach its station.
	await h.next_event(wpn, "hack_done")
