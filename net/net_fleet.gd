class_name NetFleet
extends RefCounted
## The multi-ship lobby and the PvP game rules on the server (#11, E11, E12; owner M4-Q2 to
## M4-Q10, 2026-10-28; docs/protocol.md "Multi-ship games and PvP"). NetGame owns one
## and registers its handlers. It holds the lobby's ships (ShipSlot) and the host's
## GameRules, answers ShipAdd, ShipTeam, GameMode and Relaunch, and sends the `fleet`,
## `takeover`, `handover`, `scoreboard`, `eliminated`, `relaunch_votes`, `relaunched` and
## `game_over` events (FleetMessages).
## - Lobby: ShipAdd (any player, up to GameRules.MAX_SHIPS), ShipTeam (the host, or a session
##   on the ship; teams and holdout only) and GameMode (the host) change the ships while no ship
##   has started. Each change rebuilds a lobby world of allied placeholder ships, one per slot
##   with stable ids (`rebuild`, NetServer.rebuild_fleet), and sends the Catalogue again.
## - Start: the universe starts all together when the host presses Start, every crewed ship
##   passing coverage and every crew player Ready (NetLobby.start, start_ships, M4-Q4,
##   #37 C1). The world is then built from start_slots(), the ships with a crew pick in lobby
##   order, with the mode's factions and teams; a ship nobody crewed vanishes and
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

## Sim events the M4 rules emit (GameOutcome) that NetFleet turns into its own events of the
## same names: the raw sim events go to nobody.
const OWN_EVENTS: Array[StringName] = [
	GameOutcome.EVENT_ELIMINATED,
	GameOutcome.EVENT_RELAUNCHED,
	GameOutcome.EVENT_GAME_OVER,
]
## Ticks between an elimination and its handover, so that a session the elimination ends
## (its outcome comes from the same tick's run state) keeps its crews for the debrief.
const HANDOVER_DELAY_TICKS: int = 2
## A scoreboard whose rows changed only in their times goes out at most once a second.
const SCOREBOARD_EVERY_TICKS: int = SimRate.HZ
## While the universe runs, the `fleet` event is checked at most every half second.
const FLEET_EVERY_TICKS: int = SimRate.HZ / 2

var game: NetGame:
	get:
		return _game.get_ref() as NetGame
## The lobby's ships, by ship id (slot order).
var slots: Array[ShipSlot] = []
## The host's mode and options.
var rules: GameRules = GameRules.new()
## Rebuilds the world from (slots, rules): NetServer.rebuild_fleet. Invalid for a fixed world.
var rebuild: Callable
## Eliminated ships -> the `eliminated` reason: "destroyed" (the hull reached 0), "abandoned"
## (the crew or host gave up in a pause, FT-NET-041) or "forfeit" (a PvP crew's abandon vote,
## M4-Q10).
var eliminated: Dictionary[int, String] = {}
## The game's outcome once it is over, else null.
var outcome: GameOutcome
## The tick the universe started.
var start_tick: int = 0
## The run modifiers the lobby rolls from (RunModifierDef ids, gp-11): roll_modifiers sets
## them; the host's Reroll picks another (REROLL_MODIFIER).
var modifiers: Array[StringName] = []
var _modifier_rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _game: WeakRef
## Whether the world was built from the current slots and rules (false after a lobby change:
## the lobby world holds placeholders).
var _world_current: bool = true
var _dirty: bool = true
## A lobby change not yet checked (publish).
var _pending: bool = false
var _fleet_tick: int = -FLEET_EVERY_TICKS
## Eliminated ship -> [[session id, seat], ...]: who was on it, for the handover and a relaunch.
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


func _init(net_game: NetGame) -> void:
	_game = weakref(net_game)
	net_game.add_handler(NetProtocol.Type.SHIP_ADD, _on_ship_add)
	net_game.add_handler(NetProtocol.Type.SHIP_TEAM, _on_ship_team)
	net_game.add_handler(NetProtocol.Type.GAME_MODE, _on_game_mode)
	net_game.add_handler(NetProtocol.Type.RELAUNCH, _on_relaunch)
	net_game.add_handler(NetProtocol.Type.REROLL_MODIFIER, _on_reroll_modifier)


