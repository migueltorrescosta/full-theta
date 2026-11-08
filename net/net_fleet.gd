class_name NetFleet
extends RefCounted
## The multi-ship lobby and the PvP session rules on the server (#11, E11, E12; owner M4-Q2 to
## M4-Q10, 2026-10-28; docs/protocol.md "Multi-ship sessions and PvP"). ServerSession owns one
## and registers its handlers. It holds the lobby's ships (ShipSlot) and the host's
## SessionRules, answers ShipAdd, ShipTeam, SessionMode and Relaunch, and sends the `fleet`,
## `takeover`, `handover`, `scoreboard`, `eliminated`, `relaunch_votes`, `relaunched` and
## `session_over` events (FleetMessages).
## - Lobby: ShipAdd (any player, up to SessionRules.MAX_SHIPS), ShipTeam (a session on the
##   ship, teams and holdout only) and SessionMode (the host) change the ships while no ship
##   has started. Each change rebuilds a lobby world of allied placeholder ships, one per slot
##   with stable ids (`rebuild`, NetServer.rebuild_fleet), and sends the Catalogue again.
## - Start: the universe starts once every crewed ship has pressed Start and passes coverage
##   (press_start, M4-Q4). The world is then built from start_slots(), the ships with a crew
##   pick in lobby order, with the mode's factions and teams; a ship nobody crewed vanishes and
##   its sessions are moved to the new ids (M4-Q3).
## - Elimination: the sim's &"eliminated" event for a started ship (destroyed, abandoned, or
##   forfeited by the abandon vote in PvP, M4-Q10; the event carries the reason and the lives
##   left, F5) becomes the `eliminated` event; HANDOVER_DELAY_TICKS later,
##   unless the session is over, its sessions view a surviving friendly ship's main screen or
##   go to the scoreboard (destination_of, FT-MIS-030, D91).
## - Relaunch: the eliminated ship's connected crew vote by majority while it has lives left
##   (M4-Q2); the vote sends RelaunchShipCommand, the sim alone checks the side's policy, and its
##   &"relaunched" event puts the crew back on their stations (`relaunched`); a rejected
##   command is refused `no_relaunch` to the voters.
## - Takeover in a pause (takeover_rule, M4-Q8, FT-NET-042).
## - Scoreboard: rows to the sessions without a pick once the universe started (M4-Q9).
## A world NetServer can't rebuild (the M1 and load encounters) keeps its fixed ships: the
## lobby requests are refused `lobby_closed`, the rest applies.

## Sim events the M4 rules emit (SessionOutcome) that NetFleet turns into its own events of the
## same names: the raw sim events go to nobody.
const OWN_EVENTS: Array[StringName] = [
	SessionOutcome.EVENT_ELIMINATED,
	SessionOutcome.EVENT_RELAUNCHED,
	SessionOutcome.EVENT_SESSION_OVER,
]
## Ticks between an elimination and its handover, so that a session the elimination ends
## (its outcome comes from the same tick's run state) keeps its crews for the debrief.
const HANDOVER_DELAY_TICKS: int = 2
## A scoreboard whose rows changed only in their times goes out at most once a second.
const SCOREBOARD_EVERY_TICKS: int = SimRate.HZ
## While the universe runs, the `fleet` event is checked at most every half second.
const FLEET_EVERY_TICKS: int = SimRate.HZ / 2

var session: ServerSession:
	get:
		return _session.get_ref() as ServerSession
## The lobby's ships, by ship id (slot order).
var slots: Array[ShipSlot] = []
## The host's mode and options.
var rules: SessionRules = SessionRules.new()
## Rebuilds the world from (slots, rules): NetServer.rebuild_fleet. Invalid for a fixed world.
var rebuild: Callable
## Ships whose crew pressed Start, waiting for the others (M4-Q4).
var pressed: Dictionary[int, bool] = {}
## Eliminated ships -> the `eliminated` reason: "destroyed" (the hull reached 0), "abandoned"
## (the crew or host gave up in a pause, FT-NET-041) or "forfeit" (a PvP crew's abandon vote,
## M4-Q10).
var eliminated: Dictionary[int, String] = {}
## The session's outcome once it is over, else null.
var outcome: SessionOutcome
## The tick the universe started.
var start_tick: int = 0

