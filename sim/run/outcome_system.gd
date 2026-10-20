class_name OutcomeSystem
extends RefCounted
## Ship status and encounter outcome (T036, FT-M1-012, D30). Runs last in each tick,
## after damage, and writes only RunTable. In ship id order:
## 1. A ship in play whose kin.alive is 0 becomes DESTROYED (DamageSystem already
##    emitted &"destroyed").
## 2. A live AI ship in RETREAT mode that no live ship of a faction hostile to it
##    detects any more has escaped: RETREATED, and &"retreated" (ship_id the ship).
##    Retreat means leaving every hostile sensor range (D120).
## 3. Each crewed ship (not AI-flown) without an outcome gets one: LOSS when it is
##    destroyed or abandoned (per-ship elimination, D30: the other ships carry on);
##    WIN when it is in play and every ship of a faction hostile to it is destroyed or
##    retreated, with at least one such ship. &"outcome" is emitted once per ship,
##    keyed to it, with value the RunTable.Outcome and tag &"win" or &"loss".
## Statuses and outcomes are final for the run; SimWorld.reset_ship (FT-MIS-017)
## restores a ship's row to IN_PLAY / NONE like every other table.


static func step(world: SimWorld) -> void:
	var run: RunTable = world.run
	var status: PackedByteArray = run.status
	var outcome: PackedByteArray = run.outcome
	var alive: PackedByteArray = world.kin.alive
	var enabled: PackedByteArray = world.ai.enabled
	var mode: PackedByteArray = world.ai.mode
	var n: int = world.ship_count()
	for id: int in n:
		if status[id] != RunTable.Status.IN_PLAY:
			continue
		if alive[id] != 1:
			status[id] = RunTable.Status.DESTROYED
		elif enabled[id] == 1 and mode[id] == AiTable.Mode.RETREAT and _escaped(world, id):
			status[id] = RunTable.Status.RETREATED
			world.emit(&"retreated", id)
	for id: int in n:
		if enabled[id] == 1 or outcome[id] != RunTable.Outcome.NONE:
			continue
		var st: int = status[id]
		if st == RunTable.Status.DESTROYED or st == RunTable.Status.ABANDONED:
			_set_outcome(world, id, RunTable.Outcome.LOSS)
		elif st == RunTable.Status.IN_PLAY and _enemies_gone(world, id):
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
	var factions: PackedInt32Array = world.kin.factions
	var status: PackedByteArray = world.run.status
	# Relation to each faction, looked up once.
	var hostile: Dictionary[int, bool] = {}
	var enemies: int = 0
	for o: int in world.ship_count():
		var f: int = factions[o]
		if not hostile.has(f):
			hostile[f] = world.relation(faction, f) == SimWorld.Relation.HOSTILE
		if not hostile[f]:
			continue
		if status[o] == RunTable.Status.IN_PLAY:
			return false
		enemies += 1
	return enemies > 0


static func _set_outcome(world: SimWorld, id: int, outcome: RunTable.Outcome) -> void:
	world.run.outcome[id] = outcome
	world.emit(&"outcome", id, -1, outcome, Vector3.ZERO, RunTable.OUTCOME_NAMES[outcome])
