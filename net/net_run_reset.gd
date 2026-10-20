class_name NetRunReset
extends RefCounted
## The run reset (T058, FT-M1-012, D178). When the sim gives a crewed ship its outcome,
## every session with a pick on that ship gets `run_over` (win or loss, run time, hull)
## and the current `run_votes`; a session that picks the ship or reconnects later gets
## them too. Each connected crew player of the ship casts or withdraws a "Run again"
## vote (RunAgain), with the abandon vote's rule (NetAbandonVote: more than half of the
## connected crew); the host's vote resets at once. The reset calls `rebuild`
## (NetServer.restart_run): a world built from scratch, every ship back in the lobby
## with its picks, crew state cleared (ServerSession.restart); the crew presses Start
## again. In M1 the reset is world-wide (one crewed ship); #11 decides it per ship.
## A voter who drops loses the vote, as in D128.

const NOT_OVER: String = "not_over"

var session: ServerSession
## Ship -> its `run_over` payload, from its outcome until the reset.
var over: Dictionary[int, Dictionary] = {}
## Ship -> its "Run again" votes.
var votes: Dictionary[int, NetAbandonVote] = {}

var _rebuild: Callable
## Session id -> the connection and ship its card was last sent to.
var _told: Dictionary[int, Vector2i] = {}
## Ship -> the `run_votes` payload last sent.
var _sent_votes: Dictionary[int, Dictionary] = {}


func _init(server_session: ServerSession, rebuild: Callable) -> void:
	session = server_session
	_rebuild = rebuild
	session.add_handler(NetProtocol.Type.RUN_AGAIN, _on_run_again)


## After the sim stepped: a crewed ship's outcome ends its run.
func after_ticks(events: Array[SimEvent]) -> void:
	for e: SimEvent in events:
		if e.kind != &"outcome" or session.world.ai.is_enabled(e.ship_id):
			continue
		var hull: float = DamageSystem.hull_fraction(session.world, e.ship_id)
		over[e.ship_id] = {
			"ship": e.ship_id,
			"outcome": String(e.tag),
			"time_s": e.tick * SimWorld.DT,
			"hull": clampf(hull, 0.0, 1.0),
		}
		votes[e.ship_id] = NetAbandonVote.new()


## Every frame, after ServerSession.process(): drops the votes of crew who left (and
## sends the votes when they or the votes needed changed), and sends the card to every
## pick on a finished ship that hasn't got it on its current connection.
func process() -> void:
	for ship: int in over:
		votes[ship].keep_only(session.connected_crew(ship))
		if _votes_payload(ship) != _sent_votes.get(ship):
			_send_votes(ship)
		for s: NetSession in session.by_id.values():
			var key: Vector2i = Vector2i(s.conn, ship)
			if s.ship == ship and s.has_pick() and s.connected() and _told.get(s.id) != key:
				_told[s.id] = key
				session.notify(s, NetProtocol.EVENT_RUN_OVER, over[ship])
				session.notify(s, NetProtocol.EVENT_RUN_VOTES, _votes_payload(ship))


func _on_run_again(conn: int, msg: Dictionary, _now_us: int) -> void:
	var s: NetSession = session.by_conn.get(conn)
	if s == null:
		return
	var ship: int = msg["ship"]
	var members: Array[int] = session.connected_crew(ship)
	var why: String = ""
	if not over.has(ship):
		why = NOT_OVER
	elif not s.is_host and not members.has(s.id):
		why = ServerSession.NOT_CREW
	if why != "":
		session.request_rejected(s, NetProtocol.Type.RUN_AGAIN, why, {"ship": ship})
		return
	if s.is_host and msg["vote"]:
		_reset()
		return
	var vote: NetAbandonVote = votes[ship]
	vote.cast(s.id, s.name, msg["vote"])
	vote.keep_only(members)
	_send_votes(ship)
	if vote.passes(members.size()):
		_reset()


func _reset() -> void:
	over.clear()
	votes.clear()
	_told.clear()
	_sent_votes.clear()
	_rebuild.call()


func _votes_payload(ship: int) -> Dictionary:
	return {
		"ship": ship,
		"voters": votes[ship].names(),
		"sessions": votes[ship].sessions(),
		"needed": NetAbandonVote.needed(session.connected_crew(ship).size()),
	}


func _send_votes(ship: int) -> void:
	_sent_votes[ship] = _votes_payload(ship)
	for s: NetSession in session.by_id.values():
		if s.ship == ship and s.has_pick():
			session.notify(s, NetProtocol.EVENT_RUN_VOTES, _sent_votes[ship])
