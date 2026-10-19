extends GdUnitTestSuite
## L3 tests of the run reset (T058, D178): after an outcome every pick on the ship gets
## the outcome card and the "Run again" votes; more than half of the connected crew, or
## the host alone, resets the run: a world built from scratch, marks and alert cleared,
## picks and claims kept, the ship back in the lobby until Start is pressed again.

const PLAYER: int = NetHarness.PLAYER
const ENEMY: int = NetHarness.ENEMY
const SECRET: String = "s3cret"

var h: NetHarness


func before_test() -> void:
	h = NetHarness.new(self)


func after_test() -> void:
	await h.free_all()


## Ends the run: a hit no ship survives destroys `ship`; the sim gives the outcome on
## its next tick.
func _destroy(server: NetServer, ship: int) -> void:
	var hit: SimHit = SimHit.new()
	hit.target_id = ship
	hit.source_id = ENEMY if ship == PLAYER else PLAYER
	DamageSystem.apply_hit(server.world, hit, 1.0e15)


func _voters(e: Dictionary) -> Array:
	return e["payload"]["voters"] if not e.is_empty() else ["(none)"]


# FT: FT-M1-012
# A win: every pick on the ship (crew and viewer) gets the card; crew vote and withdraw
# (a viewer can't); 2 of 3 crew votes rebuild the world (fresh command log, enemy back,
# marks and alert cleared) and put the ship back in the lobby with picks and claims
# kept; snapshots go on (full) and Start starts the new run.
func test_win_then_crew_vote_resets_the_run() -> void:
	var server: NetServer = h.server()
	var crew: Array[NetClient] = await h.crew3(server)
	var viewer: NetClient = await h.joined(server, "viewer", "viewer")
	assert_bool(await h.start(server, crew[0])).is_true()
	var tac: NetSession = h.session_of(server, crew[0])
	crew[2].place_mark(-1, "", ENEMY, 0, Vector3.ZERO)
	crew[0].set_alert(2)
	var marked: Callable = func() -> bool:
		return (
			server.session.marks.marks_of(PLAYER).size() == 1
			and server.session.marks.alert(PLAYER) == 2
		)
	assert_bool(await h.until(marked)).is_true()
	var old_world: SimWorld = server.world
	var from: int = h.mark(viewer)
	var crew_from: Array[int] = []
	for c: NetClient in crew:
		crew_from.append(h.mark(c))
	_destroy(server, ENEMY)
	var card: Dictionary = await h.next_event(viewer, NetProtocol.EVENT_RUN_OVER, from)
	assert_str(card["payload"]["outcome"]).is_equal("win")
	assert_float(card["payload"]["time_s"]).is_greater(0.0)
	assert_float(card["payload"]["hull"]).is_equal(1.0)
	for i: int in crew.size():
		var got: Dictionary = await h.next_event(crew[i], NetProtocol.EVENT_RUN_OVER, crew_from[i])
		assert_dict(got["payload"]).is_equal(card["payload"])
	var votes: Dictionary = await h.next_event(crew[0], NetProtocol.EVENT_RUN_VOTES, crew_from[0])
	assert_int(votes["payload"]["needed"]).is_equal(2)
	assert_array(_voters(votes)).is_empty()
	# Cast, a viewer's refused vote, withdraw.
	from = h.mark(crew[1])
	crew[0].run_again(PLAYER, true)
	var cast: Callable = func(e: Dictionary) -> bool: return _voters(e) == ["tactical"]
	assert_dict(await h.next_event(crew[1], NetProtocol.EVENT_RUN_VOTES, from, cast)).is_not_empty()
	var vfrom: int = h.mark(viewer)
	viewer.run_again(PLAYER, true)
	var refused: Dictionary = await h.next_event(viewer, NetProtocol.EVENT_REQUEST_REJECTED, vfrom)
	assert_str(refused["payload"]["reason"]).is_equal(ServerSession.NOT_CREW)
	from = h.mark(crew[1])
	crew[0].run_again(PLAYER, false)
	var none: Callable = func(e: Dictionary) -> bool: return _voters(e).is_empty()
	assert_dict(await h.next_event(crew[1], NetProtocol.EVENT_RUN_VOTES, from, none)).is_not_empty()
	assert_object(server.world).is_same(old_world)
	# Two of three: the run resets.
	var old_tick: int = old_world.tick
	var fulls: int = crew[0].view.full_count
	from = h.mark(crew[0])
	crew[0].run_again(PLAYER, true)
	crew[1].run_again(PLAYER, true)
	assert_bool(await h.until(func() -> bool: return server.world != old_world)).is_true()
	var w: SimWorld = server.world
	assert_object(server.session.world).is_same(w)
	assert_int(w.tick).is_equal(0)
	assert_array(w.command_log).is_empty()
	assert_bool(w.kin.is_alive(ENEMY)).is_true()
	assert_int(w.run.outcome[PLAYER]).is_equal(RunTable.Outcome.NONE)
	assert_bool(server.session.sim_running()).is_false()
	var lobby: Callable = func(e: Dictionary) -> bool: return not e["payload"]["started"]
	assert_dict(await h.next_event(crew[0], NetProtocol.EVENT_LOBBY, from, lobby)).is_not_empty()
	var cleared: Callable = func(e: Dictionary) -> bool: return e["payload"]["marks"].is_empty()
	assert_dict(await h.next_event(crew[0], NetProtocol.EVENT_MARKS, from, cleared)).is_not_empty()
	var normal: Callable = func(e: Dictionary) -> bool: return e["payload"]["level"] == 0
	assert_dict(await h.next_event(crew[0], NetProtocol.EVENT_ALERT, from, normal)).is_not_empty()
	for i: int in crew.size():
		assert_str(h.session_of(server, crew[i]).entry).is_equal(["tactical", "systems", "ops"][i])
	assert_int(server.session.claims.holder(PLAYER, "flight")).is_equal(tac.id)
	var fresh: Callable = func() -> bool:
		return crew[0].view.full_count > fulls and crew[0].view.tick < old_tick
	assert_bool(await h.until(fresh)).is_true()
	assert_bool(await h.start(server, crew[0])).is_true()
	assert_bool(w.kin.is_alive(PLAYER)).is_true()


