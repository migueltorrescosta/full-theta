extends GdUnitTestSuite
## L3: the Captain's ping on a Comms card (FT-CPT-005) reaches every screen of the ship
## as a ping event of kind card, and the Captain fills only empty mark slots (FT-SPA-013).

const PLAYER: int = NetHarness.PLAYER

var h: NetHarness


func before_test() -> void:
	h = NetHarness.new(self)


func after_test() -> void:
	await h.free_all()


# FT: FT-CPT-005, FT-CPT-002
func test_a_card_ping_reaches_the_main_screen() -> void:
	var server: NetServer = h.server()
	var posted: PostCardCommand = StoryFixture.card(StoryTable.Kind.MISSION)
	posted.reward_credits = 250
	posted.expires_s = 90.0
	CommsL3.post(server, posted)
	var cap: NetClient = await h.joined(server, StationViews.CAPTAIN, StationViews.CAPTAIN)
	var viewer: NetClient = await h.joined(server, "viewer", StationViews.VIEWER)
	server.session.launch(PLAYER)
	assert_bool(await h.until(func() -> bool: return server.world.story.size() == 1)).is_true()
	var from: int = h.mark(viewer)
	cap.ping("card", 0, Vector3.ZERO)
	var e: Dictionary = await h.next_event(
		viewer,
		NetProtocol.EVENT_PING,
		from,
		func(ev: Dictionary) -> bool: return ev["payload"]["kind"] == "card"
	)
	assert_int(e["payload"]["id"]).is_equal(0)
	assert_str(e["payload"]["by"]).is_equal(StationViews.CAPTAIN)
	# The ping carries the card's text: a viewer has no Comms section to look it up in.
	var card: Dictionary = e["payload"]["card"]
	assert_int(card["kind"]).is_equal(StoryTable.Kind.MISSION)
	assert_str(card["title"]).is_equal(server.world.story.title[0])
	assert_float(card["expires"]).is_between(80.0, 90.0)
	# A card the list doesn't have is refused; a viewer may not ping at all.
	from = h.mark(cap)
	cap.ping("card", 999, Vector3.ZERO)
	var r: Dictionary = await h.next_event(cap, NetProtocol.EVENT_REQUEST_REJECTED, from)
	assert_str(r["payload"]["reason"]).is_equal(CrewPings.BAD_PING)


# FT: FT-CPT-005
# D215: only the Captain pings a card; a crew station's card ping is refused.
func test_a_crew_station_cannot_ping_a_card() -> void:
	var server: NetServer = h.server()
	CommsL3.post(server, StoryFixture.card(StoryTable.Kind.MISSION))
	var helm: NetClient = await h.joined(server, "helm", "helm")
	server.session.launch(PLAYER)
	assert_bool(await h.until(func() -> bool: return server.world.story.size() == 1)).is_true()
	var from: int = h.mark(helm)
	helm.ping("card", 0, Vector3.ZERO)
	var r: Dictionary = await h.next_event(helm, NetProtocol.EVENT_REQUEST_REJECTED, from)
	assert_str(r["payload"]["reason"]).is_equal(CrewPings.BAD_PING)
	assert_array(h.events_of(helm, NetProtocol.EVENT_PING)).is_empty()


# FT: FT-SPA-013, FT-CPT-002, FT-CPT-003
func test_the_captain_fills_empty_slots_only() -> void:
	var server: NetServer = h.server()
	var helm: NetClient = await h.joined(server, "helm", "helm")
	var cap: NetClient = await h.joined(server, StationViews.CAPTAIN, StationViews.CAPTAIN)
	helm.place_mark(0, "", -1, Vector3(5.0, 0.0, 0.0))
	await h.until(
		func() -> bool:
			return (
				not h.events_of(cap, NetProtocol.EVENT_MARKS).is_empty()
				and not h.last_event(cap, NetProtocol.EVENT_MARKS)["payload"]["marks"].is_empty()
			)
	)
	var from: int = h.mark(cap)
	cap.place_mark(-1, "", -1, Vector3(9.0, 0.0, 0.0))
	var marks: Dictionary = await h.next_event(
		cap,
		NetProtocol.EVENT_MARKS,
		from,
		func(ev: Dictionary) -> bool: return ev["payload"]["marks"].size() == 2
	)
	assert_int(marks["payload"]["marks"][1]["slot"]).is_equal(1)
	# A taken slot, a move and a delete are refused (the first mark is the helm's).
	var cases: Array[Callable] = [
		func() -> void: cap.place_mark(0, "", -1, Vector3.ZERO),
		func() -> void: cap.move_mark(0, -1, Vector3.ZERO),
		func() -> void: cap.delete_mark(0),
	]
	for send: Callable in cases:
		from = h.mark(cap)
		send.call()
		var r: Dictionary = await h.next_event(cap, NetProtocol.EVENT_REQUEST_REJECTED, from)
		assert_str(r.get("type", "")).is_equal(NetProtocol.EVENT_REQUEST_REJECTED)
	# And a command is not the Captain's to send.
	from = h.mark(cap)
	cap.command({"kind": &"helm_decoupled", "decoupled": true})
	var rej: Dictionary = await h.next_event(cap, NetProtocol.EVENT_COMMAND_REJECTED, from)
	assert_str(rej["payload"]["reason"]).is_equal("not_your_station")