var _session: WeakRef
## Whether the world was built from the current slots and rules (false after a lobby change:
## the lobby world holds placeholders).
var _world_current: bool = true
var _dirty: bool = true
## A lobby change not yet checked (publish).
var _pending: bool = false
var _fleet_tick: int = -FLEET_EVERY_TICKS
## Eliminated ship -> [[session id, entry], ...]: who was on it, for the handover and a relaunch.
var _crews: Dictionary[int, Array] = {}
## Eliminated ship -> the tick of its handover.
var _handover_at: Dictionary[int, int] = {}
var _votes: Dictionary[int, NetVote] = {}
## Eliminated ship -> the relaunches its side has left, as the sim's &"eliminated" or
## &"relaunched" event said.
var _lives: Dictionary[int, int] = {}
var _relaunching: Dictionary[int, RelaunchShipCommand] = {}
var _fleet_sent: Dictionary = {}
var _board_sent: Array = []
var _board_tick: int = -SCOREBOARD_EVERY_TICKS


func _init(server_session: ServerSession) -> void:
	_session = weakref(server_session)
	server_session.add_handler(NetProtocol.Type.SHIP_ADD, _on_ship_add)
	server_session.add_handler(NetProtocol.Type.SHIP_TEAM, _on_ship_team)
	server_session.add_handler(NetProtocol.Type.SESSION_MODE, _on_session_mode)
	server_session.add_handler(NetProtocol.Type.RELAUNCH, _on_relaunch)


## The slots RunSetup builds at Start: those with a crew pick, in lobby order (M4-Q3).
func start_slots() -> Array[ShipSlot]:
	var out: Array[ShipSlot] = []
	for i: int in _kept():
		out.append(slots[i])
	return out


## The run reset (ServerSession.restart): the session's progress goes, the lobby stays.
func reset() -> void:
	pressed.clear()
	eliminated.clear()
	outcome = null
	_crews.clear()
	_handover_at.clear()
	_votes.clear()
	_lives.clear()
	_relaunching.clear()
	_board_sent = []
	_fleet_tick = -FLEET_EVERY_TICKS
	_dirty = true


## A ship's lobby name: its slot's, else `fallback` (a fixed world's ship definition name).
func name_of(ship: int, fallback: String) -> String:
	return slots[ship].name if ship >= 0 and ship < slots.size() else fallback


## A ship's side as the lobby shows it: its slot's team, 0 on a fixed world.
func team_of(ship: int) -> int:
	return slots[ship].team if ship >= 0 and ship < slots.size() else 0


## Whether the session is over (SessionOutcome), so the world-wide "Run again" may follow.
func is_over() -> bool:
	return outcome != null


## The crewed ships not yet ready to start together: a crew pick but no Start pressed, or a
## coverage check that fails again. Empty once the universe started.
func waiting() -> Array[int]:
	var out: Array[int] = []
	if session.lobby.any_launched():
		return out
	for id: int in _crewed():
		if not (
			pressed.has(id)
			and NetCoverage.passes(session.lobby.entries_of(id), session.lobby.min_crew())
		):
			out.append(id)
	return out


## Start pressed by `s`, whose ship passes coverage (ServerSession._on_ready checked it). Returns
## the ships to launch now, all together, or [] while others wait (M4-Q4). With the mode's slot
## errors (SessionRules.slot_errors) the press is refused `bad_mode` with the errors. On a
## fixed world a ship crewed after the universe started starts alone.
func press_start(s: NetSession) -> Array[int]:
	if session.lobby.any_launched():
		return [s.ship]
	pressed[s.ship] = true
	_dirty = true
	if not waiting().is_empty():
		return []
	if rebuild.is_valid():
		var errors: Array[String] = rules.slot_errors(start_slots())
		if not errors.is_empty():
			pressed.erase(s.ship)
			var extra: Dictionary = {"errors": Array(errors)}
			session.refuse(s, NetProtocol.Type.READY, FleetMessages.BAD_MODE, extra)
			return []
		var kept: Array[int] = _kept()
		if not _world_current or kept.size() < slots.size():
			_rebuild_for_start(kept)
	pressed.clear()
	start_tick = session.world.tick
	return _crewed()


