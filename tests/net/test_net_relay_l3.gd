extends GdUnitTestSuite
## L3 tests of Relay over loopback (E02): the mark inbox between allied ships, zones,
## routes and sites, marks on scanned subsystems, probes and the ship's log.

const PLAYER: int = NetHarness.PLAYER
const ALLY: int = NetHarness.ENEMY

var h: NetHarness


func before_test() -> void:
	h = NetHarness.new(self)


func after_test() -> void:
	await h.free_all()


## A server whose second ship is crewed by the first's faction (an ally), and the
## sender's Relay, the ally's Relay and the ally's Tactical.
func _allies() -> Array:
	var server: NetServer = h.server()
	var w: SimWorld = server.world
	w.ai.enabled[ALLY] = 0
	w.kin.factions[ALLY] = w.faction_of(PLAYER)
	var sender: NetClient = await h.joined(server, "sender", "ops", PLAYER)
	var receiver: NetClient = await h.joined(server, "receiver", "ops", ALLY)
	var bystander: NetClient = await h.joined(server, "bystander", "tactical", ALLY)
	var own: NetClient = await h.joined(server, "own", "tactical", PLAYER)
	return [server, sender, receiver, bystander, own]


func _rejected(c: NetClient, type: int, from: int) -> Dictionary:
	var e: Dictionary = await h.next_event(
		c,
		NetProtocol.EVENT_REQUEST_REJECTED,
		from,
		func(ev: Dictionary) -> bool: return ev["payload"]["request"] == type
	)
	return e.get("payload", {})


# FT: FT-RLY-008, FT-RLY-009, FT-SPA-020, FT-SPA-021
# A mark sent to an allied ship is visible only to that ship's Relay until it accepts it;
# then it is one of that ship's marks, for its whole crew, and the sender's marks are
# untouched. A declined mark is gone.
func test_sent_mark_waits_in_the_receiving_relay_inbox() -> void:
	var a: Array = await _allies()
	var sender: NetClient = a[1]
	var receiver: NetClient = a[2]
	var bystander: NetClient = a[3]
	var own: NetClient = a[4]
	var from: int = h.mark(receiver)
	var by_from: int = h.mark(bystander)
	var own_from: int = h.mark(own)
	sender.place_mark(-1, "Rock", -1, Vector3(1.0, 2.0, 3.0))
	await h.until(func() -> bool: return not h.events_of(own, NetProtocol.EVENT_MARKS).is_empty())
	sender.send_mark(0, ALLY)
	var inbox: Dictionary = await h.next_event(
		receiver,
		NetProtocol.EVENT_INBOX,
		from,
		func(e: Dictionary) -> bool: return not e["payload"]["items"].is_empty()
	)
	var item: Dictionary = inbox["payload"]["items"][0]
	assert_str(item["name"]).is_equal("Rock")
	assert_float(item["z"]).is_equal(3.0)
	assert_int(item["from_ship"]).is_equal(PLAYER)
	# Nobody else heard of it, and the receiving ship's marks did not change.
	await h.wait(300)
	for c: NetClient in [bystander, own, sender]:
		var seen: Array = h.events_of(c, NetProtocol.EVENT_INBOX)
		(
			assert_bool(
				seen.all(func(e: Dictionary) -> bool: return e["payload"]["items"].is_empty())
			)
			. is_true()
		)
	assert_array(h.events_of(bystander, NetProtocol.EVENT_MARKS).slice(by_from)).is_empty()
	assert_array(h.events_of(receiver, NetProtocol.EVENT_MARKS).slice(from)).is_empty()
	assert_int(a[0].session.crew.marks.marks_of(ALLY).size()).is_equal(0)
	# Only a Relay accepts.
	var why_from: int = h.mark(bystander)
	bystander.accept_mark(item["id"])
	var why: Dictionary = await _rejected(bystander, NetProtocol.Type.MARK_ACCEPT, why_from)
	assert_str(why.get("reason", "")).is_equal(CrewRelay.NOT_RELAY)
	# Accepting makes it one of the receiving ship's marks, shown to its crew.
	by_from = h.mark(bystander)
	receiver.accept_mark(item["id"])
	var marks: Dictionary = await h.next_event(bystander, NetProtocol.EVENT_MARKS, by_from)
	assert_str(marks["payload"]["marks"][0]["name"]).is_equal("Rock")
	assert_float(marks["payload"]["marks"][0]["z"]).is_equal(3.0)
	assert_int(a[0].session.crew.marks.marks_of(PLAYER).size()).is_equal(1)
	assert_array(a[0].session.crew.relay.inbox_of(ALLY)).is_empty()
	# Declined: discarded.
	from = h.mark(receiver)
	sender.send_mark(0, ALLY)
	inbox = await h.next_event(
		receiver,
		NetProtocol.EVENT_INBOX,
		from,
		func(e: Dictionary) -> bool: return not e["payload"]["items"].is_empty()
	)
	receiver.decline_mark(inbox["payload"]["items"][0]["id"])
	await h.until(func() -> bool: return a[0].session.crew.relay.inbox_of(ALLY).is_empty())
	assert_int(a[0].session.crew.marks.marks_of(ALLY).size()).is_equal(1)


