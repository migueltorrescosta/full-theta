extends GdUnitTestSuite
## L3: the Captain's priority target over loopback (gp-15, NetCrewState): only the Captain
## seat sets it, on a contact the faction detects; every pick of the ship hears it, a joining
## one gets it, and it clears with -1 and when the contact leaves play.

const PLAYER: int = NetHarness.PLAYER
const ENEMY: int = NetHarness.ENEMY

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
		func(ev: Dictionary) -> bool:
			return ev["payload"]["request"] == NetProtocol.Type.PRIORITY_TARGET
	)
	return str(e.get("payload", {}).get("reason", ""))


func _priority(c: NetClient, from: int) -> Dictionary:
	var e: Dictionary = await h.next_event(c, NetProtocol.EVENT_PRIORITY, from)
	return e.get("payload", {"contact": -99})


# FT: FT-CPT-003, FT-CPT-006
# The Captain sets the priority target for every pick of the ship; crew (Relay too) and a
# viewer are refused, so is a contact the faction doesn't detect; -1 clears it.
func test_only_the_captain_sets_it_and_every_pick_hears_it() -> void:
	var server: NetServer = h.server()
	var helm: NetClient = await h.joined(server, "helm", "helm")
	var relay: NetClient = await h.joined(server, "relay", "relay")
	var cap: NetClient = await h.joined(server, StationCatalogue.CAPTAIN, StationCatalogue.CAPTAIN)
	var viewer: NetClient = await h.joined(server, "viewer", StationCatalogue.VIEWER)
	# Not detected yet: refused like an unknown id.
	var from: int = h.mark(cap)
	cap.set_priority(ENEMY)
	assert_str(await _rejected(cap, from)).is_equal(CrewPings.BAD_PING)
	KnowledgeSystem.step(server.world)
	for c: NetClient in [helm, relay, viewer]:
		from = h.mark(c)
		c.set_priority(ENEMY)
		assert_str(await _rejected(c, from)).is_equal(NetProtocol.REASON_NOT_ALLOWED)
	from = h.mark(helm)
	cap.set_priority(ENEMY)
	var p: Dictionary = await _priority(helm, from)
	assert_int(p["contact"]).is_equal(ENEMY)
	assert_str(p["by"]).is_equal(StationCatalogue.CAPTAIN)
	var w: SimWorld = server.world
	assert_str(p["callsign"]).is_equal(KnowledgeSystem.callsign(w, w.faction_of(PLAYER), ENEMY))
	(
		assert_int(int(h.last_event(viewer, NetProtocol.EVENT_PRIORITY)["payload"]["contact"]))
		. is_equal(ENEMY)
	)
	# A pick that joins now gets the current target.
	var late: NetClient = await h.joined(server, "late", "weapons")
	assert_int(int(h.last_event(late, NetProtocol.EVENT_PRIORITY)["payload"]["contact"])).is_equal(
		ENEMY
	)
	from = h.mark(helm)
	cap.set_priority(-1)
	assert_int((await _priority(helm, from))["contact"]).is_equal(-1)


# FT: FT-CPT-006
# A priority target that leaves play is cleared for the ship.
func test_it_clears_when_the_contact_leaves_play() -> void:
	var server: NetServer = h.server()
	var helm: NetClient = await h.joined(server, "helm", "helm")
	var cap: NetClient = await h.joined(server, StationCatalogue.CAPTAIN, StationCatalogue.CAPTAIN)
	KnowledgeSystem.step(server.world)
	var from: int = h.mark(helm)
	cap.set_priority(ENEMY)
	assert_int((await _priority(helm, from))["contact"]).is_equal(ENEMY)
	from = h.mark(helm)
	var e: SimEvent = SimEvent.new()
	e.kind = &"destroyed"
	e.ship_id = ENEMY
	server.game.crew.on_sim_event(e)
	assert_int((await _priority(helm, from))["contact"]).is_equal(-1)
	assert_bool(server.game.crew.priorities.has(PLAYER)).is_false()