## Why `s` may not take over `entry` on the paused `ship`, whose open stations are `uncovered`,
## or "" (M4-Q8, FT-NET-042): the ship's own Captain and viewers, and players of allied ships
## (same faction); enemies never (ENEMY_SHIP); the entry must cover a station still uncovered
## (TAKEN: someone claimed it first); a crew player may not leave if their own ship in play
## would fail coverage (BREAKS_COVERAGE).
func takeover_rule(s: NetSession, ship: int, entry: String, uncovered: Array) -> String:
	var world: SimWorld = session.world
	if not StationViews.is_entry(entry, session.dev_all) or not StationViews.is_crew(entry):
		return ServerSession.BAD_PICK
	if s.ship == ship:
		if s.entry != StationViews.CAPTAIN and s.entry != StationViews.VIEWER:
			return CommandGate.NOT_ALLOWED
	elif not s.has_pick():
		return CommandGate.NOT_ALLOWED
	elif world.faction_of(s.ship) != world.faction_of(ship):
		return FleetMessages.ENEMY_SHIP
	var covers: bool = false
	for station: String in StationViews.stations_of(entry):
		covers = covers or uncovered.has(station)
	if not covers:
		return FleetMessages.TAKEN
	return _leave_rule(s, ship)


## BREAKS_COVERAGE when a crew player leaving their own ship in play for `ship` would make it
## fail the coverage check it passes now (FT-NET-042), else "".
func _leave_rule(s: NetSession, ship: int) -> String:
	if s.ship == ship or not StationViews.is_crew(s.entry) or not session.lobby.in_play(s.ship):
		return ""
	var before: Array = session.lobby.entries_of(s.ship)
	var after: Array = before.duplicate()
	after.erase(s.entry)
	if (
		NetCoverage.passes(before, session.lobby.min_crew())
		and not NetCoverage.passes(after, session.lobby.min_crew())
	):
		return FleetMessages.BREAKS_COVERAGE
	return ""


## A takeover was applied: every session of the ship's side hears who took what (M4-Q8).
func took_over(s: NetSession, ship: int, entry: String, from_ship: int) -> void:
	var world: SimWorld = session.world
	var ids: PackedInt32Array = session.audience(
		func(o: NetSession) -> bool:
			return o.ship >= 0 and world.faction_of(o.ship) == world.faction_of(ship)
	)
	var payload: Dictionary = FleetMessages.takeover(ship, entry, s.name, from_ship)
	session.transport.post_event(ids, world.tick, NetProtocol.EVENT_TAKEOVER, payload)


## Where an eliminated ship's sessions go: the first surviving friendly ship in play, or
## FleetMessages.TO_SCOREBOARD when none is left or the mode sends them there (FT-MIS-030,
## D91, SessionRules.eliminated_to).
func destination_of(ship: int) -> int:
	if rules.eliminated_to == SessionRules.Destination.SCOREBOARD:
		return FleetMessages.TO_SCOREBOARD
	var world: SimWorld = session.world
	for c: Dictionary in session.crew_ships():
		var other: int = c["id"]
		if (
			other != ship
			and session.lobby.in_play(other)
			and world.faction_of(other) == world.faction_of(ship)
		):
			return other
	return FleetMessages.TO_SCOREBOARD