## The lobby's run modifier (gp-11): one of `ids` at random from the server seed, or none
## without any; only for a lobby the server rebuilds (a fixed world has no setup to apply it).
## The world is built again at Start with it (GameRules.modifier_id).
func roll_modifiers(ids: Array[StringName], seed_value: int) -> void:
	if not rebuild.is_valid() or ids.is_empty():
		return
	modifiers = ids.duplicate()
	_modifier_rng.seed = seed_value
	rules.modifier_id = modifiers[_modifier_rng.randi_range(0, modifiers.size() - 1)]
	_world_current = false
	_dirty = true


## The slots RunSetup builds at Start: those with a crew pick, in lobby order (M4-Q3).
func start_slots() -> Array[ShipSlot]:
	var out: Array[ShipSlot] = []
	for i: int in _kept():
		out.append(slots[i])
	return out


## The run reset (NetGame.restart): the session's progress goes, the lobby stays.
func reset() -> void:
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


## The lobby team whose ships have `faction` (GameOutcome.winner_faction mapped back for
## the wire, FleetMessages.game_over): -1 for -1 or a faction no slot has. The inverse of
## the team -> faction map RunSetup applies (GameRules.faction_for), so the wire keeps teams.
func team_of_faction(faction: int) -> int:
	return team_for_faction(slots, rules, faction)


## team_of_faction on the given slots (ship id = slot index) and rules.
static func team_for_faction(on: Array[ShipSlot], under: GameRules, faction: int) -> int:
	if faction < 0:
		return -1
	for i: int in on.size():
		if under.faction_for(i, on[i].team) == faction:
			return on[i].team
	return -1


## Whether the session is over (GameOutcome), so the world-wide "Run again" may follow.
func is_over() -> bool:
	return outcome != null


## The crewed ships not yet ready to start together: coverage fails or a crew player is not
## Ready (#37 C1). Empty once the universe started.
func waiting() -> Array[int]:
	var out: Array[int] = []
	if game.lobby.any_launched():
		return out
	for id: int in crewed():
		if not game.lobby.covered(id) or not game.lobby.unready(id).is_empty():
			out.append(id)
	return out


## The ships to launch for an accepted Start (NetLobby.start checked coverage and Ready): every
## crewed ship, all together (M4-Q4), or [] when the mode's slot errors
## (GameRules.slot_errors) refuse it `bad_mode` with the errors. On a fixed world a ship crewed
## after the universe started starts alone.
func start_ships(s: NetSession) -> Array[int]:
	if game.lobby.any_launched():
		return [s.ship]
	if rebuild.is_valid():
		var errors: Array[String] = rules.slot_errors(start_slots())
		if not errors.is_empty():
			var extra: Dictionary = {"errors": Array(errors)}
			game.refuse(s, NetProtocol.Type.START, FleetMessages.BAD_MODE, extra)
			return []
		var kept: Array[int] = _kept()
		if not _world_current or kept.size() < slots.size():
			_rebuild_for_start(kept)
	start_tick = game.world.tick
	return crewed()


## Why `s` may not take over `seat` on the paused `ship`, whose open stations are `uncovered`,
## or "" (M4-Q8, FT-NET-042): the ship's own Captain and viewers, and players of allied ships
## (same faction); enemies never (ENEMY_SHIP); the seat must cover a station still uncovered
## (TAKEN: someone claimed it first); a crew player may not leave if their own ship in play
## would fail coverage (BREAKS_COVERAGE).
func takeover_rule(s: NetSession, ship: int, seat: String, uncovered: Array) -> String:
	var world: SimWorld = game.world
	if not StationCatalogue.is_seat(seat, game.dev_all) or not StationCatalogue.is_crew(seat):
		return NetGame.BAD_PICK
	if s.ship == ship:
		if s.seat != StationCatalogue.CAPTAIN and s.seat != StationCatalogue.VIEWER:
			return CommandGate.NOT_ALLOWED
	elif not s.has_pick():
		return CommandGate.NOT_ALLOWED
	elif world.faction_of(s.ship) != world.faction_of(ship):
		return FleetMessages.ENEMY_SHIP
	var covers: bool = false
	for station: String in StationCatalogue.stations_of(seat):
		covers = covers or uncovered.has(station)
	if not covers:
		return FleetMessages.TAKEN
	return _leave_rule(s, ship)


