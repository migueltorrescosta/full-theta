extends GdUnitTestSuite
## L3 claims and ownership tests (T044): claimable items, the claimer-only rule, names
## in snapshots, implicit claims of a player alone on a station, ship-wide controls
## with their last writer, and the three ways a claim is released.

const PLAYER: int = NetHarness.PLAYER

var h: NetHarness


func before_test() -> void:
	h = NetHarness.new(self)


func after_test() -> void:
	await h.free_all()


## Waits until a client's OWNERSHIP view names `who` (a client, or null for free) as
## the holder of an item.
func _holds(server: NetServer, viewer: NetClient, item: String, who: NetClient) -> bool:
	var want: int = h.session_of(server, who).id if who != null else -1
	return await h.until(
		func() -> bool:
			var claims: Dictionary = viewer.view.ownership.get("claims", {})
			return (claims[item][0] if claims.has(item) else -1) == want
	)


## Sends a command and returns the CommandRejected reason for it, or "" once the sim
## has applied it (a few ticks later) without one.
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


# FT: FT-NET-022, FT-NET-023, FT-NET-045
# Two Weapons players: the claimer of a mount fires and aims, the other is refused
# with CommandRejected{claimed}; two Helm players: with Helm flight claimed, the other
# can't fly, Align or face, and with shield facing claimed the other can't set it.
# Each claimer's name shows in the snapshots of the others at that station. Claims
# apply in the lobby already, before Start.
func test_only_the_claimer_commands_a_claimed_item() -> void:
	var server: NetServer = h.server(false, 10.0)
	var w1: NetClient = await h.joined(server, "ana", "weapons")
	var w2: NetClient = await h.joined(server, "bo", "tactical")
	var h2: NetClient = await h.joined(server, "cy", "helm")
	# Ana was alone on Weapons first, so she holds the mount; Bo sees her name.
	assert_bool(await _holds(server, w2, "mount:0", w1)).is_true()
	assert_str(w2.view.claimer("mount:0")).is_equal("ana")
	# Claims hold in the lobby too, before Start: the gate refuses at once.
	var aim: Dictionary = {"kind": "aim_mount", "mount_index": 0, "aim_z": -100.0}
	assert_str(await _verdict(server, w2, {"kind": "fire", "mount_index": 0})).is_equal(
		CommandGate.CLAIMED
	)
	assert_str(await _verdict(server, w2, aim)).is_equal(CommandGate.CLAIMED)
	assert_bool(server.session.launched.is_empty()).is_true()
	server.session.launch(PLAYER)
	assert_str(await _verdict(server, w1, aim)).is_equal("")
	# Bo (Tactical) held Helm alone until Cy joined: he keeps flight and shield facing.
	assert_bool(await _holds(server, h2, "flight", w2)).is_true()
	assert_str(await _verdict(server, h2, {"kind": "helm_input", "throttle": 1.0})).is_equal(
		CommandGate.CLAIMED
	)
	assert_str(await _verdict(server, h2, {"kind": "helm_align"})).is_equal(CommandGate.CLAIMED)
	assert_str(await _verdict(server, h2, {"kind": "helm_input", "face": true})).is_equal(
		CommandGate.CLAIMED
	)
	var focus: Dictionary = {"kind": "set_shield_focus", "direction": Vector3.BACK}
	assert_str(await _verdict(server, h2, focus)).is_equal(CommandGate.CLAIMED)
	assert_str(await _verdict(server, w2, {"kind": "helm_input", "throttle": 0.5})).is_equal("")
	# Bo releases shield facing, Cy claims it: now Cy sets it and Bo can't.
	w2.release_claim("shield_facing")
	assert_bool(await _holds(server, h2, "shield_facing", null)).is_true()
	h2.claim("shield_facing")
	assert_bool(await _holds(server, w2, "shield_facing", h2)).is_true()
	assert_str(w2.view.ownership["claims"]["shield_facing"][1]).is_equal("cy")
	assert_str(await _verdict(server, h2, focus)).is_equal("")
	assert_str(await _verdict(server, w2, focus)).is_equal(CommandGate.CLAIMED)
	# A claim held by another is refused; an item of another station too.
	var from: int = h.mark(h2)
	h2.claim("flight")
	var refused: Dictionary = await h.next_event(h2, ServerSession.EVENT_REQUEST_REJECTED, from)
	assert_str(refused["payload"]["reason"]).is_equal(CommandGate.CLAIMED)
	from = h.mark(h2)
	h2.claim("mount:0")
	refused = await h.next_event(h2, ServerSession.EVENT_REQUEST_REJECTED, from)
	assert_str(refused["payload"]["reason"]).is_equal(CommandGate.NOT_YOUR_STATION)