# FT: FT-RLY-008, FT-RLY-009, FT-SPA-022
# With 8 marks an accept names the mark to replace (D182); without a slot it is refused.
# Only a Relay sends, and only to an allied, crewed ship.
func test_accepting_at_eight_marks_replaces_and_send_rules() -> void:
	var a: Array = await _allies()
	var server: NetServer = a[0]
	var sender: NetClient = a[1]
	var receiver: NetClient = a[2]
	var own: NetClient = a[4]
	for k: int in CrewMarks.SLOTS:
		receiver.place_mark(-1, "", -1, Vector3(10.0 * k, 0.0, 0.0))
	await h.until(func() -> bool: return server.session.crew.marks.marks_of(ALLY).size() == 8)
	var from: int = h.mark(receiver)
	sender.place_mark(-1, "Rock", -1, Vector3(9.0, 0.0, 0.0))
	await h.until(func() -> bool: return server.session.crew.marks.marks_of(PLAYER).size() == 1)
	sender.send_mark(0, ALLY)
	var inbox: Dictionary = await h.next_event(
		receiver,
		NetProtocol.EVENT_INBOX,
		from,
		func(e: Dictionary) -> bool: return not e["payload"]["items"].is_empty()
	)
	var id: int = inbox["payload"]["items"][0]["id"]
	from = h.mark(receiver)
	receiver.accept_mark(id, -1)
	var why: Dictionary = await _rejected(receiver, NetProtocol.Type.MARK_ACCEPT, from)
	assert_str(why.get("reason", "")).is_equal(CrewMarks.MARKS_FULL)
	assert_int(server.session.crew.relay.inbox_of(ALLY).size()).is_equal(1)
	receiver.accept_mark(id, 4)
	await h.until(func() -> bool: return server.session.crew.relay.inbox_of(ALLY).is_empty())
	var marks: Array = server.session.crew.marks.marks_of(ALLY)
	assert_int(marks.size()).is_equal(8)
	assert_str(marks[4]["name"]).is_equal("Rock")
	# Not a Relay; not allied; no such mark.
	from = h.mark(own)
	own.send_mark(0, ALLY)
	why = await _rejected(own, NetProtocol.Type.MARK_SEND, from)
	assert_str(why.get("reason", "")).is_equal(CrewRelay.NOT_RELAY)
	from = h.mark(sender)
	sender.send_mark(0, PLAYER)
	why = await _rejected(sender, NetProtocol.Type.MARK_SEND, from)
	assert_str(why.get("reason", "")).is_equal(CrewRelay.BAD_TARGET)
	server.world.kin.factions[ALLY] = 9
	from = h.mark(sender)
	sender.send_mark(0, ALLY)
	why = await _rejected(sender, NetProtocol.Type.MARK_SEND, from)
	assert_str(why.get("reason", "")).is_equal(CrewRelay.BAD_TARGET)
	server.world.kin.factions[ALLY] = server.world.faction_of(PLAYER)
	from = h.mark(sender)
	sender.send_mark(5, ALLY)
	why = await _rejected(sender, NetProtocol.Type.MARK_SEND, from)
	assert_str(why.get("reason", "")).is_equal(CrewMarks.BAD_MARK)


