class_name OutcomeSystem
extends RefCounted
## Ship status and encounter outcome (T036, FT-M1-012, D30). Runs last in each tick,
## after damage, and writes only ShipStateTable. In ship id order:
## 1. A ship in play whose kin.alive is 0 becomes DESTROYED (DamageSystem already
##    emitted &"destroyed").
## 2. A live AI ship in RETREAT mode is gone (gp-17, D9, amending D120): RETREATED, and
##    &"retreated" (ship_id the ship), once it has been retreating for its
##    retreat_jump_after (it jumps out), or once every live ship of a faction hostile to it
##    is farther than retreat_gone_factor x its engage_range_max. Sensors play no part, so a
##    blinded crew does not let it go at once (R10-13); neither way counts as a kill.
## 3. Each crewed ship (not AI-flown) without an outcome gets one: LOSS when it is
##    destroyed or abandoned (per-ship elimination, D30: the other ships carry on);
##    WIN when it is in play and every ship of a faction hostile to it is destroyed or
##    retreated, with at least one such ship. &"outcome" is emitted once per ship,
##    keyed to it, with value the ShipStateTable.ShipOutcome and tag &"win" or &"loss".
## Statuses and outcomes are final for the run; SimWorld.reset_ship (FT-MIS-017)
## restores a ship's row to IN_PLAY / NONE like every other table.
## Multi-ship games (#11): a crewed ship destroyed by a crewed ship of another side counts
## a kill for that ship (ShipStateTable.kills); each outcome stamps
## ShipStateTable.finish_tick. A crewed ship's LOSS also emits &"eliminated"
## (GameOutcome.EVENT_ELIMINATED, FT-MIS-011) with the reason and the lives left, which
## the server relays (NetFleet, F5); in a director run
## (run_def set) the first tick game_outcome() is over emits &"game_over"
## (GameOutcome.EVENT_GAME_OVER).


static func step(world: SimWorld) -> void:
	var directed: bool = world.run_def != null
	var was_over: bool = directed and game_outcome(world).over()
	var status: PackedByteArray = world.ships.status
	var outcome: PackedByteArray = world.ships.ship_outcome
	var alive: PackedByteArray = world.kin.alive
	var enabled: PackedByteArray = world.ai.enabled
	var mode: PackedByteArray = world.ai.mode
	var n: int = world.ship_count()
	for id: int in n:
		if status[id] != ShipStateTable.Status.IN_PLAY:
			continue
		if alive[id] != 1:
			# a training run resets the crewed ship at the yard instead.
			if _training_reset(world, id):
				continue
			status[id] = ShipStateTable.Status.DESTROYED
			if enabled[id] == 0:
				_count_kill(world, id)
				# A ship that won and was then destroyed is out of play too: it has no
				# LOSS to emit the elimination from (R17-5).
				if outcome[id] == ShipStateTable.ShipOutcome.WIN:
					_emit_eliminated(world, id)
		elif enabled[id] == 1 and mode[id] == AiTable.Mode.RETREAT and _escaped(world, id):
			status[id] = ShipStateTable.Status.RETREATED
			world.emit(&"retreated", id)
	for id: int in n:
		if enabled[id] == 1 or outcome[id] != ShipStateTable.ShipOutcome.NONE:
			continue
		var st: int = status[id]
		if st == ShipStateTable.Status.DESTROYED or st == ShipStateTable.Status.ABANDONED:
			_set_outcome(world, id, ShipStateTable.ShipOutcome.LOSS)
		elif st == ShipStateTable.Status.IN_PLAY and world.run_def != null:
			# a run wins by finishing its encounters, not by a clear sky.
			if EncounterSystem.run_complete(world, id):
				_set_outcome(world, id, ShipStateTable.ShipOutcome.WIN)
		elif st == ShipStateTable.Status.IN_PLAY and _enemies_gone(world, id):
			_set_outcome(world, id, ShipStateTable.ShipOutcome.WIN)
	if directed and not was_over:
		var now: GameOutcome = game_outcome(world)
		if now.over():
			world.emit(GameOutcome.EVENT_GAME_OVER, -1, -1, now.reason)


