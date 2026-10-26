class_name EncounterSystem
extends RefCounted
## Encounter state over the run (E07, FT-MIS-015, FT-MIS-025, FT-MIS-027, D231, D233). Runs
## after the movement systems (so after a jump) and before OutcomeSystem, and writes only
## EncounterTable, RunTable and events. In encounter id order:
## 1. A PENDING encounter turns ACTIVE when one of its ships is at the site (inside the
##    site's radius), or when the arrival timeout has passed since it opened (D231).
##    &"encounter_start" is emitted (ship_id the first ship, value the id, tag the scenario).
## 2. In an ACTIVE encounter, a ship whose jump this tick (&"jump_arrive") took it out of
##    the encounter's site while a live ship of a hostile faction detects it has fled
##    (D233): its bit joins fled_mask, it leaves the encounter, and the flee cost is
##    charged. A jump that leaves unseen is not fleeing and the ship stays in the encounter.
## 3. A ship destroyed or abandoned leaves the encounter as a loss. When every ship has
##    left (lost or fled) the encounter ends LOST, or FLED when none was lost.
## A scenario ends an encounter itself with EndEncounterCommand (finish()). The run is won
## once a crewed ship has been through RunDef.encounters encounters and is in none
## (run_complete(), read by OutcomeSystem).


static func step(world: SimWorld) -> void:
	var table: EncounterTable = world.encounters
	var count: int = table.size()
	if count == 0:
		return
	var jumped: PackedInt32Array = _jumped_this_tick(world)
	for id: int in count:
		var result: int = table.result[id]
		if result > EncounterTable.Result.ACTIVE:
			continue
		if result == EncounterTable.Result.PENDING and _arrived(world, id):
			_activate(world, id)
		elif result == EncounterTable.Result.ACTIVE:
			_check_flee(world, id, jumped)
		_check_losses(world, id)


## Ends an open encounter with a result: stamps the end tick, frees the ships still in it
## (each has been through one more encounter) and emits &"encounter_end" (value the
## result, other_id the id, tag the scenario).
static func finish(world: SimWorld, id: int, result: EncounterTable.Result) -> void:
	var table: EncounterTable = world.encounters
	table.result[id] = result
	table.end_tick[id] = world.tick
	for ship: int in _ships(table.ships_mask[id]):
		if world.run.encounter[ship] == id:
			_leave(world, ship)
	var first: int = table.ship_ids[id]
	world.emit(&"encounter_end", first, id, result, Vector3.ZERO, _scenario(world, id))


## Whether the crewed ship has been through all of the run's encounters and is in none.
static func run_complete(world: SimWorld, ship: int) -> bool:
	return (
		world.run_def != null
		and world.run.encounter[ship] < 0
		and world.run.encounters_done[ship] >= world.run_def.encounters
	)


## Charges a fled ship the FleeCostDef (D233): credits (all it has, when it holds less) and
## a reputation draw with the hostile faction that saw it go. &"flee_cost" is emitted
## (ship_id the ship, other_id the hostile ship, value the credits taken, tag the
## distribution id).
static func _charge_flee(world: SimWorld, ship: int, hostile_ship: int) -> void:
	var cost: FleeCostDef = world.run_def.flee_cost if world.run_def != null else null
	if cost == null:
		return
	var paid: int = mini(cost.credits, Economy.credits(world, ship))
	Economy.add_credits(world, ship, -paid)
	Reputation.change(
		world, ship, world.faction_of(ship), world.faction_of(hostile_ship), cost.rep_dist
	)
	world.emit(&"flee_cost", ship, hostile_ship, paid, Vector3.ZERO, cost.rep_dist)


static func _activate(world: SimWorld, id: int) -> void:
	var table: EncounterTable = world.encounters
	table.result[id] = EncounterTable.Result.ACTIVE
	table.start_tick[id] = world.tick
	world.emit(&"encounter_start", table.ship_ids[id], -1, id, Vector3.ZERO, _scenario(world, id))


static func _arrived(world: SimWorld, id: int) -> bool:
	var table: EncounterTable = world.encounters
	var site: int = table.site[id]
	if site < 0 or world.tick >= table.open_tick[id] + _timeout_ticks(world):
		return true
	for ship: int in _ships(table.ships_mask[id]):
		if (
			world.run.status[ship] == RunTable.Status.IN_PLAY
			and SiteTable.at_site(world, ship) == site
		):
			return true
	return false


static func _check_flee(world: SimWorld, id: int, jumped: PackedInt32Array) -> void:
	var table: EncounterTable = world.encounters
	var site: int = table.site[id]
	if site < 0 or jumped.is_empty():
		return
	for ship: int in _ships(table.ships_mask[id]):
		if world.run.encounter[ship] != id or not jumped.has(ship):
			continue
		if SiteTable.at_site(world, ship) == site:
			continue
		var seen_by: int = _hostile_seeing(world, ship)
		if seen_by < 0:
			continue
		table.fled_mask[id] |= 1 << ship
		world.run.fled_count[ship] += 1
		_leave(world, ship)
		world.emit(&"fled", ship, seen_by, id, Vector3.ZERO, _scenario(world, id))
		_charge_flee(world, ship, seen_by)


static func _check_losses(world: SimWorld, id: int) -> void:
	var table: EncounterTable = world.encounters
	var mask: int = table.ships_mask[id]
	for ship: int in _ships(mask):
		if world.run.status[ship] == RunTable.Status.IN_PLAY:
			continue
		if EncounterTable.has_bit(table.losses_mask[id] | table.fled_mask[id], ship):
			continue
		table.losses_mask[id] |= 1 << ship
		if world.run.encounter[ship] == id:
			_leave(world, ship)
	if (table.losses_mask[id] | table.fled_mask[id]) == mask:
		var lost: bool = table.losses_mask[id] != 0
		finish(world, id, EncounterTable.Result.LOST if lost else EncounterTable.Result.FLED)


## A ship leaves its encounter: one more done, no longer in one.
static func _leave(world: SimWorld, ship: int) -> void:
	world.run.encounter[ship] = -1
	world.run.encounters_done[ship] += 1


## The id of a live ship of a faction hostile to the ship's that detects it, or -1.
static func _hostile_seeing(world: SimWorld, ship: int) -> int:
	var faction: int = world.faction_of(ship)
	for o: int in world.ship_count():
		if o == ship or not world.kin.is_alive(o):
			continue
		var f: int = world.faction_of(o)
		if world.relation(f, faction) == SimWorld.Relation.HOSTILE:
			if KnowledgeSystem.is_detected(world, f, ship):
				return o
	return -1


## Ships that emitted &"jump_arrive" during this tick (events of the tick being stepped).
static func _jumped_this_tick(world: SimWorld) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var events: Array[SimEvent] = world.events
	var i: int = events.size() - 1
	while i >= 0 and events[i].tick == world.tick:
		if events[i].kind == &"jump_arrive":
			out.append(events[i].ship_id)
		i -= 1
	return out


static func _timeout_ticks(world: SimWorld) -> int:
	if world.run_def == null:
		return 0
	return ceili(world.run_def.director.arrival_timeout_s * SimWorld.HZ)


static func _scenario(world: SimWorld, id: int) -> StringName:
	var ix: int = world.encounters.scenario_ix[id]
	return StringName(world.scenario_ids[ix]) if ix >= 0 and ix < world.scenario_ids.size() else &""


## Ship ids of a mask, ascending.
static func _ships(mask: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for ship: int in EncounterTable.MAX_SHIP_BITS:
		if (mask >> ship) & 1 == 1:
			out.append(ship)
	return out