## BREAKS_COVERAGE when a crew player leaving their own ship in play for `ship` would make it
## fail the coverage check it passes now (FT-NET-042), else "".
func _leave_rule(s: NetSession, ship: int) -> String:
	if s.ship == ship or not StationCatalogue.is_crew(s.seat) or not game.lobby.in_play(s.ship):
		return ""
	var seats: Array = game.lobby.seats_of(s.ship)
	if NetCoverage.breaks(seats, game.lobby.min_crew(), s.seat):
		return CommandGate.BREAKS_COVERAGE
	return ""


## A takeover was applied: every session of the ship's side hears who took what (M4-Q8).
func took_over(s: NetSession, ship: int, seat: String, from_ship: int) -> void:
	var world: SimWorld = game.world
	var ids: PackedInt32Array = game.audience(
		func(o: NetSession) -> bool:
			return o.ship >= 0 and world.faction_of(o.ship) == world.faction_of(ship)
	)
	var payload: Dictionary = FleetMessages.takeover(ship, seat, s.name, from_ship)
	game.transport.post_event(ids, world.tick, NetProtocol.EVENT_TAKEOVER, payload)


## Where an eliminated ship's sessions go: the first surviving friendly ship in play, or
## FleetMessages.TO_SCOREBOARD when none is left or the mode sends them there (FT-MIS-030,
## D91, GameRules.eliminated_to).
func destination_of(ship: int) -> int:
	if rules.eliminated_to == GameRules.Destination.SCOREBOARD:
		return FleetMessages.TO_SCOREBOARD
	var world: SimWorld = game.world
	for c: Dictionary in game.crew_ships():
		var other: int = c["id"]
		if (
			other != ship
			and game.lobby.in_play(other)
			and world.faction_of(other) == world.faction_of(ship)
		):
			return other
	return FleetMessages.TO_SCOREBOARD


## The live scoreboard's rows, one per started ship: status and progress only (M4-Q9).
func scoreboard_rows() -> Array:
	var world: SimWorld = game.world
	var rows: Array = []
	for c: Dictionary in game.crew_ships():
		var id: int = c["id"]
		if not game.lobby.is_launched(id):
			continue
		var end: int = (
			world.ships.finish_tick[id] if world.ships.finish_tick[id] >= 0 else world.tick
		)
		var time: float = float(end - start_tick) / SimWorld.HZ
		var state: String = FleetMessages.IN_PLAY
		if eliminated.has(id) or world.ships.ship_outcome[id] == ShipStateTable.ShipOutcome.LOSS:
			state = FleetMessages.DESTROYED
		elif (
			world.ships.ship_outcome[id]
			in [ShipStateTable.ShipOutcome.WIN, ShipStateTable.ShipOutcome.SURVIVED]
		):
			state = FleetMessages.FINISHED
		var k: int = world.ships.kills[id] if rules.is_pvp() else 0
		var done: int = world.ships.encounters_done[id]
		rows.append(FleetMessages.scoreboard_row(id, c["name"], team_of(id), state, done, time, k))
	return rows


