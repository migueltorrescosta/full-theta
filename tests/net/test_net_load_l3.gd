extends GdUnitTestSuite
## L3 (#11 load gate, D160): the 64-connection session cap in a 6-ship setup, with real
## clients over loopback. The 6 crewable ships come from LoadEncounter (`--load-ships`,
## dev and test only) until the multi-ship lobby lands; the 64 seats follow the load
## gate's plan (LoadSeats: 36 crew, 6 Captains, 22 viewers). The timed load run itself
## is tools/l4/load.sh (gate.sh l4load).

const SHIPS: int = 6

var h: NetHarness


func before_test() -> void:
	h = NetHarness.new(self)


func after_test() -> void:
	await h.free_all()


func _server() -> NetServer:
	var s: NetServer = NetServer.new()
	var enc: LoadEncounter = LoadEncounter.new(
		5, "test", TestDefs.corvette(), TestDefs.raider_enemy(), SHIPS, 2 * SHIPS
	)
	assert_int(s.start(enc, 0, "127.0.0.1")).is_equal(OK)
	add_child(s)
	h.servers.append(s)
	return s


# FT: FT-NET-014, FT-GEN-003, FT-TST-011
# Six crewable ships; 64 connections take every seat of the plan (crew, Captains and
# viewers on all six ships, each picked), every ship passes coverage, and connection 65
# is refused with "session full" without taking a session.
func test_connection_65_is_refused_in_a_six_ship_session() -> void:
	var server: NetServer = _server()
	assert_int(server.session.crew_ships().size()).is_equal(SHIPS)
	var all: Array[NetClient] = []
	for i: int in LoadSeats.CONNECTIONS:
		all.append(h.client(server, "load%02d" % i))
	var all_in: Callable = func() -> bool:
		return all.all(func(c: NetClient) -> bool: return c.is_welcomed())
	assert_bool(await h.until(all_in, 30_000)).is_true()
	for i: int in all.size():
		var seat: Array = LoadSeats.seat(i, SHIPS)
		all[i].pick(seat[0], seat[1])
	var picked: Callable = func() -> bool:
		return all.all(
			func(c: NetClient) -> bool:
				return not h.events_of(c, NetProtocol.EVENT_PICKED).is_empty()
		)
	assert_bool(await h.until(picked, 30_000)).is_true()
	var entries: Dictionary = {}
	for c: NetClient in all:
		var answer: Dictionary = h.events_of(c, NetProtocol.EVENT_PICKED)[-1]
		assert_str(answer["payload"]["reason"]).is_equal("")
		var key: String = answer["payload"]["entry"]
		entries[key] = int(entries.get(key, 0)) + 1
	(
		assert_dict(entries)
		. is_equal(
			{
				"helm": 6,
				"weapons": 6,
				"engineering": 6,
				"science": 6,
				"relay": 6,
				"comms": 6,
				"captain": 6,
				"viewer": 22,
			}
		)
	)
	for ship: int in SHIPS:
		assert_bool(server.session.lobby_state(ship)["ready"]).is_true()
	var late: NetClient = h.client(server, "load64")
	var refused: Callable = func() -> bool: return late.state == NetClient.State.REJECTED
	assert_bool(await h.until(refused)).is_true()
	assert_str(late.reject_reason).is_equal(NetProtocol.REJECT_FULL)
	assert_int(server.session.by_id.size()).is_equal(LoadSeats.CONNECTIONS)