# FT: FT-RLY-009
# D221: a mark attached to a contact the faction no longer detects can't be sent (it would
# go as the contact's true position); while the contact is detected the send works.
func test_lost_contact_mark_cannot_be_sent() -> void:
	var a: Array = await _allies()
	var server: NetServer = a[0]
	var sender: NetClient = a[1]
	var w: SimWorld = server.world
	var foe: int = w.spawn_enemy(TestDefs.raider_enemy(), 7, Vector3(500.0, 0.0, 0.0))
	KnowledgeSystem.step(w)
	var faction: int = w.faction_of(PLAYER)
	assert_bool(KnowledgeSystem.is_detected(w, faction, foe)).is_true()
	var from: int = h.mark(sender)
	sender.place_mark(-1, "Foe", foe, Vector3.ZERO)
	await h.until(func() -> bool: return server.session.crew.marks.marks_of(PLAYER).size() == 1)
	sender.send_mark(0, ALLY)
	await h.until(func() -> bool: return server.session.crew.relay.inbox_of(ALLY).size() == 1)
	w.knowledge.detected[w.knowledge.row_for(faction, foe)] = 0
	from = h.mark(sender)
	sender.send_mark(0, ALLY)
	var why: Dictionary = await _rejected(sender, NetProtocol.Type.MARK_SEND, from)
	assert_str(why.get("reason", "")).is_equal(CrewRelay.LOST_CONTACT)
	assert_int(server.session.crew.relay.inbox_of(ALLY).size()).is_equal(1)


# FT: FT-SPA-028, FT-SPA-016
# D222: a hazard zone and a probe bubble can be pinged like marks, by every crew pick; an id
# that is neither refuses.
func test_zones_and_probe_bubbles_can_be_pinged() -> void:
	var server: NetServer = h.server()
	var relay: NetClient = await h.joined(server, "relay", "ops")
	var helm: NetClient = await h.joined(server, "helm", "tactical")
	var w: SimWorld = server.world
	w.probes.launch(PLAYER, w.faction_of(PLAYER), 3, Vector3.ZERO, Vector3(0.0, 0.0, -100.0))
	relay.hazard_add(2000.0, Vector3(1000.0, 0.0, -3000.0))
	await h.until(func() -> bool: return server.session.crew.relay.zones_of(PLAYER).size() == 1)
	var zone: int = server.session.crew.relay.zones_of(PLAYER)[0]["id"]
	var from: int = h.mark(relay)
	helm.ping("zone", zone, Vector3.ZERO)
	var e: Dictionary = await h.next_event(
		relay,
		NetProtocol.EVENT_PING,
		from,
		func(ev: Dictionary) -> bool: return ev["payload"]["kind"] == "zone"
	)
	assert_int(e["payload"]["id"]).is_equal(zone)
	from = h.mark(relay)
	helm.ping("zone", -4, Vector3.ZERO)
	e = await h.next_event(
		relay,
		NetProtocol.EVENT_PING,
		from,
		func(ev: Dictionary) -> bool: return ev["payload"]["kind"] == "zone"
	)
	assert_int(e["payload"]["id"]).is_equal(-4)
	from = h.mark(helm)
	helm.ping("zone", CrewPings.HAZARD_ZONE_BASE - 7, Vector3.ZERO)
	var why: Dictionary = await _rejected(helm, NetProtocol.Type.PING, from)
	assert_str(why.get("reason", "")).is_equal(CrewPings.BAD_PING)