## After the sim stepped (NetGame.after_ticks): eliminations and relaunches from the
## sim's events (F5: the sim owns the reason, the lives left and the relaunch rule), the
## game's outcome, due handovers, refused relaunches and the scoreboard. The outcome is read
## from the run state (OutcomeSystem.game_outcome) rather than the sim's `game_over`
## event, which only a director run emits.
func after_ticks(events: Array[SimEvent]) -> void:
	var world: SimWorld = game.world
	for e: SimEvent in events:
		if not game.lobby.is_launched(e.ship_id):
			continue
		if e.kind == GameOutcome.EVENT_ELIMINATED and not eliminated.has(e.ship_id):
			_eliminate(e.ship_id, String(e.tag), int(e.value))
		elif e.kind == GameOutcome.EVENT_RELAUNCHED:
			_relaunched(e.ship_id, int(e.value))
	if outcome == null and game.lobby.any_launched():
		var o: GameOutcome = OutcomeSystem.game_outcome(world)
		if o.over():
			outcome = o
			var time: float = float(world.tick - start_tick) / SimWorld.HZ
			var hold_time: float = float(o.held_ticks) / SimRate.HZ
			var reason: String = GameOutcome.REASON_NAMES[o.reason]
			var payload: Dictionary = FleetMessages.game_over(
				reason, Array(o.winners), team_of_faction(o.winner_faction), hold_time, time
			)
			game.broadcast(NetProtocol.EVENT_GAME_OVER, payload)
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


## Sends the `fleet` event when it changed (NetGame._publish, on a lobby change). Once
## the universe runs, a change the sim's events may have made is checked at most every
## FLEET_EVERY_TICKS, so the load stays off the tick (the 64-connection gate, D161).
func publish(lobby_dirty: bool) -> void:
	_pending = _pending or lobby_dirty
	if not _dirty and not _pending:
		return
	var tick: int = game.world.tick
	if not _dirty and game.lobby.any_launched() and tick < _fleet_tick + FLEET_EVERY_TICKS:
		return
	_dirty = false
	_pending = false
	_fleet_tick = tick
	var payload: Dictionary = _fleet_payload()
	if payload != _fleet_sent:
		_fleet_sent = payload
		game.broadcast(NetProtocol.EVENT_FLEET, payload)


## A (re)joining session starts in sync: the `fleet` event, and the scoreboard without a pick.
func send_to(s: NetSession) -> void:
	game.notify(s, NetProtocol.EVENT_FLEET, _fleet_payload())
	if game.lobby.any_launched() and not s.has_pick():
		var payload: Dictionary = FleetMessages.scoreboard(scoreboard_rows())
		game.notify(s, NetProtocol.EVENT_SCOREBOARD, payload)


# --- Handlers. ---


func _on_ship_add(s: NetSession, msg: Dictionary, _now_us: int) -> void:
	var reason: String = _lobby_refusal(s, false)
	if reason == "" and slots.size() >= GameRules.MAX_SHIPS:
		reason = FleetMessages.FLEET_FULL
	if game.refuse(s, NetProtocol.Type.SHIP_ADD, reason, {"name": msg["name"]}):
		return
	var ship_name: String = msg["name"]  # cleaned by NetProtocol.decode (NAMED)
	if ship_name == "":
		ship_name = "Ship %d" % (slots.size() + 1)
	slots.append(ShipSlot.of(ship_name, 0))
	_apply(rules.has_teams())


func _on_ship_team(s: NetSession, msg: Dictionary, _now_us: int) -> void:
	var ship: int = msg["ship"]
	var team: int = msg["team"]
	var reason: String = _lobby_refusal(s, false)
	if reason == "" and (ship < 0 or ship >= slots.size() or (s.ship != ship and not s.is_host)):
		reason = NetGame.NOT_CREW
	elif reason == "" and (not rules.has_teams() or team < 0 or team > 1):
		reason = FleetMessages.BAD_TEAM
	if game.refuse(s, NetProtocol.Type.SHIP_TEAM, reason, {"ship": ship, "team": team}):
		return
	slots[ship].team = team
	_apply(false)


