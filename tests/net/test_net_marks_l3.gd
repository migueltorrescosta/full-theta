extends GdUnitTestSuite
## L3 tests of marks, pings and the alert level over loopback (NetCrewState with
## CrewMarks and CrewPings): who may do what, which contacts and named sites they may name,
## who hears it, and the state a joining client gets.

const PLAYER: int = NetHarness.PLAYER
const ENEMY: int = NetHarness.ENEMY

var h: NetHarness


func before_test() -> void:
	h = NetHarness.new(self)


func after_test() -> void:
	await h.free_all()


## The rejection of a request type at or after `from`, waiting for it; {} on timeout.
func _rejected(c: NetClient, type: int, from: int) -> Dictionary:
	var e: Dictionary = await h.next_event(
		c,
		NetProtocol.EVENT_REQUEST_REJECTED,
		from,
		func(ev: Dictionary) -> bool: return ev["payload"]["request"] == type
	)
	return e.get("payload", {})


## Runs the sensors once without stepping the sim: the player's faction detects the
## enemy, as in a started run.
func _detect(server: NetServer) -> void:
	KnowledgeSystem.step(server.world)
	var w: SimWorld = server.world
	assert_bool(KnowledgeSystem.is_detected(w, w.faction_of(PLAYER), ENEMY)).is_true()


## The next `marks` event at or after `from`; its marks list.
func _marks(c: NetClient, from: int) -> Array:
	var e: Dictionary = await h.next_event(c, NetProtocol.EVENT_MARKS, from)
	return e.get("payload", {}).get("marks", [{"timeout": true}])


# FT: FT-SPA-012, FT-SPA-013, FT-SPA-020, FT-SPA-022, FT-RLY-003
func test_marks_cap_relay_replace_and_relay_only_edits() -> void:
	var server: NetServer = h.server()
	_detect(server)
	var crew: Array[NetClient] = await h.crew3(server)
	var tac: NetClient = crew[0]
	var sys: NetClient = crew[1]
	var ops: NetClient = crew[2]
	var viewer: NetClient = await h.joined(server, "viewer", "viewer")
	var lobby: NetClient = await h.welcomed(server, "lobby")
	var from: int = h.mark(viewer)
	for k: int in CrewMarks.SLOTS:
		tac.place_mark(-1, "", -1, Vector3(100.0 * k, 0.0, 0.0))
	var full: Callable = func() -> bool:
		var last: Dictionary = h.last_event(viewer, NetProtocol.EVENT_MARKS)
		return not last.is_empty() and last["payload"]["marks"].size() == CrewMarks.SLOTS
	assert_bool(await h.until(full)).is_true()
	var placed: Array = h.last_event(viewer, NetProtocol.EVENT_MARKS)["payload"]["marks"]
	assert_str(placed[7]["name"]).is_equal("Hotel")
	assert_str(placed[7]["by"]).is_equal("tactical")
	assert_float(placed[7]["x"]).is_equal(700.0)
	assert_int(h.events_of(viewer, NetProtocol.EVENT_MARKS).size()).is_greater_equal(8)
	# The ninth: refused for a crew station, and for Relay without a slot.
	from = h.mark(tac)
	tac.place_mark(-1, "", -1, Vector3.ZERO)
	var why: Dictionary = await _rejected(tac, NetProtocol.Type.MARK, from)
	assert_str(why.get("reason", "")).is_equal(CrewMarks.MARKS_FULL)
	from = h.mark(ops)
	ops.place_mark(-1, "", -1, Vector3.ZERO)
	why = await _rejected(ops, NetProtocol.Type.MARK, from)
	assert_str(why.get("reason", "")).is_equal(CrewMarks.MARKS_FULL)
	# Relay replaces the slot it names, attached to a contact.
	from = h.mark(sys)
	ops.place_mark(2, "Bogey", ENEMY, Vector3.ZERO)
	var marks: Array = await _marks(sys, from)
	assert_dict(marks[2]).contains_key_value("name", "Bogey")
	assert_dict(marks[2]).contains_key_value("contact", ENEMY)
	assert_dict(marks[2]).contains_key_value("by", "ops")
	# Another crew station can't rename or delete Tactical's marks; Relay can.
	from = h.mark(sys)
	sys.rename_mark(0, "Mine")
	why = await _rejected(sys, NetProtocol.Type.MARK, from)
	assert_str(why.get("reason", "")).is_equal(CrewMarks.NOT_YOURS)
	sys.delete_mark(0)
	from = h.mark(sys)
	ops.delete_mark(0)
	marks = await _marks(sys, from)
	assert_int(marks.size()).is_equal(7)
	assert_int(marks[0]["slot"]).is_equal(1)
	# Tactical moves its own mark.
	from = h.mark(ops)
	tac.move_mark(1, -1, Vector3(5.0, 6.0, 7.0))
	marks = await _marks(ops, from)
	assert_float(marks[0]["z"]).is_equal(7.0)
	# Nothing reached the client without a pick (FT-SPA-020).
	assert_array(h.events_of(lobby, NetProtocol.EVENT_MARKS)).is_empty()