# FT: FT-SPA-027, FT-SPA-028, FT-SPA-012, FT-SPA-029, FT-RLY-005
# Every pick gets the scenario's sites (the SITES section); hazard zones and scan positions
# sit outside the 8-mark cap and every pick of the ship gets them at every difficulty; routes reach
# Relay always and the other stations except on Hard.
func test_sites_zones_and_routes_reach_who_they_should() -> void:
	var server: NetServer = h.server()
	var relay: NetClient = await h.joined(server, "relay", "ops")
	var helm: NetClient = await h.joined(server, "helm", "tactical")
	var viewer: NetClient = await h.joined(server, "viewer", "viewer")
	assert_bool(await h.until(func() -> bool: return not viewer.view.sites.is_empty())).is_true()
	assert_str(viewer.view.sites[0]["name_key"]).is_equal("site.kestrel_yard")
	# Eight marks, and zones beyond them.
	for k: int in CrewMarks.SLOTS:
		relay.place_mark(-1, "", -1, Vector3(5.0 * k, 0.0, 0.0))
	relay.hazard_add(2000.0, Vector3(1000.0, 0.0, -3000.0))
	server.session.crew.add_scan_position(PLAYER, Vector3(5.0, 6.0, 7.0), 500.0, "science")
	var two: Callable = func() -> bool:
		var z: Dictionary = h.last_event(viewer, NetProtocol.EVENT_ZONES)
		return not z.is_empty() and z["payload"]["zones"].size() == 2
	assert_bool(await h.until(two)).is_true()
	var zones: Array = h.last_event(viewer, NetProtocol.EVENT_ZONES)["payload"]["zones"]
	zones.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["kind"] < y["kind"])
	assert_str(zones[0]["kind"]).is_equal("hazard")
	assert_float(zones[0]["radius"]).is_equal(2000.0)
	assert_str(zones[1]["kind"]).is_equal("scan")
	assert_int(server.session.crew.marks.marks_of(PLAYER).size()).is_equal(8)
	# Only Relay changes zones and routes.
	var from: int = h.mark(helm)
	helm.hazard_add(1000.0, Vector3.ZERO)
	var why: Dictionary = await _rejected(helm, NetProtocol.Type.MARK, from)
	assert_str(why.get("reason", "")).is_equal(CrewRelay.NOT_RELAY)
	# Routes: Hard keeps them off Tactical (FT-PAIR-008), Relay still sees them.
	h.session_of(server, helm).toggles = "hard"
	from = h.mark(helm)
	# Zones survive Hard (FT-SPA-028): Tactical still gets a new hazard.
	relay.hazard_add(1000.0, Vector3(-300.0, 0.0, 100.0))
	var hard_zones: Dictionary = await h.next_event(
		helm,
		NetProtocol.EVENT_ZONES,
		from,
		func(e: Dictionary) -> bool: return e["payload"]["zones"].size() == 3
	)
	assert_dict(hard_zones).is_not_empty()
	var drop: int = hard_zones["payload"]["zones"][-1]["id"]
	relay.hazard_delete(drop)
	await h.until(func() -> bool: return server.session.crew.relay.zones_of(PLAYER).size() == 2)
	from = h.mark(helm)
	var relay_from: int = h.mark(relay)
	relay.route_add(0, Vector3(0.0, 0.0, -2000.0))
	relay.route_add(0, Vector3(900.0, 0.0, -4000.0))
	var routes: Dictionary = await h.next_event(
		relay,
		NetProtocol.EVENT_ROUTES,
		relay_from,
		func(e: Dictionary) -> bool: return e["payload"]["routes"][0].size() == 2
	)
	assert_float(routes["payload"]["routes"][0][1]["x"]).is_equal(900.0)
	await h.wait(200)
	assert_array(h.events_of(helm, NetProtocol.EVENT_ROUTES).slice(from)).is_empty()
	# On Normal Tactical gets them once Relay shares them (D210); the zones stayed on Hard.
	h.session_of(server, helm).toggles = "normal"
	relay.share("routes")
	routes = await h.next_event(
		helm,
		NetProtocol.EVENT_ROUTES,
		from,
		func(e: Dictionary) -> bool: return not e["payload"]["routes"][0].is_empty()
	)
	assert_int(routes["payload"]["routes"][0].size()).is_equal(2)
	from = h.mark(helm)
	relay.route_add(1, Vector3(1.0, 1.0, 1.0))
	routes = await h.next_event(helm, NetProtocol.EVENT_ROUTES, from)
	assert_int(routes["payload"]["routes"][1].size()).is_equal(1)
	assert_int(server.session.crew.relay.zones_of(PLAYER).size()).is_equal(2)
	relay.hazard_delete(zones[0]["id"])
	await h.until(func() -> bool: return server.session.crew.relay.zones_of(PLAYER).size() == 1)
	relay.route_clear(0)
	await h.until(func() -> bool: return server.session.crew.relay.routes_of(PLAYER)[0].is_empty())


