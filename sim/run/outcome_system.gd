class_name OutcomeSystem
extends RefCounted
## Ship status and encounter outcome (T036, FT-M1-012, D30). Runs last in each tick,
## after damage, and writes only RunTable. In ship id order:
## 1. A ship in play whose kin.alive is 0 becomes DESTROYED (DamageSystem already
##    emitted &"destroyed").
## 2. A live AI ship in RETREAT mode that no live ship of a faction hostile to it
##    detects any more has escaped: RETREATED, and &"retreated" (ship_id the ship).
##    Provisional: retreat means leaving every hostile sensor range; FT-MIS-017 and D36
##    don't define it.
## 3. Each crewed ship (not AI-flown) without an outcome gets one: LOSS when it is
##    destroyed (per-ship elimination, D30: the other ships carry on); WIN when it is in
##    play and every ship of a faction hostile to it is destroyed or retreated, with at
##    least one such ship. &"outcome" is emitted once per ship, keyed to it, with value
##    the RunTable.Outcome and tag &"win" or &"loss".
## Statuses and outcomes are final for the run; SimWorld.reset_ship (FT-GEN-002)
## restores a ship's row to IN_PLAY / NONE like every other table.


static func step(world: SimWorld) -> void:
	var run: RunTable = world.run
	for id: int in world.ship_count():
		if run.status[id] != RunTable.Status.IN_PLAY:
			continue
		if not world.kin.is_alive(id):
			_set_status(world, id, RunTable.Status.DESTROYED)
		elif _escaped(world, id):
			_set_status(world, id, RunTable.Status.RETREATED)
			world.emit(&"retreated", id)
	for id: int in world.ship_count():
		if world.ai.is_enabled(id) or run.outcome[id] != RunTable.Outcome.NONE:
			continue
		if run.status[id] == RunTable.Status.DESTROYED:
			_set_outcome(world, id, RunTable.Outcome.LOSS)
		elif run.status[id] == RunTable.Status.IN_PLAY and _enemies_gone(world, id):
			_set_outcome(world, id, RunTable.Outcome.WIN)


## The encounter's outcome over the crewed ships: WIN once any has won, LOSS once every
## one has lost, else NONE (M1 has one crewed ship, so it is that ship's outcome).
static func encounter_outcome(world: SimWorld) -> RunTable.Outcome:
	var crewed: int = 0
	var lost: int = 0
	for id: int in world.ship_count():
		if world.ai.is_enabled(id):
			continue
		crewed += 1
		match world.run.outcome[id]:
			RunTable.Outcome.WIN:
				return RunTable.Outcome.WIN
			RunTable.Outcome.LOSS:
				lost += 1
	return RunTable.Outcome.LOSS if crewed > 0 and lost == crewed else RunTable.Outcome.NONE


## An AI ship in RETREAT that no live ship of a hostile faction detects.
static func _escaped(world: SimWorld, id: int) -> bool:
	if not world.ai.is_enabled(id) or world.ai.mode[id] != AiTable.Mode.RETREAT:
		return false
	var faction: int = world.faction_of(id)
	for o: int in world.ship_count():
		if not world.kin.is_alive(o):
			continue
		var f: int = world.faction_of(o)
		if world.relation(faction, f) == SimWorld.Relation.HOSTILE:
			if KnowledgeSystem.is_detected(world, f, id):
				return false
	return true


## Every ship of a faction hostile to the ship's is out of play, and there is one.
static func _enemies_gone(world: SimWorld, id: int) -> bool:
	var faction: int = world.faction_of(id)
	var enemies: int = 0
	for o: int in world.ship_count():
		if world.relation(faction, world.faction_of(o)) != SimWorld.Relation.HOSTILE:
			continue
		if world.run.status[o] == RunTable.Status.IN_PLAY:
			return false
		enemies += 1
	return enemies > 0


static func _set_status(world: SimWorld, id: int, status: RunTable.Status) -> void:
	world.run.status[id] = status
	world.run.status_tick[id] = world.tick


static func _set_outcome(world: SimWorld, id: int, outcome: RunTable.Outcome) -> void:
	world.run.outcome[id] = outcome
	world.run.outcome_tick[id] = world.tick
	world.emit(&"outcome", id, -1, outcome, Vector3.ZERO, RunTable.OUTCOME_NAMES[outcome])