# FT: FT-SPA-016, FT-SPA-020, FT-SPA-017, FT-SPA-031
func test_pings_reach_every_pick_of_the_ship_only() -> void:
	var server: NetServer = h.server()
	# The enemy ship without its AI: another crewable ship, to check isolation.
	server.world.ai.enabled[ENEMY] = 0
	_detect(server)
	var crew: Array[NetClient] = await h.crew3(server)
	var viewer: NetClient = await h.joined(server, "viewer", "viewer")
	var captain: NetClient = await h.joined(server, "captain", "captain")
	var other: NetClient = await h.joined(server, "other", "viewer", ENEMY)
	var from: int = h.mark(viewer)
	crew[0].ping("contact", ENEMY, Vector3.ZERO)
	var ping: Dictionary = await h.next_event(viewer, NetProtocol.EVENT_PING, from)
	assert_dict(ping.get("payload", {})).contains_key_value("by", "tactical")
	assert_dict(ping["payload"]).contains_key_value("copy", "")
	assert_dict(ping["payload"]).contains_key_value("id", ENEMY)
	for c: NetClient in [crew[1], crew[2], captain, crew[0]]:
		assert_dict(await h.next_event(c, NetProtocol.EVENT_PING, 0)).is_not_empty()
	# Another station's ping on the same item within 3 s is a copy.
	from = h.mark(viewer)
	captain.ping("contact", ENEMY, Vector3.ZERO)
	ping = await h.next_event(viewer, NetProtocol.EVENT_PING, from)
	assert_dict(ping.get("payload", {})).contains_key_value("copy", "tactical")
	assert_dict(ping["payload"]).contains_key_value("by", "captain")
	# A point ping, wrapped onto the cube.
	from = h.mark(viewer)
	crew[1].ping("point", -1, Vector3(250_000.0, 0.0, 0.0))
	ping = await h.next_event(viewer, NetProtocol.EVENT_PING, from)
	assert_float(ping.get("payload", {}).get("x", 0.0)).is_equal(-150_000.0)
	# Viewers don't ping.
	from = h.mark(viewer)
	viewer.ping("contact", ENEMY, Vector3.ZERO)
	var why: Dictionary = await _rejected(viewer, NetProtocol.Type.PING, from)
	assert_str(why.get("reason", "")).is_equal(ServerSession.NOT_CREW)
	# Rate limit: burst 3, then refused.
	from = h.mark(crew[2])
	for i: int in 5:
		crew[2].ping("site", 0, Vector3.ZERO)
	why = await _rejected(crew[2], NetProtocol.Type.PING, from)
	assert_str(why.get("reason", "")).is_equal(CommandGate.RATE_LIMITED)
	await h.wait(200)
	# The other ship heard none of it.
	assert_array(h.events_of(other, NetProtocol.EVENT_PING)).is_empty()