## GameMode{mode, team_win, lives, drop_pause, fill_bots}: lives -1 keeps the holdout default
## (HOLDOUT_LIVES); the two host options (#40 D1, D2) go to the lobby.
func _on_game_mode(s: NetSession, msg: Dictionary, _now_us: int) -> void:
	var mode: int = GameRules.MODE_NAMES.find(msg["mode"])
	var team_win: int = GameRules.TEAM_WIN_NAMES.find(msg["team_win"])
	var lives: int = msg["lives"]
	var reason: String = _lobby_refusal(s, true)
	if reason == "" and (mode < 0 or team_win < 0 or lives == 0 or lives < -1):
		reason = FleetMessages.BAD_MODE
	var extra: Dictionary = msg.duplicate()
	extra.erase("t")
	if game.refuse(s, NetProtocol.Type.GAME_MODE, reason, extra):
		return
	var had_teams: bool = rules.has_teams()
	var modifier: StringName = rules.modifier_id
	rules = GameRules.of_mode(mode as GameRules.Mode)
	rules.modifier_id = modifier
	rules.team_win = team_win as GameRules.TeamWin
	game.lobby.drop_pause = msg["drop_pause"]
	game.lobby.fill_bots = msg["fill_bots"]
	game.lobby.mark_dirty()
	if mode == GameRules.Mode.HOLDOUT and lives > 0:
		rules.relaunch[rules.holdout_finite_faction()] = RelaunchPolicy.of_lives(lives)
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
		reason = NetGame.NOT_CREW
	if game.refuse(s, NetProtocol.Type.RELAUNCH, reason, {"ship": ship}):
		return
	var vote: NetVote = _votes.get_or_add(ship, NetVote.new())
	var passes: bool = vote.cast_from(s, msg["vote"], members)
	var ids: PackedInt32Array = PackedInt32Array(members)
	game.send_votes(NetProtocol.EVENT_RELAUNCH_VOTES, ship, vote, members.size(), ids)
	if passes:
		_votes.erase(ship)
		var c: RelaunchShipCommand = RelaunchShipCommand.new()
		c.ship = ship
		game.world.submit(c)
		_relaunching[ship] = c


## RerollModifier{} (gp-11): the host, before the start, swaps the run modifier for another
## one; refused `no_reroll` with fewer than two.
func _on_reroll_modifier(s: NetSession, _msg: Dictionary, _now_us: int) -> void:
	var reason: String = _lobby_refusal(s, true)
	if reason == "" and modifiers.size() < 2:
		reason = FleetMessages.NO_REROLL
	if game.refuse(s, NetProtocol.Type.REROLL_MODIFIER, reason, {}):
		return
	var others: Array[StringName] = modifiers.filter(
		func(id: StringName) -> bool: return id != rules.modifier_id
	)
	rules.modifier_id = others[_modifier_rng.randi_range(0, others.size() - 1)]
	_world_current = false
	_dirty = true
	game.publish()


# --- Internals. ---


## Why the lobby can't change now, or "": a fixed world or a started universe (lobby_closed),
## and GameMode from anyone but the host (not_host).
func _lobby_refusal(s: NetSession, host_only: bool) -> String:
	if not rebuild.is_valid() or game.lobby.any_launched():
		return FleetMessages.LOBBY_CLOSED
	if host_only and not s.is_host:
		return NetGame.NOT_HOST
	return ""


## After a lobby change: each slot's team follows the mode (one side in co-op,
## one per ship in race and last ship standing, 0 and 1 in teams and holdout, alternating
## when `split` is set), and the lobby world is rebuilt with allied placeholder ships.
func _apply(split: bool) -> void:
	for i: int in slots.size():
		var team: int = 0
		if rules.has_teams():
			team = i % 2 if split or slots[i].team > 1 else slots[i].team
		elif rules.mode != GameRules.Mode.COOP:
			team = i
		slots[i].team = team
	var placeholders: Array[ShipSlot] = []
	for s: ShipSlot in slots:
		placeholders.append(ShipSlot.of(s.name, 0))
	rebuild.call(placeholders, GameRules.new())
	_world_current = false
	_dirty = true
	_send_catalogue()