## The game's outcome under world.rules (#11): who won and why, derived from ShipStateTable each
## time it is asked. A crewed ship still stands while it has no LOSS, or has one and its
## side's relaunch policy allows another relaunch (M4-Q2); a ship out of play never stands
## by an earlier win. COOP: OBJECTIVE with every
## crewed ship that won once the fleet run's final objective is complete (FT-MIS-013,
## M4-Q1). RACE: FIRST_TO_FINISH, the first ship to complete the final objective, by
## ShipStateTable.finish_tick (FT-MIS-032). LAST_STANDING: LAST_STANDING, the one crewed ship left
## standing (FT-MIS-033). TEAMS: by rules.team_win, the first team to finish, or the last
## team with a ship standing (once no ship plays on and several teams stand, the first to
## finish), its ships the winners (FT-MIS-034, M4-Q6). HOLDOUT: HOLDOUT_OVER once the finite
## side has no ship standing, held_ticks the tick its last ship left play (M4-Q2), no winner
## named; or, when the time cap runs out first, the finite side wins (A11). Every mode:
## ALL_LOST once no crewed ship stands and none won.
static func game_outcome(world: SimWorld) -> GameOutcome:
	var out: GameOutcome = GameOutcome.new()
	var crew: PackedInt32Array = PackedInt32Array()
	var standing: PackedInt32Array = PackedInt32Array()
	var playing: bool = false
	var won: bool = false
	for id: int in world.ship_count():
		if world.ai.is_enabled(id):
			continue
		crew.append(id)
		var o: int = world.ships.ship_outcome[id]
		won = won or o == ShipStateTable.ShipOutcome.WIN
		# in play counts, not "no loss": a ship that won and was then destroyed does not stand.
		if world.ships.status[id] == ShipStateTable.Status.IN_PLAY or _may_relaunch(world, id):
			standing.append(id)
			playing = playing or o == ShipStateTable.ShipOutcome.NONE
	if crew.is_empty():
		return out
	var rules: GameRules = world.rules
	match rules.mode:
		GameRules.Mode.RACE:
			_first_to_finish(world, crew, out, false)
		GameRules.Mode.LAST_STANDING:
			if standing.size() == 1 and crew.size() > 1:
				out.reason = GameOutcome.Reason.LAST_STANDING
				out.winners = standing
		GameRules.Mode.TEAMS:
			if rules.team_win == GameRules.TeamWin.FIRST_TO_FINISH:
				_first_to_finish(world, crew, out, true)
			else:
				_last_team(world, crew, standing, out)
				if not out.over() and not playing:
					_first_to_finish(world, crew, out, true)
		GameRules.Mode.HOLDOUT:
			_holdout(world, crew, standing, out)
		_:
			if won:
				out.reason = GameOutcome.Reason.OBJECTIVE
				for id: int in crew:
					if world.ships.ship_outcome[id] == ShipStateTable.ShipOutcome.WIN:
						out.winners.append(id)
	if not out.over() and standing.is_empty():
		out.reason = GameOutcome.Reason.ALL_LOST
	return out


## Whether a crewed ship that lost may still relaunch under its side's policy.
static func _may_relaunch(world: SimWorld, id: int) -> bool:
	return world.rules.relaunch_for(world.faction_of(id)).allows(world.ships.relaunches[id])


## FIRST_TO_FINISH: the crewed ships that won on the earliest finish tick; with teams, every
## ship of the first one's faction.
static func _first_to_finish(
	world: SimWorld, crew: PackedInt32Array, out: GameOutcome, teams: bool
) -> void:
	var first: int = -1
	for id: int in crew:
		if world.ships.ship_outcome[id] != ShipStateTable.ShipOutcome.WIN:
			continue
		var t: int = world.ships.finish_tick[id]
		if first < 0 or t < world.ships.finish_tick[first]:
			first = id
	if first < 0:
		return
	out.reason = GameOutcome.Reason.FIRST_TO_FINISH
	if not teams:
		for id: int in crew:
			var o: int = world.ships.ship_outcome[id]
			if (
				o == ShipStateTable.ShipOutcome.WIN
				and world.ships.finish_tick[id] == world.ships.finish_tick[first]
			):
				out.winners.append(id)
		return
	out.winner_faction = world.faction_of(first)
	for id: int in crew:
		if world.faction_of(id) == out.winner_faction:
			out.winners.append(id)


## LAST_TEAM_STANDING: the one faction with a ship standing, all its ships the winners.
static func _last_team(
	world: SimWorld, crew: PackedInt32Array, standing: PackedInt32Array, out: GameOutcome
) -> void:
	var sides: Dictionary[int, bool] = {}
	for id: int in crew:
		sides[world.faction_of(id)] = true
	var left: Dictionary[int, bool] = {}
	for id: int in standing:
		left[world.faction_of(id)] = true
	if left.size() != 1 or sides.size() < 2:
		return
	out.reason = GameOutcome.Reason.LAST_STANDING
	out.winner_faction = left.keys()[0]
	for id: int in crew:
		if world.faction_of(id) == out.winner_faction:
			out.winners.append(id)