# FT: FT-STN-008, FT-SPA-012
func test_alert_from_crew_and_the_state_a_joining_client_gets() -> void:
	var server: NetServer = h.server()
	var crew: Array[NetClient] = await h.crew3(server)
	var captain: NetClient = await h.joined(server, "captain", "captain")
	var viewer: NetClient = await h.joined(server, "viewer", "viewer")
	# Each pick got the current state: Normal, no marks.
	var first: Dictionary = h.last_event(viewer, NetProtocol.EVENT_ALERT)
	assert_dict(first.get("payload", {})).contains_key_value("level", CrewMarks.ALERT_NORMAL)
	assert_array(h.last_event(viewer, NetProtocol.EVENT_MARKS)["payload"]["marks"]).is_empty()
	var from: int = h.mark(viewer)
	crew[1].set_alert(CrewMarks.ALERT_RED)
	var alert: Dictionary = await h.next_event(viewer, NetProtocol.EVENT_ALERT, from)
	assert_dict(alert.get("payload", {})).contains_key_value("level", CrewMarks.ALERT_RED)
	assert_dict(alert["payload"]).contains_key_value("by", "systems")
	for c: NetClient in [captain, viewer]:
		from = h.mark(c)
		c.set_alert(CrewMarks.ALERT_YELLOW)
		var why: Dictionary = await _rejected(c, NetProtocol.Type.ALERT, from)
		assert_str(why.get("reason", "")).is_equal(ServerSession.NOT_CREW)
	assert_int(server.session.crew.marks.alert(PLAYER)).is_equal(CrewMarks.ALERT_RED)
	crew[0].place_mark(-1, "Rock", -1, Vector3(1.0, 2.0, 3.0))
	(
		assert_bool(
			await h.until(
				func() -> bool: return server.session.crew.marks.marks_of(PLAYER).size() == 1
			)
		)
		. is_true()
	)
	# A new client that picks the ship, and one that rejoins by token, get both.
	var late: NetClient = await h.joined(server, "late", "viewer")
	assert_int(h.last_event(late, NetProtocol.EVENT_ALERT)["payload"]["level"]).is_equal(2)
	var marks: Array = h.last_event(late, NetProtocol.EVENT_MARKS)["payload"]["marks"]
	assert_str(marks[0]["name"]).is_equal("Rock")
	var token: String = crew[2].token
	await h.drop(server, crew[2])
	var back: NetClient = h.client(server, "ops", token)
	assert_dict(await h.next_event(back, NetProtocol.EVENT_MARKS)).is_not_empty()
	assert_int(h.last_event(back, NetProtocol.EVENT_ALERT)["payload"]["level"]).is_equal(2)
	# A run reset clears them, with events.
	from = h.mark(viewer)
	server.session.crew.reset(PLAYER)
	alert = await h.next_event(viewer, NetProtocol.EVENT_ALERT, from)
	assert_dict(alert.get("payload", {})).contains_key_value("level", CrewMarks.ALERT_NORMAL)
	assert_array(await _marks(viewer, from)).is_empty()


# FT: FT-SPA-012, FT-SPA-014, FT-SPA-016, FT-SPA-020
# A mark or ping may name only a contact the sender's faction detects (or its own ship)
# and a named site the world has; an undetected contact and an id past the ship count get the
# same refusal. A free mark is wrapped onto the cube.
func test_marks_and_pings_name_only_detected_contacts_and_real_sites() -> void:
	var server: NetServer = h.server()
	var crew: Array[NetClient] = await h.crew3(server)
	var tac: NetClient = crew[0]
	var w: SimWorld = server.world
	assert_bool(KnowledgeSystem.is_detected(w, w.faction_of(PLAYER), ENEMY)).is_false()
	var reasons: Array = []
	for contact: int in [ENEMY, w.ship_count(), 999]:
		var from: int = h.mark(tac)
		tac.place_mark(-1, "", contact, Vector3.ZERO)
		reasons.append((await _rejected(tac, NetProtocol.Type.MARK, from)).get("reason", ""))
		from = h.mark(tac)
		tac.ping("contact", contact, Vector3.ZERO)
		reasons.append((await _rejected(tac, NetProtocol.Type.PING, from)).get("reason", ""))
		await h.wait(600)  # the ping rate limit
	var mark_bad: Array = [CrewMarks.BAD_MARK, CrewPings.BAD_PING]
	assert_array(reasons).is_equal(mark_bad + mark_bad + mark_bad)
	# A named site the world lacks.
	var from: int = h.mark(tac)
	tac.ping("site", 7, Vector3.ZERO)
	var why: Dictionary = await _rejected(tac, NetProtocol.Type.PING, from)
	assert_str(why.get("reason", "")).is_equal(CrewPings.BAD_PING)
	# The own ship is always known; a free mark wraps; a detected enemy may be marked.
	from = h.mark(tac)
	tac.place_mark(-1, "", PLAYER, Vector3.ZERO)
	assert_int((await _marks(tac, from))[0]["contact"]).is_equal(PLAYER)
	from = h.mark(tac)
	tac.place_mark(-1, "", -1, Vector3(250_000.0, 0.0, 0.0))
	assert_float((await _marks(tac, from))[1]["x"]).is_equal(-150_000.0)
	_detect(server)
	from = h.mark(tac)
	tac.place_mark(-1, "", ENEMY, Vector3.ZERO)
	assert_int((await _marks(tac, from))[2]["contact"]).is_equal(ENEMY)