## The live scoreboard's rows, one per started ship: status and progress only (M4-Q9).
func scoreboard_rows() -> Array:
	var world: SimWorld = session.world
	var rows: Array = []
	for c: Dictionary in session.crew_ships():
		var id: int = c["id"]
		if not session.lobby.is_launched(id):
			continue
		var end: int = world.run.finish_tick[id] if world.run.finish_tick[id] >= 0 else world.tick
		var time_s: float = float(end - start_tick) / SimWorld.HZ
		var state: String = FleetMessages.IN_PLAY
		if eliminated.has(id) or world.run.outcome[id] == RunTable.Outcome.LOSS:
			state = FleetMessages.DESTROYED
		elif world.run.outcome[id] == RunTable.Outcome.WIN:
			state = FleetMessages.FINISHED
		var k: int = world.run.kills[id] if rules.is_pvp() else 0
		var done: int = world.run.encounters_done[id]
		rows.append(
			FleetMessages.scoreboard_row(id, c["name"], team_of(id), state, done, time_s, k)
		)
	return rows


## After the sim stepped (ServerSession.after_ticks): eliminations and relaunches from the
## sim's events (F5: the sim owns the reason, the lives left and the relaunch rule), the
## session's outcome, due handovers, refused relaunches and the scoreboard. The outcome is read
## from the run state (OutcomeSystem.session_outcome) rather than the sim's `session_over`
## event, which only a director run emits.
func after_ticks(events: Array[SimEvent]) -> void:
	var world: SimWorld = session.world
	for e: SimEvent in events:
		if not session.lobby.is_launched(e.ship_id):
			continue
		if e.kind == SessionOutcome.EVENT_ELIMINATED and not eliminated.has(e.ship_id):
			_eliminate(e.ship_id, String(e.tag), int(e.value))
		elif e.kind == SessionOutcome.EVENT_RELAUNCHED:
			_relaunched(e.ship_id, int(e.value))
	if outcome == null and session.lobby.any_launched():
		var o: SessionOutcome = OutcomeSystem.session_outcome(world)
		if o.over():
			outcome = o
			var time_s: float = float(world.tick - start_tick) / SimWorld.HZ
			var held_s: float = float(o.held_ticks) / SimRate.HZ
			var reason: String = SessionOutcome.REASON_NAMES[o.reason]
			var payload: Dictionary = FleetMessages.session_over(
				reason, Array(o.winners), o.team, held_s, time_s
			)
			session.broadcast(NetProtocol.EVENT_SESSION_OVER, payload)
	for ship: int in _handover_at.keys():
		if world.tick >= _handover_at[ship]:
			_handover_at.erase(ship)
			if outcome == null:
				_hand_over(ship)
	for ship: int in _relaunching.keys():
		var c: RelaunchShipCommand = _relaunching[ship]
		if c.tick >= 0:
			_relaunching.erase(ship)
			if not c.accepted:
				_refuse_relaunch(ship)
	_send_scoreboard()


## Sends the `fleet` event when it changed (ServerSession._publish, on a lobby change). Once
## the universe runs, a change the sim's events may have made is checked at most every
## FLEET_EVERY_TICKS, so the load stays off the tick (the 64-connection gate, D161).
func publish(lobby_dirty: bool) -> void:
	_pending = _pending or lobby_dirty
	if not _dirty and not _pending:
		return
	var tick: int = session.world.tick
	if not _dirty and session.lobby.any_launched() and tick < _fleet_tick + FLEET_EVERY_TICKS:
		return
	_dirty = false
	_pending = false
	_fleet_tick = tick
	var payload: Dictionary = _fleet_payload()
	if payload != _fleet_sent:
		_fleet_sent = payload
		session.broadcast(NetProtocol.EVENT_FLEET, payload)


## A (re)joining session starts in sync: the `fleet` event, and the scoreboard without a pick.
func send_to(s: NetSession) -> void:
	session.notify(s, NetProtocol.EVENT_FLEET, _fleet_payload())
	if session.lobby.any_launched() and not s.has_pick():
		var payload: Dictionary = FleetMessages.scoreboard(scoreboard_rows())
		session.notify(s, NetProtocol.EVENT_SCOREBOARD, payload)


# --- Handlers. ---