## HOLDOUT_OVER once no ship of the finite side stands (no winner, held_ticks the latest tick
## one of its ships left play). With one still standing, the session ends at
## GameRules.HOLDOUT_CAP: the finite side held if a ship of it is in play, and wins (faction
## and winners named, held_ticks the cap); one that only waits to relaunch has not held (no
## winner, held_ticks as above).
static func _holdout(
	world: SimWorld, crew: PackedInt32Array, standing: PackedInt32Array, out: GameOutcome
) -> void:
	var finite: int = world.rules.holdout_finite_faction()
	var latest: int = -1
	var in_play: bool = false
	var waiting: bool = false
	for id: int in crew:
		if world.faction_of(id) != finite:
			continue
		latest = maxi(latest, world.ships.finish_tick[id])
		if world.ships.status[id] == ShipStateTable.Status.IN_PLAY:
			in_play = true
		elif standing.has(id):
			waiting = true
	if in_play or waiting:
		var cap: int = SimRate.ticks(GameRules.HOLDOUT_CAP)
		if world.tick < cap:
			return
		out.reason = GameOutcome.Reason.HOLDOUT_OVER
		if not in_play:
			out.held_ticks = latest
			return
		out.held_ticks = cap
		out.winner_faction = finite
		for id: int in crew:
			if world.faction_of(id) == finite:
				out.winners.append(id)
		return
	if latest < 0:
		return
	out.reason = GameOutcome.Reason.HOLDOUT_OVER
	out.held_ticks = latest


## A crewed ship destroyed this tick by a crewed ship of another side: one kill for that ship
## (the &"destroyed" event names the source, DamageSystem).
static func _count_kill(world: SimWorld, id: int) -> void:
	var events: Array[SimEvent] = world.events
	var i: int = events.size() - 1
	while i >= 0 and events[i].tick == world.tick:
		var e: SimEvent = events[i]
		i -= 1
		if e.kind != &"destroyed" or e.ship_id != id:
			continue
		var killer: int = e.other_id
		if killer == id or not world.has_ship(killer):
			return
		if not world.is_crew(killer) or world.faction_of(killer) == world.faction_of(id):
			return
		world.ships.kills[killer] += 1
		return


## An AI ship in RETREAT that has jumped out (retreating retreat_jump_after or longer) or left
## every live ship of a hostile faction beyond retreat_gone_factor x engage_range_max (gp-17).
static func _escaped(world: SimWorld, id: int) -> bool:
	var ai: AiTable = world.ai
	if not ai.is_enabled(id) or ai.mode[id] != AiTable.Mode.RETREAT:
		return false
	if world.tick - ai.retreat_tick[id] >= SimRate.ticks(ai.retreat_jump_after[id]):
		return true
	var reach: float = ai.retreat_gone_factor[id] * ai.engage_range_max[id]
	var faction: int = world.faction_of(id)
	for o: int in world.ship_count():
		if o == id or not world.kin.is_alive(o):
			continue
		if world.is_hostile(faction, world.faction_of(o)):
			if world.kin.relative(id, o).length() <= reach:
				return false
	return true


## Every ship of a faction hostile to the ship's is out of play, and there is one.
static func _enemies_gone(world: SimWorld, id: int) -> bool:
	var faction: int = world.faction_of(id)
	var owner_faction: PackedInt32Array = world.kin.owner_faction
	var status: PackedByteArray = world.ships.status
	# Relation to each faction, looked up once.
	var hostile: Dictionary[int, bool] = {}
	var enemies: int = 0
	for o: int in world.ship_count():
		var f: int = owner_faction[o]
		if not hostile.has(f):
			hostile[f] = world.is_hostile(faction, f)
		if not hostile[f]:
			continue
		if status[o] == ShipStateTable.Status.IN_PLAY:
			return false
		enemies += 1
	return enemies > 0


## In a training run (RunDef.training, FT-MIS-039) a crewed ship at hull 0 is not eliminated:
## ResetShipCommand's reset puts it back at the yard (site 0). The reset is a pure function
## of the state, so a replay reaches it on the same tick. True when it reset the ship.
static func _training_reset(world: SimWorld, id: int) -> bool:
	if world.run_def == null or not world.run_def.training or world.ai.is_enabled(id):
		return false
	var cmd: ResetShipCommand = ResetShipCommand.new()
	cmd.ship_id = id
	if world.sites.size() > 0:
		var yard: PackedFloat64Array = world.sites.point(0)
		cmd.x = yard[0]
		cmd.y = yard[1]
		cmd.z = yard[2]
	cmd.apply(world)
	return true


static func _set_outcome(world: SimWorld, id: int, outcome: ShipStateTable.ShipOutcome) -> void:
	world.ships.ship_outcome[id] = outcome
	world.ships.finish_tick[id] = world.tick
	world.emit(&"outcome", id, -1, outcome, Vector3.ZERO, ShipStateTable.OUTCOME_NAMES[outcome])
	if outcome == ShipStateTable.ShipOutcome.LOSS:
		_emit_eliminated(world, id)


## &"eliminated" for a crewed ship out of play: tagged destroyed, or abandoned / forfeit.
static func _emit_eliminated(world: SimWorld, id: int) -> void:
	var tag: StringName = &"destroyed"
	if world.ships.status[id] == ShipStateTable.Status.ABANDONED:
		tag = &"forfeit" if world.rules.is_pvp() else &"abandoned"
	var policy: RelaunchPolicy = world.rules.relaunch_for(world.faction_of(id))
	world.emit(
		GameOutcome.EVENT_ELIMINATED,
		id,
		-1,
		policy.left(world.ships.relaunches[id]),
		Vector3.ZERO,
		tag
	)