# FT: FT-NET-044
# A player alone on Engineering holds both repair crews; unclaimable controls (power
# pips, shield power) are ship-wide: either Engineering player sets them, the last
# writer wins and its name is in the snapshots of every Engineering player.
func test_alone_holds_all_and_ship_wide_controls_name_last_writer() -> void:
	var server: NetServer = h.server()
	var e1: NetClient = await h.joined(server, "dee", "engineering")
	assert_bool(await _holds(server, e1, "crew:0", e1)).is_true()
	assert_bool(await _holds(server, e1, "crew:1", e1)).is_true()
	var e2: NetClient = await h.joined(server, "eve", "systems")
	var helm: NetClient = await h.joined(server, "fay", "helm")
	server.session.launch(PLAYER)
	assert_str(e2.view.claimer("crew:1")).is_equal("dee")
	assert_bool(await _holds(server, e2, "crew:0", e1)).is_true()
	var pips: String = "pips:%d" % SubsystemDef.Kind.ENGINES
	var writer_is: Callable = func(c: NetClient, writer: String) -> bool:
		var w: Dictionary = c.view.ownership.get("writers", {})
		return w.has(pips) and w[pips][1] == writer
	(
		assert_str(await _verdict(server, e2, {"kind": "set_pips", "subsystem_kind": 4, "pips": 2}))
		. is_equal("")
	)
	e1.set_pips(SubsystemDef.Kind.ENGINES, 2)
	assert_bool(await h.until(func() -> bool: return writer_is.call(e2, "dee"))).is_true()
	assert_bool(writer_is.call(e1, "dee")).is_true()
	e2.set_pips(SubsystemDef.Kind.ENGINES, 3)
	assert_bool(await h.until(func() -> bool: return writer_is.call(e1, "eve"))).is_true()
	assert_str(e1.view.last_writer(pips)).is_equal("eve")
	e1.command({"kind": "set_shield", "power": 2})
	var shield_by: Callable = func() -> bool:
		var w: Dictionary = e2.view.ownership.get("writers", {})
		return w.has("shield") and w["shield"][1] == "dee"
	assert_bool(await h.until(shield_by)).is_true()
	# Helm sees no Engineering writers or claims.
	assert_bool(helm.view.ownership["writers"].has(pips)).is_false()
	assert_bool(helm.view.ownership["claims"].has("crew:0")).is_false()


# FT: FT-NET-024
# A claim is released explicitly, on a station change and when the claimer's grace
# ends; while the grace runs it stays held.
func test_claims_release_on_release_station_change_and_grace() -> void:
	var server: NetServer = h.server(false, 1.0)
	var a: NetClient = await h.joined(server, "a", "engineering")
	var b: NetClient = await h.joined(server, "b", "engineering")
	var c: NetClient = await h.joined(server, "c", "systems")
	# a was alone first: it holds both crews.
	assert_bool(await _holds(server, c, "crew:0", a)).is_true()
	a.release_claim("crew:0")
	assert_bool(await _holds(server, c, "crew:0", null)).is_true()
	b.claim("crew:0")
	assert_bool(await _holds(server, c, "crew:0", b)).is_true()
	# Station change: a moves to Helm and lets crew 1 go.
	assert_bool(await h.pick(a, "helm")).is_true()
	assert_bool(await _holds(server, c, "crew:1", null)).is_true()
	c.claim("crew:1")
	assert_bool(await _holds(server, b, "crew:1", c)).is_true()
	# Grace: c drops; its claim stays for the grace period, then frees up.
	var session: NetSession = h.session_of(server, c)
	var t0: int = Time.get_ticks_msec()
	assert_bool(await h.drop(server, c)).is_true()
	assert_int(server.session.claims.holder(PLAYER, "crew:1")).is_equal(session.id)
	assert_bool(await h.lapsed(session)).is_true()
	assert_int(Time.get_ticks_msec() - t0).is_greater_equal(1000)
	# Released: b, now alone on Engineering, holds every crew again (FT-NET-044).
	assert_bool(await _holds(server, b, "crew:1", b)).is_true()