func _on_ship_add(s: NetSession, msg: Dictionary, _now_us: int) -> void:
	var reason: String = _lobby_refusal(s, false)
	if reason == "" and slots.size() >= SessionRules.MAX_SHIPS:
		reason = FleetMessages.FLEET_FULL
	if session.refuse(s, NetProtocol.Type.SHIP_ADD, reason, {"name": msg["name"]}):
		return
	var ship_name: String = msg["name"]  # cleaned by NetProtocol.decode (NAMED)
	if ship_name == "":
		ship_name = "Ship %d" % (slots.size() + 1)
	slots.append(ShipSlot.of(ship_name, SessionRules.CREW_FACTIONS[0], 0))
	_apply(rules.has_teams())


func _on_ship_team(s: NetSession, msg: Dictionary, _now_us: int) -> void:
	var ship: int = msg["ship"]
	var team: int = msg["team"]
	var reason: String = _lobby_refusal(s, false)
	if reason == "" and (ship < 0 or ship >= slots.size() or s.ship != ship):
		reason = ServerSession.NOT_CREW
	elif reason == "" and (not rules.has_teams() or team < 0 or team > 1):
		reason = FleetMessages.BAD_TEAM
	if session.refuse(s, NetProtocol.Type.SHIP_TEAM, reason, {"ship": ship, "team": team}):
		return
	slots[ship].team = team
	_apply(false)


## SessionMode{mode, team_win, lives}: lives -1 keeps the holdout default (HOLDOUT_LIVES).
func _on_session_mode(s: NetSession, msg: Dictionary, _now_us: int) -> void:
	var mode: int = SessionRules.MODE_NAMES.find(msg["mode"])
	var team_win: int = SessionRules.TEAM_WIN_NAMES.find(msg["team_win"])
	var lives: int = msg["lives"]
	var reason: String = _lobby_refusal(s, true)
	if reason == "" and (mode < 0 or team_win < 0 or lives == 0 or lives < -1):
		reason = FleetMessages.BAD_MODE
	var extra: Dictionary = msg.duplicate()
	extra.erase("t")
	if session.refuse(s, NetProtocol.Type.SESSION_MODE, reason, extra):
		return
	var had_teams: bool = rules.has_teams()
	rules = SessionRules.of_mode(mode as SessionRules.Mode)
	rules.team_win = team_win as SessionRules.TeamWin
	if mode == SessionRules.Mode.HOLDOUT and lives > 0:
		rules.relaunch[SessionRules.HOLDOUT_FINITE_TEAM] = RelaunchPolicy.of_lives(lives)
	_apply(rules.has_teams() and not had_teams)


## Relaunch{ship, vote} from the eliminated ship's connected crew (M4-Q2).
func _on_relaunch(s: NetSession, msg: Dictionary, _now_us: int) -> void:
	var ship: int = msg["ship"]
	var members: Array[int] = _voters(ship)
	var reason: String = ""
	# Lives as the sim's events told them (F5): the sim checks the policy again on apply.
	if (
		not eliminated.has(ship)
		or outcome != null
		or _relaunching.has(ship)
		or _lives_left(ship) == 0
	):
		reason = FleetMessages.NO_RELAUNCH
	elif not members.has(s.id):
		reason = ServerSession.NOT_CREW
	if session.refuse(s, NetProtocol.Type.RELAUNCH, reason, {"ship": ship}):
		return
	var vote: NetVote = _votes.get_or_add(ship, NetVote.new())
	var passes: bool = vote.cast_from(s, msg["vote"], members)
	var ids: PackedInt32Array = PackedInt32Array(members)
	session.send_votes(NetProtocol.EVENT_RELAUNCH_VOTES, ship, vote, members.size(), ids)
	if passes:
		_votes.erase(ship)
		var c: RelaunchShipCommand = RelaunchShipCommand.new()
		c.ship = ship
		session.world.submit(c)
		_relaunching[ship] = c


# --- Internals. ---


## Why the lobby can't change now, or "": a fixed world or a started universe (lobby_closed),
## and SessionMode from anyone but the host (not_host).
func _lobby_refusal(s: NetSession, host_only: bool) -> String:
	if not rebuild.is_valid() or session.lobby.any_launched():
		return FleetMessages.LOBBY_CLOSED
	if host_only and not s.is_host:
		return ServerSession.NOT_HOST
	return ""


