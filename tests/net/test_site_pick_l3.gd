extends GdUnitTestSuite
## L3 tests of the crew-chosen sites on the wire (E2, w-bzx, NetSkipGap): during a quiet gap
## the `gap` event carries the driver's offers, the pick and the pickers (the human Captain, or
## with none the human Comms players); SitePick from a picker sets Director.pick_flag through a
## logged SetFlagCommand, anything else is refused. The driver is a stub, so these hold
## whatever the director offers.

const PLAYER: int = NetHarness.PLAYER
const FACTION: int = M1Encounter.PLAYER_FACTION

var h: NetHarness


## A driver whose every gap offers the same three sites.
class ThreeOffers:
	extends RunDriver

	func site_offers(_faction: int) -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		for i: int in 3:
			(
				out
				. append(
					{
						"site": 10 + i,
						"name_key": "site.vesper_beacon",
						"scenario": &"wave",
						"risk": i,
						"reward": 2 - i,
					}
				)
			)
		return out


func before_test() -> void:
	h = NetHarness.new(self)


func after_test() -> void:
	await h.free_all()


func _server() -> NetServer:
	var server: NetServer = h.server()
	server.driver_factory = func(_preset: StringName) -> RunDriver: return ThreeOffers.new()
	return server


## A client holding `seat`; human (desktop) unless `bot`.
func _joined(server: NetServer, seat: String, bot: bool = false) -> NetClient:
	var c: NetClient = h.client(server, seat)
	if not bot:
		c.client_kind = "desktop"
	await h.until(c.is_welcomed)
	await h.pick(c, seat, PLAYER)
	return c


func _open_gap(server: NetServer) -> void:
	var gap: SetFlagCommand = SetFlagCommand.new()
	gap.flag_name = Director.gap_flag(FACTION)
	gap.value = server.world.tick + 60 * 600
	server.world.submit(gap)


## The payload of the first `gap` event of an open gap with that pick, {} on a timeout.
func _gap_payload(c: NetClient, pick: int = 0) -> Dictionary:
	var e: Dictionary = await h.next_event(
		c,
		NetProtocol.EVENT_GAP,
		0,
		func(ev: Dictionary) -> bool:
			return ev["payload"]["ends_at"] > 0 and ev["payload"]["pick"] == pick
	)
	return e.get("payload", {})


## The reason SitePick from `c` is refused for.
func _refused(c: NetClient, offer: int) -> String:
	var from: int = h.mark(c)
	c.site_pick(offer)
	var e: Dictionary = await h.next_event(
		c,
		NetProtocol.EVENT_REQUEST_REJECTED,
		from,
		func(ev: Dictionary) -> bool: return ev["payload"]["request"] == NetProtocol.Type.SITE_PICK
	)
	return str(e.get("payload", {}).get("reason", ""))


func _pick(server: NetServer) -> int:
	return server.world.story_flags.get_flag(Director.pick_flag(FACTION))


# FT: FT-MIS-025
# With a Captain seated, only the Captain picks: the payload names them alone and carries the
# offers without the scenario; Comms, a viewer and a bad index are refused; the Captain's pick
# sets the flag through a logged command and comes back as the payload's pick.
func test_the_captain_picks_and_everyone_else_is_refused() -> void:
	var server: NetServer = _server()
	var crew: Array[NetClient] = []
	for seat: String in ["tactical", "systems", "ops"]:
		crew.append(await _joined(server, seat))
	var captain: NetClient = await _joined(server, StationCatalogue.CAPTAIN)
	var viewer: NetClient = await _joined(server, StationCatalogue.VIEWER)
	assert_bool(await h.start(server, crew[0])).is_true()
	_open_gap(server)
	var p: Dictionary = await _gap_payload(crew[2])
	assert_array(p["pickers"]).is_equal([h.session_of(server, captain).id])
	assert_int(p["pick"]).is_equal(0)
	assert_int((p["offers"] as Array).size()).is_equal(3)
	assert_dict(p["offers"][2]).is_equal(
		{"site": 12, "name_key": "site.vesper_beacon", "risk": 2, "reward": 0}
	)
	assert_str(await _refused(crew[2], 1)).is_equal(NetGame.NOT_CREW)
	assert_str(await _refused(viewer, 1)).is_equal(NetGame.NOT_CREW)
	assert_str(await _refused(captain, 3)).is_equal(NetSkipGap.BAD_OFFER)
	assert_str(await _refused(captain, -1)).is_equal(NetSkipGap.BAD_OFFER)
	assert_int(_pick(server)).is_equal(0)
	captain.site_pick(2)
	assert_bool(await h.until(func() -> bool: return _pick(server) == 3)).is_true()
	var logged: bool = false
	for c: SimCommand in server.world.command_log:
		if c is SetFlagCommand and (c as SetFlagCommand).flag_name == Director.pick_flag(FACTION):
			logged = (c as SetFlagCommand).value == 3
	assert_bool(logged).is_true()
	assert_bool((await _gap_payload(viewer, 2)).is_empty()).is_false()


# FT: FT-MIS-025
# With no human Captain seated (a bot Captain doesn't count), the human Comms player picks and
# the bot is refused; outside a gap SitePick is refused `no_gap`.
func test_comms_picks_with_no_human_captain_and_not_outside_a_gap() -> void:
	var server: NetServer = _server()
	var crew: Array[NetClient] = []
	for seat: String in ["tactical", "systems", "ops"]:
		crew.append(await _joined(server, seat))
	var bot: NetClient = await _joined(server, StationCatalogue.CAPTAIN, true)
	assert_bool(await h.start(server, crew[0])).is_true()
	assert_str(await _refused(crew[2], 0)).is_equal(NetSkipGap.NO_GAP)
	_open_gap(server)
	var p: Dictionary = await _gap_payload(crew[0])
	assert_array(p["pickers"]).is_equal([h.session_of(server, crew[2]).id])
	assert_str(await _refused(bot, 1)).is_equal(NetGame.NOT_CREW)
	crew[2].site_pick(1)
	assert_bool(await h.until(func() -> bool: return _pick(server) == 2)).is_true()