# FT: FT-M1-012
# A loss: RunAgain before the outcome is refused; a voter who drops loses the vote; a
# player who picks the ship after the outcome gets the card; the host resets alone.
func test_loss_then_host_resets_alone() -> void:
	var server: NetServer = h.server(false, 10.0, SECRET)
	var crew: Array[NetClient] = await h.crew3(server)
	var host: NetClient = await h.welcomed(server, "host", "", SECRET)
	assert_bool(await h.pick(host, "viewer")).is_true()
	assert_bool(await h.start(server, crew[0])).is_true()
	var from: int = h.mark(crew[0])
	crew[0].run_again(PLAYER, true)
	var early: Dictionary = await h.next_event(crew[0], NetProtocol.EVENT_REQUEST_REJECTED, from)
	assert_str(early["payload"]["reason"]).is_equal(NetRunReset.NOT_OVER)
	_destroy(server, PLAYER)
	var card: Dictionary = await h.next_event(crew[0], NetProtocol.EVENT_RUN_OVER, from)
	assert_str(card["payload"]["outcome"]).is_equal("loss")
	assert_float(card["payload"]["hull"]).is_equal(0.0)
	# A voter who drops loses the vote; the votes needed follow the connected crew.
	from = h.mark(crew[0])
	crew[1].run_again(PLAYER, true)
	var cast: Callable = func(e: Dictionary) -> bool: return _voters(e) == ["systems"]
	assert_dict(await h.next_event(crew[0], NetProtocol.EVENT_RUN_VOTES, from, cast)).is_not_empty()
	from = h.mark(crew[0])
	await h.drop(server, crew[1])
	var dropped: Callable = func(e: Dictionary) -> bool: return _voters(e).is_empty()
	var after: Dictionary = await h.next_event(crew[0], NetProtocol.EVENT_RUN_VOTES, from, dropped)
	assert_int(after["payload"]["needed"]).is_equal(2)
	# A late pick gets the card.
	var late: NetClient = await h.joined(server, "late", "captain")
	var late_card: Dictionary = await h.next_event(late, NetProtocol.EVENT_RUN_OVER)
	assert_dict(late_card["payload"]).is_equal(card["payload"])
	assert_dict(await h.next_event(late, NetProtocol.EVENT_RUN_VOTES)).is_not_empty()
	# The host alone.
	var old_world: SimWorld = server.world
	from = h.mark(late)
	host.run_again(PLAYER, true)
	assert_bool(await h.until(func() -> bool: return server.world != old_world)).is_true()
	assert_bool(server.world.kin.is_alive(PLAYER)).is_true()
	var lobby: Callable = func(e: Dictionary) -> bool: return not e["payload"]["started"]
	assert_dict(await h.next_event(late, NetProtocol.EVENT_LOBBY, from, lobby)).is_not_empty()