## After a lobby change: each slot's team and faction follow the mode (one side in co-op,
## one per ship in race and last ship standing, 0 and 1 in teams and holdout, alternating
## when `split` is set), and the lobby world is rebuilt with allied placeholder ships.
func _apply(split: bool) -> void:
	for i: int in slots.size():
		var team: int = 0
		if rules.has_teams():
			team = i % 2 if split or slots[i].team > 1 else slots[i].team
		elif rules.mode != SessionRules.Mode.COOP:
			team = i
		slots[i].team = team
		slots[i].faction = rules.faction_for(i, team)
	var placeholders: Array[ShipSlot] = []
	for s: ShipSlot in slots:
		placeholders.append(ShipSlot.of(s.name, SessionRules.CREW_FACTIONS[0], 0))
	pressed.clear()
	rebuild.call(placeholders, SessionRules.new())
	_world_current = false
	_dirty = true
	_send_catalogue()


## Builds the session's world from the kept slots with the mode's factions; every session moves
## to its ship's new id, or to the pick screen when its ship vanished (M4-Q3).
func _rebuild_for_start(kept: Array[int]) -> void:
	var moves: Array = []
	for s: NetSession in session.by_id.values():
		if s.ship >= 0:
			moves.append([s, kept.find(s.ship), s.entry])
			s.ship = -1
			s.entry = ""
	for s: NetSession in session.sessions.all():
		if s.lapsed:
			s.last_ship = kept.find(s.last_ship)
	var built: Array[ShipSlot] = []
	for i: int in kept:
		built.append(slots[i])
	slots = built
	session.reset_claims()
	rebuild.call(slots, rules)
	_world_current = true
	_send_catalogue()
	for m: Array in moves:
		var ship: int = m[1]
		session.lobby.move(m[0], ship, m[2] if ship >= 0 else "")


## Lobby ids of the slots with a crew pick, ascending.
func _kept() -> Array[int]:
	var out: Array[int] = []
	for i: int in slots.size():
		if NetCoverage.crew_count(session.lobby.entries_of(i)) > 0:
			out.append(i)
	return out


## Crewable ships with a crew pick.
func _crewed() -> Array[int]:
	var out: Array[int] = []
	for c: Dictionary in session.crew_ships():
		if NetCoverage.crew_count(session.lobby.entries_of(c["id"])) > 0:
			out.append(c["id"])
	return out


func _send_catalogue() -> void:
	var bytes: PackedByteArray = session.catalogue()
	for s: NetSession in session.by_id.values():
		if s.connected():
			session.transport.send(s.conn, bytes)


## The relaunches the eliminated ship's side has left, from the sim's last event for it.
func _lives_left(ship: int) -> int:
	return _lives.get(ship, 0)


## A crewed ship left play, with the sim's reason ("destroyed", "abandoned" or "forfeit",
## M4-Q10) and lives left: everyone hears why; its sessions are handed over later.
func _eliminate(ship: int, reason: String, lives: int) -> void:
	eliminated[ship] = reason
	_lives[ship] = lives
	var payload: Dictionary = FleetMessages.eliminated(ship, reason, lives)
	session.broadcast(NetProtocol.EVENT_ELIMINATED, payload)
	var crew: Array = []
	for s: NetSession in session.by_id.values():
		if s.ship == ship and s.has_pick():
			crew.append([s.id, s.entry])
	_crews[ship] = crew
	_handover_at[ship] = session.world.tick + HANDOVER_DELAY_TICKS
	_dirty = true


## The eliminated ship's sessions view a friendly ship's main screen, or go to the scoreboard.
func _hand_over(ship: int) -> void:
	var to: int = destination_of(ship)
	for pair: Array in _crews.get(ship, []):
		var s: NetSession = session.by_id.get(pair[0])
		if s == null or s.ship != ship:
			continue
		# `handover` first, then the `picked` of the move (the client keys its view by ship).
		session.notify(s, NetProtocol.EVENT_HANDOVER, FleetMessages.handover(ship, to))
		session.lobby.move(s, to, StationViews.VIEWER if to >= 0 else "")
	_board_sent = []
	_board_tick = -SCOREBOARD_EVERY_TICKS