# FT: FT-SPA-014
# A mark attaches to a contact's subsystem only once its weak point is revealed (D202);
# the mark then rides on the subsystem's place in the contact's frame.
func test_mark_on_a_revealed_subsystem_only() -> void:
	var server: NetServer = h.server()
	server.world.science_def = ScienceFixture.science()
	server.world.defs[NetHarness.ENEMY] = ScienceFixture.weak_raider()
	KnowledgeSystem.step(server.world)
	var relay: NetClient = await h.joined(server, "relay", "ops")
	var enemy: int = NetHarness.ENEMY
	var from: int = h.mark(relay)
	relay.place_mark(-1, "Core", enemy, Vector3(1.0, 0.0, 0.0))
	var why: Dictionary = await _rejected(relay, NetProtocol.Type.MARK, from)
	assert_str(why.get("reason", "")).is_equal(CrewMarks.BAD_MARK)
	# After the scan.
	ScienceKnowledge.record(server.world, server.world.faction_of(PLAYER), enemy, 1.0)
	from = h.mark(relay)
	relay.place_mark(-1, "Core", enemy, Vector3(1.0, 0.0, 0.0))
	var marks: Dictionary = await h.next_event(relay, NetProtocol.EVENT_MARKS, from)
	var m: Dictionary = marks["payload"]["marks"][0]
	assert_int(m["contact"]).is_equal(enemy)
	assert_int(m["sub"]).is_equal(0)
	var def: ShipDef = server.world.defs[enemy]
	assert_float(m["z"]).is_equal_approx(def.subsystems[0].position.z, 0.001)
	# A subsystem that is not revealed, or does not exist, is refused; a plain contact mark
	# needs no scan.
	from = h.mark(relay)
	relay.place_mark(-1, "Nope", enemy, Vector3(3.0, 0.0, 0.0))
	why = await _rejected(relay, NetProtocol.Type.MARK, from)
	assert_str(why.get("reason", "")).is_equal(CrewMarks.BAD_MARK)
	relay.place_mark(-1, "Plain", enemy, Vector3.ZERO)
	await h.until(func() -> bool: return server.session.crew.marks.marks_of(PLAYER).size() == 2)
	assert_int(server.session.crew.marks.marks_of(PLAYER)[1]["sub"]).is_equal(-1)


# FT: FT-RLY-004, FT-RLY-006, FT-RLY-007, FT-RLY-011
# Relay launches a probe through the command path; the stock and the probe reach its
# snapshot, the ship's log records it as keys (no text), and a lane warning reaches
# Relay and, once Relay shared its track feeds, Weapons only.
func test_probe_launch_log_and_lane_warning_events() -> void:
	var server: NetServer = h.server()
	var relay: NetClient = await h.joined(server, "relay", "ops")
	var tac: NetClient = await h.joined(server, "tac", "tactical")
	var sys: NetClient = await h.joined(server, "sys", "systems")
	assert_bool(await h.start(server, relay)).is_true()
	var from: int = h.mark(relay)
	relay.command({"kind": "launch_probe", "x": 0.0, "y": 0.0, "z": -2000.0})
	var logged: Dictionary = await h.next_event(
		relay,
		NetProtocol.EVENT_RELAY_LOG,
		from,
		func(e: Dictionary) -> bool:
			return e["payload"]["entries"].any(
				func(x: Dictionary) -> bool: return x["key"] == "probe_launched"
			)
	)
	assert_dict(logged).is_not_empty()
	var entry: Dictionary = logged["payload"]["entries"][0]
	(
		assert_bool(entry["args"].values().all(func(v: Variant) -> bool: return not v is String))
		. is_true()
	)
	var snap: Callable = func() -> bool:
		var blk: Dictionary = relay.view.blocks.get(StationViews.Section.RELAY, {})
		return not blk.is_empty() and blk["stock"] == 2 and blk["probes"].size() == 1
	assert_bool(await h.until(snap)).is_true()
	# Ticks of flight: it deploys; Weapons never gets a Relay block (Engineering and
	# Science do: fabrication seconds, probe bubbles), nor Relay's events.
	var deployed: Callable = func() -> bool:
		return relay.view.blocks[StationViews.Section.RELAY]["probes"][0]["deployed"]
	assert_bool(await h.until(deployed, 20000)).is_true()
	assert_bool(tac.view.blocks.has(StationViews.Section.RELAY)).is_false()
	assert_bool(sys.view.blocks.has(StationViews.Section.RELAY)).is_true()
	assert_array(h.events_of(sys, "probe_launched")).is_empty()
	# Lane flagging and its warning: a friendly in the bow mount's line.
	var w: SimWorld = server.world
	w.ai.enabled[NetHarness.ENEMY] = 0
	w.kin.factions[NetHarness.ENEMY] = w.faction_of(PLAYER)
	# The warning is a track-feed shortcut: it reaches Weapons once Relay shares (D210).
	relay.share("track_feeds")
	var tac_session: NetSession = h.session_of(server, tac)
	(
		assert_bool(
			await h.until(func() -> bool: return tac_session.shares.has(ViewFilter.TRACK_FEEDS))
		)
		. is_true()
	)
	from = h.mark(tac)
	var tac_from: int = h.mark(sys)
	relay.command({"kind": "flag_lanes", "on": true})
	var warn: Dictionary = await h.next_event(tac, "lane_warning", from)
	assert_int(warn.get("payload", {}).get("other", -1)).is_equal(NetHarness.ENEMY)
	await h.wait(200)
	assert_array(h.events_of(sys, "lane_warning").slice(tac_from)).is_empty()


