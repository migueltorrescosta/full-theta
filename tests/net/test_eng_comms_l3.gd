extends GdUnitTestSuite
## Engineering and Comms between different players (FT-PAIR-010, FT-PAIR-019, FT-PAIR-011,
## D68, P12): over loopback at each preset there is no data link between them. Comms' board
## carries no Engineering field and its only view of condition is the hull band; only Comms
## trades, and what it buys lands in Engineering's spares; a Quartermaster, who holds both
## stations, sees both by design (D76).

const PLAYER: int = CommsL3.PLAYER
const S = StationViews.Section

var h: NetHarness


func before_test() -> void:
	h = NetHarness.new(self)


func after_test() -> void:
	await h.free_all()


## Puts every client's session on a preset and waits for the new full views.
func _preset(server: NetServer, clients: Array[NetClient], code: String) -> void:
	var fulls: Dictionary = {}
	for c: NetClient in clients:
		fulls[c] = c.view.full_count
		var s: NetSession = h.session_of(server, c)
		s.toggles = code
		server.transport.set_view(s.id, s.view_key())
	var all_new: Callable = func() -> bool:
		return clients.all(func(c: NetClient) -> bool: return c.view.full_count > fulls[c])
	assert_bool(await h.until(all_new)).is_true()


func _spares(c: NetClient) -> int:
	return c.view.blocks.get(S.ENGINEERING, {}).get("spare_parts", -1)


func _run(code: String) -> void:
	var server: NetServer = h.server()
	CommsL3.offer(server)
	var eng: NetClient = await h.joined(server, "eng", "engineering")
	var comms: NetClient = await h.joined(server, "comms", "comms")
	var qm: NetClient = await h.joined(server, "qm", "quartermaster")
	server.session.launch(PLAYER)
	var all: Array[NetClient] = [eng, comms, qm]
	await _preset(server, all, code)
	assert_bool(await h.until(func() -> bool: return CommsL3.block(comms).has("credits"))).is_true()
	var max_hull: float = server.world.defs[PLAYER].hull_max
	# Comms: the board holds exactly its own fields, no Engineering data, the hull as a band.
	var fields: Array = StationViews.BLOCKS[S.COMMS].map(func(f: Array) -> String: return f[0])
	assert_array(CommsL3.block(comms).keys()).is_equal(fields)
	assert_array(comms.view.kinds).not_contains([S.ENGINEERING, S.RELAY, S.MOUNTS, S.HELM])
	assert_int(CommsL3.block(comms)["hull_band"]).is_equal(HealthBand.Band.OK)
	assert_float(comms.view.blocks[S.STATUS]["hull"]).is_equal_approx(
		0.875 * max_hull, max_hull * 0.001
	)
	assert_float(comms.view.blocks[S.STATUS]["shields"]).is_equal(0.0)
	assert_int(comms.view.blocks[S.STATUS]["pips_used"]).is_equal(0)
	assert_bool(CommsL3.block(comms)["docked"]).is_true()
	assert_int(CommsL3.block(comms)["credits"]).is_equal(1000)
	# Engineering has its exact data and no board; the Quartermaster has both.
	assert_array(eng.view.kinds).not_contains([S.COMMS])
	assert_int(_spares(eng)).is_equal(20)
	assert_float(eng.view.blocks[S.STATUS]["hull"]).is_equal_approx(max_hull, max_hull * 0.001)
	assert_array(qm.view.kinds).contains([S.COMMS, S.ENGINEERING])
	assert_int(_spares(qm)).is_equal(20)
	assert_float(qm.view.blocks[S.STATUS]["hull"]).is_equal_approx(max_hull, max_hull * 0.001)
	assert_bool(CommsL3.block(qm).has("credits")).is_true()
	# Only Comms trades (FT-PAIR-011): Engineering is refused, Comms buys five parts.
	var buy: Dictionary = {"kind": "comms_trade", "card": 0, "item": "parts", "qty": 5, "buy": true}
	assert_str(await CommsL3.verdict(h, server, eng, buy)).is_equal(CommandGate.NOT_YOUR_STATION)
	assert_int(server.world.economy.credits[PLAYER]).is_equal(1000)
	assert_str(await CommsL3.verdict(h, server, comms, buy)).is_equal("")
	assert_int(server.world.economy.credits[PLAYER]).is_equal(1000 - 125)
	# P12: the parts are in Engineering's spares (and the Quartermaster's), and Comms' credits drop.
	(
		assert_bool(await h.until(func() -> bool: return _spares(eng) == 25 and _spares(qm) == 25))
		. is_true()
	)
	(
		assert_bool(
			await h.until(func() -> bool: return CommsL3.block(comms)["credits"] == 1000 - 125)
		)
		. is_true()
	)
	assert_array(CommsL3.block(comms).keys()).is_equal(fields)
	# The Quartermaster trades as Comms does.
	assert_str(await CommsL3.verdict(h, server, qm, buy)).is_equal("")
	assert_int(server.world.economy.credits[PLAYER]).is_equal(1000 - 250)


# FT: FT-PAIR-010, FT-PAIR-019, FT-PAIR-011
func test_eng_comms_on_easy() -> void:
	await _run("easy")


# FT: FT-PAIR-010, FT-PAIR-019, FT-PAIR-011
func test_eng_comms_on_normal() -> void:
	await _run("normal")


# FT: FT-PAIR-010, FT-PAIR-019, FT-PAIR-011
func test_eng_comms_on_hard() -> void:
	await _run("hard")