## The sim relaunched the ship (its &"relaunched" event, with the lives left): the ship is back
## in play and its crew on their stations.
func _relaunched(ship: int, lives: int) -> void:
	eliminated.erase(ship)
	_handover_at.erase(ship)
	_lives[ship] = lives
	session.lobby.clear_abandoned(ship)
	# The fresh ship starts with fresh crew state, as after a run reset (R17-4): marks, pings,
	# relay zones and routes, open chips, share timers and probe-scan flags of its old life go.
	# (What a rival's KnowledgeTable holds of the ship is left alone: owner call, see the report.)
	session.crew.reset(ship)
	session.chips.reset(ship)
	session.shares.reset(ship)
	session.coop.reset_ship(ship)
	for pair: Array in _crews.get(ship, []):
		var s: NetSession = session.by_id.get(pair[0])
		if s != null:
			session.lobby.move(s, ship, pair[1])
	_crews.erase(ship)
	var payload: Dictionary = FleetMessages.relaunched(ship, lives)
	session.broadcast(NetProtocol.EVENT_RELAUNCHED, payload)
	_dirty = true


## The sim rejected the relaunch the vote sent: its voters hear `no_relaunch`.
func _refuse_relaunch(ship: int) -> void:
	for id: int in _voters(ship):
		var extra: Dictionary = {"ship": ship}
		session.request_rejected(
			session.by_id[id], NetProtocol.Type.RELAUNCH, FleetMessages.NO_RELAUNCH, extra
		)


## Connected crew of the eliminated ship as it was when eliminated: the relaunch voters.
func _voters(ship: int) -> Array[int]:
	var out: Array[int] = []
	for pair: Array in _crews.get(ship, []):
		var s: NetSession = session.by_id.get(pair[0])
		if s != null and s.connected() and StationViews.is_crew(pair[1]):
			out.append(s.id)
	return out


func _fleet_payload() -> Dictionary:
	var ships: Array = []
	for c: Dictionary in session.crew_ships():
		var id: int = c["id"]
		var lobby: Dictionary = session.lobby.lobby_state(id)
		ships.append(
			FleetMessages.fleet_ship(
				id,
				c["name"],
				team_of(id),
				lobby["seats"],
				lobby["crew"],
				Array(lobby["uncovered"]),
				lobby["ready"],
				pressed.has(id) or session.lobby.is_launched(id)
			)
		)
	var lives: int = -1
	if rules.mode == SessionRules.Mode.HOLDOUT:
		lives = rules.relaunch_for(SessionRules.HOLDOUT_FINITE_TEAM).lives
	var started: bool = session.lobby.any_launched()
	var mode: String = SessionRules.MODE_NAMES[rules.mode]
	var team_win: String = SessionRules.TEAM_WIN_NAMES[rules.team_win]
	var max_ships: int = SessionRules.MAX_SHIPS
	return FleetMessages.fleet(ships, mode, team_win, max_ships, lives, Array(waiting()), started)


## The scoreboard to the sessions without a pick: on a change of state or progress, and once a
## second while only the times move.
func _send_scoreboard() -> void:
	var ids: PackedInt32Array = session.audience(
		func(s: NetSession) -> bool: return not s.has_pick() and s.connected()
	)
	if ids.is_empty():
		return
	var rows: Array = scoreboard_rows()
	var tick: int = session.world.tick
	if rows == _board_sent:
		return
	if tick < _board_tick + SCOREBOARD_EVERY_TICKS and _untimed(rows) == _untimed(_board_sent):
		return
	_board_sent = rows
	_board_tick = tick
	var payload: Dictionary = FleetMessages.scoreboard(rows)
	session.transport.post_event(ids, tick, NetProtocol.EVENT_SCOREBOARD, payload)


static func _untimed(rows: Array) -> Array:
	var out: Array = []
	for row: Dictionary in rows:
		var r: Dictionary = row.duplicate()
		r.erase("time_s")
		out.append(r)
	return out