## Builds the session's world from the kept slots with the mode's factions; every session moves
## to its ship's new id, or to the pick screen when its ship vanished (M4-Q3).
func _rebuild_for_start(kept: Array[int]) -> void:
	var moves: Array = []
	for s: NetSession in game.by_id.values():
		if s.ship >= 0:
			moves.append([s, kept.find(s.ship), s.seat])
			s.ship = -1
			s.seat = ""
	for s: NetSession in game.sessions.all():
		if s.lapsed:
			s.last_ship = kept.find(s.last_ship)
	var built: Array[ShipSlot] = []
	for i: int in kept:
		built.append(slots[i])
	slots = built
	game.reset_claims()
	rebuild.call(slots, rules)
	_world_current = true
	_send_catalogue()
	for m: Array in moves:
		var ship: int = m[1]
		game.lobby.move(m[0], ship, m[2] if ship >= 0 else "")


## Lobby ids of the slots with a crew pick, ascending.
func _kept() -> Array[int]:
	var out: Array[int] = []
	for i: int in slots.size():
		if NetCoverage.crew_count(game.lobby.seats_of(i)) > 0:
			out.append(i)
	return out


## Crewable ships with a crew pick.
func crewed() -> Array[int]:
	var out: Array[int] = []
	for c: Dictionary in game.crew_ships():
		if NetCoverage.crew_count(game.lobby.seats_of(c["id"])) > 0:
			out.append(c["id"])
	return out


func _send_catalogue() -> void:
	var bytes: PackedByteArray = game.catalogue()
	for s: NetSession in game.by_id.values():
		if s.connected():
			game.transport.send(s.conn, bytes)


## The relaunches the eliminated ship's side has left, from the sim's last event for it.
func _lives_left(ship: int) -> int:
	return _lives.get(ship, 0)


## A crewed ship left play, with the sim's reason ("destroyed", "abandoned" or "forfeit",
## M4-Q10) and lives left: everyone hears why; its sessions are handed over later.
func _eliminate(ship: int, reason: String, lives: int) -> void:
	eliminated[ship] = reason
	_lives[ship] = lives
	var cost: int = RelaunchShipCommand.cost(game.world)
	var payload: Dictionary = FleetMessages.eliminated(ship, reason, lives, cost)
	game.broadcast(NetProtocol.EVENT_ELIMINATED, payload)
	var crew: Array = []
	for s: NetSession in game.by_id.values():
		# Guests stay on their own ship's crew list (a relaunch takes them home, #40 D10).
		if s.on_ship(ship) and s.guest_from < 0:
			crew.append([s.id, s.seat])
	_crews[ship] = crew
	_handover_at[ship] = game.world.tick + HANDOVER_DELAY_TICKS
	_dirty = true


## The eliminated ship's sessions view a friendly ship's main screen, or go to the scoreboard.
func _hand_over(ship: int) -> void:
	var to: int = destination_of(ship)
	for pair: Array in _crews.get(ship, []):
		var s: NetSession = game.by_id.get(pair[0])
		if s == null or s.ship != ship:
			continue
		# `handover` first, then the `picked` of the move (the client keys its view by ship).
		game.notify(s, NetProtocol.EVENT_HANDOVER, FleetMessages.handover(ship, to))
		# In co-op and TEAMS the crew are guests there: they may take free light stations
		# (#40 D10, gp-04).
		if to >= 0 and rules.mode in [GameRules.Mode.COOP, GameRules.Mode.TEAMS]:
			s.guest_from = ship
		game.lobby.move(s, to, StationCatalogue.VIEWER if to >= 0 else "")
	# Its guests move on as guests of their own eliminated ship (#40 D10).
	for s: NetSession in game.by_id.values():
		if s.ship == ship and s.guest_from >= 0:
			game.notify(s, NetProtocol.EVENT_HANDOVER, FleetMessages.handover(s.guest_from, to))
			game.lobby.move(s, to, StationCatalogue.VIEWER if to >= 0 else "")
	_board_sent = []
	_board_tick = -SCOREBOARD_EVERY_TICKS