# FT: FT-RLY-004, FT-NET-022
# The probe launcher is a claim: with two Relay players only the claimer launches, and
# the claim shows in the other's OWNERSHIP view.
func test_two_relay_players_share_the_probe_launcher_by_claim() -> void:
	var server: NetServer = h.server()
	var first: NetClient = await h.joined(server, "ana", "relay")
	var second: NetClient = await h.joined(server, "bo", "ops")
	var id: int = h.session_of(server, first).id
	var held: Callable = func() -> bool:
		return second.view.ownership.get("claims", {}).get("probe", [-1])[0] == id
	assert_bool(await h.until(held)).is_true()
	assert_str(second.view.claimer("probe")).is_equal("ana")
	server.session.launch(PLAYER)
	var cmd: Dictionary = {"kind": "launch_probe", "x": 0.0, "y": 0.0, "z": -500.0}
	var from: int = h.mark(second)
	var seq: int = second.command(cmd)
	var refused: Dictionary = await h.next_event(
		second,
		NetProtocol.EVENT_COMMAND_REJECTED,
		from,
		func(e: Dictionary) -> bool: return e["payload"]["seq"] == seq
	)
	assert_str(refused.get("payload", {}).get("reason", "")).is_equal(CommandGate.CLAIMED)
	first.command(cmd)
	var launched: Callable = func() -> bool: return server.world.relay.stock[PLAYER] == 2
	assert_bool(await h.until(launched)).is_true()


# FT: FT-SPA-014
# Without a test override the weak-point gate reads Science's scan knowledge (D202,
# FT-SIM-023): the subsystem marks once the contact's scan confidence reveals it.
func test_subsystem_mark_follows_science_knowledge() -> void:
	var server: NetServer = h.server()
	var enemy: int = NetHarness.ENEMY
	server.world.science_def = ScienceFixture.science()
	server.world.defs[enemy] = ScienceFixture.weak_raider()
	KnowledgeSystem.step(server.world)
	var relay: NetClient = await h.joined(server, "relay", "ops")
	var from: int = h.mark(relay)
	relay.place_mark(-1, "Core", enemy, Vector3(1.0, 0.0, 0.0))
	var why: Dictionary = await _rejected(relay, NetProtocol.Type.MARK, from)
	assert_str(why.get("reason", "")).is_equal(CrewMarks.BAD_MARK)
	ScienceKnowledge.record(server.world, server.world.faction_of(PLAYER), enemy, 1.0)
	from = h.mark(relay)
	relay.place_mark(-1, "Core", enemy, Vector3(1.0, 0.0, 0.0))
	var marks: Dictionary = await h.next_event(relay, NetProtocol.EVENT_MARKS, from)
	assert_int(marks["payload"]["marks"][0]["sub"]).is_equal(0)


# FT: FT-SPA-028, FT-SCI-005
# Science's scan-position mark becomes one scan zone of the ship, outside the 8 marks;
# a new mark replaces it and a repeated one adds nothing.
func test_science_scan_mark_makes_a_scan_position() -> void:
	var server: NetServer = h.server()
	var enemy: int = NetHarness.ENEMY
	server.world.science_def = ScienceFixture.science()
	KnowledgeSystem.step(server.world)
	var crew: NetCrewState = server.session.crew
	assert_bool(ScienceSystem.place_mark(server.world, PLAYER, enemy)).is_true()
	for e: SimEvent in server.world.drain_events():
		crew.on_sim_event(e)
	var zones: Array = crew.relay.zones_of(PLAYER)
	assert_int(zones.size()).is_equal(1)
	assert_str(zones[0]["kind"]).is_equal("scan")
	assert_float(zones[0]["radius"]).is_equal(server.world.science_def.mark_radius)
	assert_float(zones[0]["x"]).is_equal_approx(server.world.science.mark_x[PLAYER], 0.001)
	assert_int(crew.marks.marks_of(PLAYER).size()).is_equal(0)
	var again: SimEvent = SimEvent.new()
	again.kind = &"scan_mark"
	again.ship_id = PLAYER
	crew.on_sim_event(again)
	assert_int(crew.relay.zones_of(PLAYER).size()).is_equal(1)
