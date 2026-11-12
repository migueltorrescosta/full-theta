class_name NetRunReset
extends RefCounted
## The run reset (T058, FT-M1-012, D178). When the sim gives a crewed ship its outcome,
## every session with a pick on that ship gets `ship_outcome` (win or loss, run time, hull)
## and the current `run_votes`; a session that picks the ship or reconnects later gets
## them too. Each connected crew player of the ship casts or withdraws a "Run again"
## vote (RunAgain), with the abandon vote's rule (NetVote: more than half of the
## connected crew); the host's vote resets at once. The reset calls `rebuild`
## (NetServer.restart_run): a world built from scratch, every ship back in the lobby
## with its picks, crew state cleared (NetGame.restart); the crew presses Start
## again. The reset is world-wide, so with several ships it waits for the session's end; a
## ship out of play before that is eliminated and may relaunch (NetFleet, #11).
## A voter who drops loses the vote, as in D128.

const NOT_OVER: String = "not_over"

var game: NetGame
## Ship -> its `ship_outcome` payload, from its outcome until the reset.
var over: Dictionary[int, Dictionary] = {}
## Ship -> its "Run again" votes.
var votes: Dictionary[int, NetVote] = {}

## The director's decisions so far (a Callable returning an Array of DirectorDecision), set
## by NetServer; none while no director runs.
var decisions: Callable
## Ship -> its debrief (RunDebrief.for_ship), built a few ticks after its outcome, so the
## encounter the ship was lost in has been closed by then.
var debriefs: Dictionary[int, Dictionary] = {}

var _rebuild: Callable
## Session id -> the connection and ship its card was last sent to.
var _told: Dictionary[int, Vector2i] = {}
## Ship -> the `run_votes` payload last sent.
var _sent_votes: Dictionary[int, Dictionary] = {}
## Ship -> the tick of its outcome, until its debrief is built.
var _outcome_tick: Dictionary[int, int] = {}
## Session id -> the connection and ship its debrief was last sent to.
var _told_debrief: Dictionary[int, Vector2i] = {}


func _init(net_game: NetGame, rebuild: Callable) -> void:
	game = net_game
	_rebuild = rebuild
	game.add_handler(NetProtocol.Type.RUN_AGAIN, _on_run_again)


## After the sim stepped: a crewed ship's outcome ends its run.
func after_ticks(events: Array[SimEvent]) -> void:
	for e: SimEvent in events:
		if e.kind != &"outcome" or game.world.ai.is_enabled(e.ship_id):
			continue
		var hull: float = DamageSystem.hull_fraction(game.world, e.ship_id)
		over[e.ship_id] = {
			"ship": e.ship_id,
			"outcome": String(e.tag),
			"time": e.tick * SimWorld.DT,
			"hull": clampf(hull, 0.0, 1.0),
		}
		votes[e.ship_id] = NetVote.new()
		_outcome_tick[e.ship_id] = e.tick


## Every frame, after NetGame.process(): drops the votes of crew who left (and
## sends the votes when they or the votes needed changed), and sends the card to every
## pick on a finished ship that hasn't got it on its current connection.
func process() -> void:
	for ship: int in over:
		_build_debrief(ship)
		votes[ship].keep_only(game.connected_crew(ship))
		if _votes_payload(ship) != _sent_votes.get(ship):
			_send_votes(ship)
		for s: NetSession in game.by_id.values():
			if not (s.on_ship(ship) and s.connected()):
				continue
			var key: Vector2i = Vector2i(s.conn, ship)
			if _told.get(s.id) != key:
				_told[s.id] = key
				game.notify(s, NetProtocol.EVENT_SHIP_OUTCOME, over[ship])
				game.notify(s, NetProtocol.EVENT_RUN_VOTES, _votes_payload(ship))
			if debriefs.has(ship):
				if _told_debrief.get(s.id) != key:
					_told_debrief[s.id] = key
					game.notify(s, NetProtocol.EVENT_DEBRIEF, debriefs[ship])


func _on_run_again(s: NetSession, msg: Dictionary, _now_us: int) -> void:
	var ship: int = msg["ship"]
	var members: Array[int] = game.connected_crew(ship)
	var why: String = ""
	# Several ships: the world-wide reset waits for the session's end (#11; a ship out of play
	# meanwhile is eliminated or relaunched, NetFleet).
	if not over.has(ship) or (game.crew_ships().size() > 1 and not game.fleet.is_over()):
		why = NOT_OVER
	elif not s.is_host and not members.has(s.id):
		why = NetGame.NOT_CREW
	if game.refuse(s, NetProtocol.Type.RUN_AGAIN, why, {"ship": ship}):
		return
	if s.is_host and msg["vote"]:
		_reset()
		return
	var passes: bool = votes[ship].cast_from(s, msg["vote"], members)
	_send_votes(ship)
	if passes:
		_reset()


func _reset() -> void:
	over.clear()
	votes.clear()
	_told.clear()
	_sent_votes.clear()
	debriefs.clear()
	_outcome_tick.clear()
	_told_debrief.clear()
	_rebuild.call()


func _votes_payload(ship: int) -> Dictionary:
	return votes[ship].payload(ship, game.connected_crew(ship).size())


## run_votes to every pick on the ship, through the shared vote path (NetGame.send_votes).
func _send_votes(ship: int) -> void:
	var to: PackedInt32Array = game.audience(func(s: NetSession) -> bool: return s.on_ship(ship))
	var n: int = game.connected_crew(ship).size()
	_sent_votes[ship] = game.send_votes(NetProtocol.EVENT_RUN_VOTES, ship, votes[ship], n, to)


## Builds the ship's debrief once two ticks have passed since its outcome (EncounterSystem
## closes the encounter a ship was lost in on the tick after OutcomeSystem), and writes it to
## the server log as `debrief` (the bot batch and #13 read it).
func _build_debrief(ship: int) -> void:
	if debriefs.has(ship) or game.world.tick < _outcome_tick.get(ship, 0) + 2:
		return
	var list: Array = decisions.call() if decisions.is_valid() else []
	var record: RunDebrief = RunDebrief.new(game.world, list, game.coop, game.first_use)
	debriefs[ship] = record.for_ship(ship)
	if game.server_log != null:
		game.server_log.event("debrief", {"ship": ship, "debrief": debriefs[ship]})