## The sim relaunched the ship (its &"relaunched" event, with the lives left): the ship is back
## in play and its crew on their stations.
func _relaunched(ship: int, lives: int) -> void:
	eliminated.erase(ship)
	_handover_at.erase(ship)
	_lives[ship] = lives
	game.lobby.clear_abandoned(ship)
	# The fresh ship starts with fresh crew state, as after a run reset (R17-4): marks, pings,
	# relay zones and routes, open chips, share timers and probe-scan flags of its old life go.
	# (What a rival's KnowledgeTable holds of the ship is left alone: owner call, see the report.)
	game.crew.reset(ship)
	game.chips.reset(ship)
	game.shares.reset(ship)
	game.coop.reset_ship(ship)
	for pair: Array in _crews.get(ship, []):
		var s: NetSession = game.by_id.get(pair[0])
		if s != null:
			s.guest_from = -1  # a guest goes home (gp-04)
			game.lobby.move(s, ship, pair[1])
	_crews.erase(ship)
	var payload: Dictionary = FleetMessages.relaunched(ship, lives)
	game.broadcast(NetProtocol.EVENT_RELAUNCHED, payload)
	_dirty = true


## The sim rejected the relaunch the vote sent: its voters hear `no_relaunch`.
func _refuse_relaunch(ship: int) -> void:
	for id: int in _voters(ship):
		var extra: Dictionary = {"ship": ship}
		game.request_rejected(
			game.by_id[id], NetProtocol.Type.RELAUNCH, FleetMessages.NO_RELAUNCH, extra
		)


## Connected crew of the eliminated ship as it was when eliminated: the relaunch voters.
func _voters(ship: int) -> Array[int]:
	var out: Array[int] = []
	for pair: Array in _crews.get(ship, []):
		var s: NetSession = game.by_id.get(pair[0])
		if s != null and s.connected() and StationCatalogue.is_crew(pair[1]):
			out.append(s.id)
	return out


func _fleet_payload() -> Dictionary:
	var ships: Array = []
	for c: Dictionary in game.crew_ships():
		var id: int = c["id"]
		var lobby: Dictionary = game.lobby.lobby_state(id)
		ships.append(
			FleetMessages.fleet_ship(
				id,
				c["name"],
				team_of(id),
				lobby["seats"],
				lobby["crew"],
				Array(lobby["uncovered"]),
				lobby["covered"],
				game.lobby.is_launched(id)
			)
		)
	var lives: int = -1
	if rules.mode == GameRules.Mode.HOLDOUT:
		lives = rules.relaunch_for(rules.holdout_finite_faction()).lives
	var started: bool = game.lobby.any_launched()
	var mode: String = GameRules.MODE_NAMES[rules.mode]
	var team_win: String = GameRules.TEAM_WIN_NAMES[rules.team_win]
	var max_ships: int = GameRules.MAX_SHIPS
	var host: bool = game.lobby.host_here()
	var options: Dictionary = {
		"modifier": String(rules.modifier_id),
		"drop_pause": game.lobby.drop_pause,
		"fill_bots": game.lobby.fill_bots,
		"rerollable": modifiers.size() > 1,
	}
	return FleetMessages.fleet(
		ships, mode, team_win, max_ships, lives, Array(waiting()), started, host, options
	)


## The scoreboard to the sessions without a pick: on a change of state or progress, and once a
## second while only the times move.
func _send_scoreboard() -> void:
	var ids: PackedInt32Array = game.audience(
		func(s: NetSession) -> bool: return not s.has_pick() and s.connected()
	)
	if ids.is_empty():
		return
	var rows: Array = scoreboard_rows()
	var tick: int = game.world.tick
	if rows == _board_sent:
		return
	if tick < _board_tick + SCOREBOARD_EVERY_TICKS and _untimed(rows) == _untimed(_board_sent):
		return
	_board_sent = rows
	_board_tick = tick
	var payload: Dictionary = FleetMessages.scoreboard(rows)
	game.transport.post_event(ids, tick, NetProtocol.EVENT_SCOREBOARD, payload)


static func _untimed(rows: Array) -> Array:
	var out: Array = []
	for row: Dictionary in rows:
		var r: Dictionary = row.duplicate()
		r.erase("time")
		out.append(r)
	return out
