extends GdUnitTestSuite
## L3 tests of abandoning the run outside a pause (D241, Q13): the co-op host abandons at
## once, or the ship's connected crew vote by more than half; the run then ends with
## `run_over` and the debrief. Refused when the ship is not in a run; in PvP it is a forfeit
## (test_fleet_pause_l3.gd).

const PLAYER: int = NetHarness.PLAYER
const SECRET: String = "c0ffee"

var h: NetHarness


func before_test() -> void:
	h = NetHarness.new(self)


func after_test() -> void:
	await h.free_all()


## A started co-op ship: the host on Tactical, Systems and Ops after it.
func _running(server: NetServer) -> Array[NetClient]:
	var crew: Array[NetClient] = []
	var host: NetClient = await h.welcomed(server, "tactical", "", SECRET)
	await h.pick(host, "tactical", PLAYER)
	crew.append(host)
	for entry: String in ["systems", "ops"]:
		crew.append(await h.joined(server, entry, entry))
	assert_bool(await h.start(server, host)).is_true()
	return crew


func _rejected(c: NetClient, type: int, from: int) -> String:
	var e: Dictionary = await h.next_event(
		c,
		NetProtocol.EVENT_REQUEST_REJECTED,
		from,
		func(ev: Dictionary) -> bool: return ev["payload"]["request"] == type
	)
	return "" if e.is_empty() else str(e["payload"]["reason"])


## The run ended: `run_over` (a loss) and the debrief (abandoned) reached the client.
func _ended(c: NetClient, from: int) -> bool:
	var over: Dictionary = await h.next_event(c, NetProtocol.EVENT_RUN_OVER, from)
	var debrief: Dictionary = await h.next_event(c, NetProtocol.EVENT_DEBRIEF, from)
	return (
		not over.is_empty()
		and over["payload"]["outcome"] == "loss"
		and not debrief.is_empty()
		and debrief["payload"]["result"] == "abandoned"
	)


# FT: FT-MIS-016
# The host abandons the run at once: every client hears `abandoned` by the host, the sim
# marks the ship ABANDONED and the crew gets the outcome card and the debrief.
func test_host_abandons_at_once() -> void:
	var server: NetServer = h.server(false, 10.0, SECRET)
	var crew: Array[NetClient] = await _running(server)
	var from: int = h.mark(crew[1])
	crew[0].abandon(PLAYER)
	var gone: Dictionary = await h.next_event(crew[1], NetProtocol.EVENT_ABANDONED, from)
	assert_str(gone["payload"]["by"]).is_equal("host")
	assert_bool(await _ended(crew[1], from)).is_true()
	assert_int(server.world.run.status[PLAYER]).is_equal(RunTable.Status.ABANDONED)


# FT: FT-MIS-016
# More than half of the connected crew (2 of 3) abandon the run; one vote does not, and
# a withdrawn vote does not count.
func test_passing_vote_abandons() -> void:
	var server: NetServer = h.server(false, 10.0, SECRET)
	var crew: Array[NetClient] = await _running(server)
	var from: int = h.mark(crew[2])
	crew[1].vote_abandon(PLAYER, true)
	var votes: Dictionary = await h.next_event(crew[2], NetProtocol.EVENT_ABANDON_VOTES, from)
	assert_int(votes["payload"]["voters"].size()).is_equal(1)
	assert_int(votes["payload"]["needed"]).is_equal(2)
	assert_int(server.world.run.status[PLAYER]).is_equal(RunTable.Status.IN_PLAY)
	crew[2].vote_abandon(PLAYER, true)
	var gone: Dictionary = await h.next_event(crew[2], NetProtocol.EVENT_ABANDONED, from)
	assert_str(gone["payload"]["by"]).is_equal("vote")
	assert_bool(await _ended(crew[2], from)).is_true()
	assert_int(server.world.run.status[PLAYER]).is_equal(RunTable.Status.ABANDONED)


# FT: FT-MIS-016
# A vote withdrawn does not count: with one vote standing of three, the run goes on.
func test_failing_vote_keeps_the_run() -> void:
	var server: NetServer = h.server(false, 10.0, SECRET)
	var crew: Array[NetClient] = await _running(server)
	var from: int = h.mark(crew[2])
	crew[1].vote_abandon(PLAYER, true)
	crew[1].vote_abandon(PLAYER, false)
	crew[2].vote_abandon(PLAYER, true)
	var last: Callable = func(ev: Dictionary) -> bool: return ev["payload"]["voters"].size() == 1
	var seen: Dictionary = await h.next_event(crew[2], NetProtocol.EVENT_ABANDON_VOTES, from, last)
	assert_bool(seen.is_empty()).is_false()
	await h.wait(300)
	assert_bool(h.events_of(crew[2], NetProtocol.EVENT_ABANDONED).is_empty()).is_true()
	assert_int(server.world.run.status[PLAYER]).is_equal(RunTable.Status.IN_PLAY)


# FT: FT-MIS-016
# Not in a run (nothing started): the host's Abandon and a vote are refused.
func test_refused_when_not_in_a_run() -> void:
	var server: NetServer = h.server(false, 10.0, SECRET)
	var host: NetClient = await h.welcomed(server, "tactical", "", SECRET)
	await h.pick(host, "tactical", PLAYER)
	var from: int = h.mark(host)
	host.abandon(PLAYER)
	assert_str(await _rejected(host, NetProtocol.Type.ABANDON, from)).is_equal("not_in_run")
	host.vote_abandon(PLAYER, true)
	assert_str(await _rejected(host, NetProtocol.Type.ABANDON_VOTE, from)).is_equal("not_in_run")


# FT: FT-MIS-016
# Only the host abandons at once; a crew player is refused `not_host`.
func test_crew_cannot_abandon_alone() -> void:
	var server: NetServer = h.server(false, 10.0, SECRET)
	var crew: Array[NetClient] = await _running(server)
	var from: int = h.mark(crew[1])
	crew[1].abandon(PLAYER)
	assert_str(await _rejected(crew[1], NetProtocol.Type.ABANDON, from)).is_equal("not_host")
	assert_int(server.world.run.status[PLAYER]).is_equal(RunTable.Status.IN_PLAY)
