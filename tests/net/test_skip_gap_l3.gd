extends GdUnitTestSuite
## L3 tests of skipping the quiet gap (gp-07, D3, NetSkipGap): while the director's gap flag
## is set, the fleet's human crew tap Ready; once every one of them is, the server sets the
## director's skip flag through a logged command. A missing one keeps the gap; viewers don't
## vote.

const PLAYER: int = NetHarness.PLAYER
const FACTION: int = M1Encounter.PLAYER_FACTION

var h: NetHarness


func before_test() -> void:
	h = NetHarness.new(self)


func after_test() -> void:
	await h.free_all()


## A human (desktop) client holding a pick: NetClient's default kind is "bot", which doesn't
## vote.
func _human(server: NetServer, seat: String) -> NetClient:
	var c: NetClient = h.client(server, seat)
	c.client_kind = "desktop"
	await h.until(c.is_welcomed)
	await h.pick(c, seat, PLAYER)
	return c


## A started ship with the three crew seats and a viewer, all human, in a gap the director
## announced.
func _in_gap(server: NetServer) -> Array[NetClient]:
	var crew: Array[NetClient] = []
	for seat: String in ["tactical", "systems", "ops"]:
		crew.append(await _human(server, seat))
	var viewer: NetClient = await _human(server, StationCatalogue.VIEWER)
	assert_bool(await h.start(server, crew[0])).is_true()
	var gap: SetFlagCommand = SetFlagCommand.new()
	gap.flag_name = Director.gap_flag(FACTION)
	gap.value = server.world.tick + 60 * 600
	server.world.submit(gap)
	crew.append(viewer)
	return crew


func _skip(server: NetServer) -> int:
	return server.world.story_flags.get_flag(Director.skip_flag(FACTION))


# FT: FT-MIS-025
# Every crew player gets the `gap` event with the three of them as voters (not the viewer, who
# gets it too but has no vote); all three Ready ends it through the skip flag.
func test_all_crew_ready_skips_the_gap() -> void:
	var server: NetServer = h.server()
	var all: Array[NetClient] = await _in_gap(server)
	var e: Dictionary = await h.next_event(
		all[3],
		NetProtocol.EVENT_GAP,
		0,
		func(ev: Dictionary) -> bool: return ev["payload"]["ends_at"] > 0
	)
	assert_int((e["payload"]["voters"] as Array).size()).is_equal(3)
	var viewer: int = h.session_of(server, all[3]).id
	assert_bool(Array(e["payload"]["voters"]).has(viewer)).is_false()
	for i: int in 3:
		all[i].skip_gap(true)
	assert_bool(await h.until(func() -> bool: return _skip(server) > 0)).is_true()


# FT: FT-MIS-025
# One crew player not Ready keeps the gap; the viewer's Ready is refused (`not_crew`).
func test_a_missing_player_keeps_the_gap_and_viewers_are_refused() -> void:
	var server: NetServer = h.server()
	var all: Array[NetClient] = await _in_gap(server)
	await h.next_event(
		all[0],
		NetProtocol.EVENT_GAP,
		0,
		func(ev: Dictionary) -> bool: return ev["payload"]["ends_at"] > 0
	)
	var from: int = h.mark(all[3])
	all[0].skip_gap(true)
	all[1].skip_gap(true)
	all[3].skip_gap(true)
	var refused: Dictionary = await h.next_event(
		all[3],
		NetProtocol.EVENT_REQUEST_REJECTED,
		from,
		func(ev: Dictionary) -> bool: return ev["payload"]["request"] == NetProtocol.Type.SKIP_GAP
	)
	assert_str(str(refused["payload"]["reason"])).is_equal(NetGame.NOT_CREW)
	var two: Dictionary = await h.next_event(
		all[0],
		NetProtocol.EVENT_GAP,
		0,
		func(ev: Dictionary) -> bool: return (ev["payload"]["ready"] as Array).size() == 2
	)
	assert_bool(two.is_empty()).is_false()
	await h.wait(300)
	assert_int(_skip(server)).is_equal(0)
	# The gap ends: Ready clears and the clients hear it.
	var end: SetFlagCommand = SetFlagCommand.new()
	end.flag_name = Director.gap_flag(FACTION)
	end.value = 0
	server.world.submit(end)
	var over: Dictionary = await h.next_event(
		all[1],
		NetProtocol.EVENT_GAP,
		0,
		func(ev: Dictionary) -> bool: return ev["payload"]["ends_at"] == 0
	)
	assert_bool(over.is_empty()).is_false()
