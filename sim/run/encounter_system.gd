class_name EncounterSystem
extends RefCounted
## Encounter state over the run (E07, FT-MIS-015, FT-MIS-025, FT-MIS-027, D231, D233). Runs
## after the movement systems (so after a jump) and before OutcomeSystem, and writes only
## EncounterTable, ShipStateTable and events. In encounter id order:
## 1. A PENDING encounter turns ACTIVE when one of its ships is at the site (inside the
##    site's radius), or when the arrival timeout has passed since it opened (D231).
##    &"encounter_start" is emitted (ship_id the first ship, value the id, tag the scenario).
## 2. In an ACTIVE encounter, a ship whose jump arrives this tick (&"jump_arrive") away from
##    the encounter's site, and that a live ship of a hostile faction detected when the jump
##    started (HelmTable.jump_seen_by), has fled (D233): its bit joins fled_mask, it leaves
##    the encounter, and the flee cost is charged. Where the jump started doesn't matter,
##    as fights happen at 9 to 12 km and the site is 3 to 5 km wide (review 2 M3). A jump
##    that started unseen, or ends at the site, is not fleeing and the ship stays. Only ships
##    spawned after the encounter opened count as watchers (EncounterTable.npc_floor): a
##    leftover raider of an older encounter makes no flee, on a travel leg or anywhere.
##    A crippled ship's seen jump away within its limp-home window (step 3) is judged when
##    the window ends: undocked by then, it has fled, as above (ShipStateTable.limp_seen_by).
## 3. In an ACTIVE encounter, a crewed ship in play is crippled (gp-09, #38 D4) once its hull
##    fraction is under RunDef.crippled_hull or RunDef.crippled_subsystems of its subsystems
##    are destroyed: &"crippled" (value RunDef.limp_home_time, other_id the encounter). Docked
##    anywhere (a dock after the crippling) within limp_home_time of that, it has limped
##    home, and a jump on the way there is no flee: its bit joins limped_mask,
##    &"limped_home" is emitted and the encounter ends PARTIAL, so its accepted cards pay
##    RunDef.partial_pay (the scenarios' end()).
## 4. In an ACTIVE encounter, a crewed ship in play that is docked anywhere (and did not limp
##    home in step 3) while a live ship of a hostile faction other than Factions.DEBRIS,
##    spawned since the encounter opened, is in the fight (within the docked ship's
##    sensor_range of it or of the encounter's site, so another encounter's hostiles
##    elsewhere don't count) is out of the fight (w-ckm): it leaves the
##    encounter as fled (&"fled", other_id the watcher or -1), charged the flee cost only
##    when a hostile sees it (hostile_seeing, D233). Docking doesn't stop the clock: the rest
##    of a fleet fights on, and a lone ship's encounter ends FLED (step 5), so a finale sat
##    out at a dock uses a try. Travel legs, with only debris, are unaffected.
## 5. A ship destroyed or abandoned leaves the encounter as a loss. When every ship has
##    left (lost or fled) the encounter ends LOST, or FLED when none was lost.
## A scenario ends an encounter itself with EndEncounterCommand (finish()). The run is won
## once the director has closed it for a crewed ship (FinishShipCommand, after at least
## RunDef.min_encounters) and the ship is in no encounter (run_complete(), read by
## OutcomeSystem; Q4, owner 2026-10-26).


static func step(world: SimWorld) -> void:
	var table: EncounterTable = world.encounters
	var count: int = table.size()
	if count == 0:
		return
	var jumped: Dictionary[int, bool] = _ships_with(world, &"jump_arrive")
	for id: int in count:
		var result: int = table.result[id]
		if result > EncounterTable.Result.ACTIVE:
			continue
		if result == EncounterTable.Result.PENDING and _arrived(world, id):
			_activate(world, id)
		elif result == EncounterTable.Result.ACTIVE:
			_check_flee(world, id, jumped)
			if _check_limp(world, id):
				continue
			_check_docked(world, id)
		_check_losses(world, id)


## Ends an open encounter with a result: stamps the end tick, frees the ships still in it
## (each has been through one more encounter) and emits &"encounter_end" (value the
## result, other_id the id, tag the scenario).
static func finish(world: SimWorld, id: int, result: EncounterTable.Result) -> void:
	var table: EncounterTable = world.encounters
	# A ship destroyed or abandoned before the scenario ended the encounter (a ram that
	# also took the last raider with it) is a loss of this encounter all the same.
	for ship: int in _ships(table.ships_mask[id]):
		if (
			world.ships.encounter[ship] == id
			and world.ships.status[ship] != ShipStateTable.Status.IN_PLAY
		):
			table.losses_mask[id] |= 1 << ship
	table.result[id] = result
	table.end_tick[id] = world.tick
	for ship: int in _ships(table.ships_mask[id]):
		if world.ships.encounter[ship] == id:
			_leave(world, ship)
	var first: int = table.owner_ship[id]
	world.emit(&"encounter_end", first, id, result, Vector3.ZERO, _scenario(world, id))


## Whether the director has closed the crewed ship's run and the ship is in no encounter.
static func run_complete(world: SimWorld, ship: int) -> bool:
	return (
		world.run_def != null and world.ships.encounter[ship] < 0 and world.ships.closed[ship] != 0
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
	world.emit(&"encounter_start", table.owner_ship[id], -1, id, Vector3.ZERO, _scenario(world, id))


static func _arrived(world: SimWorld, id: int) -> bool:
	var table: EncounterTable = world.encounters
	var site: int = table.site[id]
	if site < 0 or world.tick >= table.open_tick[id] + _timeout_ticks(world):
		return true
	for ship: int in _ships(table.ships_mask[id]):
		if (
			world.ships.status[ship] == ShipStateTable.Status.IN_PLAY
			and SiteTable.at_site(world, ship) == site
		):
			return true
	return false


static func _check_flee(world: SimWorld, id: int, jumped: Dictionary[int, bool]) -> void:
	var table: EncounterTable = world.encounters
	var site: int = table.site[id]
	if site < 0:
		return
	var ships: ShipStateTable = world.ships
	for ship: int in _ships(table.ships_mask[id]):
		if ships.encounter[ship] != id:
			continue
		var seen_by: int = world.helm.jump_seen_by[ship]
		if jumped.has(ship) and SiteTable.at_site(world, ship) != site and seen_by >= 0:
			if not limping(world, ship):
				_flee(world, id, ship, seen_by)
				continue
			# A crippled ship's seen jump away is judged when its window ends (w-4tg).
			ships.limp_seen_by[ship] = seen_by
		elif ships.limp_seen_by[ship] >= 0 and ships.crippled_tick[ship] >= 0:
			if not limping(world, ship) and world.kin.is_alive(ship):
				_flee(world, id, ship, ships.limp_seen_by[ship])


## The ship has fled (D233): marked, out of the encounter, charged when a hostile saw it.
static func _flee(world: SimWorld, id: int, ship: int, seen_by: int) -> void:
	world.encounters.fled_mask[id] |= 1 << ship
	world.ships.fled_count[ship] += 1
	_leave(world, ship)
	world.emit(&"fled", ship, seen_by, id, Vector3.ZERO, _scenario(world, id))
	if seen_by >= 0:
		_charge_flee(world, ship, seen_by)


## Docked ships out of the fight (step 4, w-ckm).
static func _check_docked(world: SimWorld, id: int) -> void:
	for ship: int in _ships(world.encounters.ships_mask[id]):
		if world.ships.encounter[ship] != id or not world.is_crew_in_play(ship):
			continue
		if world.helm.docked_site[ship] >= 0 and hostile_seeing(world, ship, false) >= 0:
			_flee(world, id, ship, hostile_seeing(world, ship))


## Crippling and limping home (step 3); true when a ship limped home and ended the encounter.
static func _check_limp(world: SimWorld, id: int) -> bool:
	var def: RunDef = world.run_def
	if def == null or def.limp_home_time <= 0.0:
		return false
	var ships: ShipStateTable = world.ships
	var docked: Dictionary[int, bool] = _ships_with(world, &"docked")
	for ship: int in _ships(world.encounters.ships_mask[id]):
		if ships.encounter[ship] != id or not world.is_crew_in_play(ship):
			continue
		if not world.kin.is_alive(ship):
			continue
		var at: int = ships.crippled_tick[ship]
		if at < 0:
			if crippled(world, ship):
				ships.crippled_tick[ship] = world.tick
				world.emit(
					&"crippled", ship, id, def.limp_home_time, Vector3.ZERO, _scenario(world, id)
				)
			continue
		# Docked this tick, after it was crippled: a ship already docked does not limp home.
		if limping(world, ship) and at < world.tick and docked.has(ship):
			world.encounters.limped_mask[id] |= 1 << ship
			world.emit(&"limped_home", ship, id, world.helm.docked_site[ship])
			finish(world, id, EncounterTable.Result.PARTIAL)
			return true
	return false


## Whether the ship was crippled in its encounter less than RunDef.limp_home_time ago (gp-09).
static func limping(world: SimWorld, ship: int) -> bool:
	var at: int = world.ships.crippled_tick[ship]
	if at < 0 or world.run_def == null:
		return false
	return world.tick <= at + SimRate.ticks(world.run_def.limp_home_time)


## Whether the ship is crippled by the run's numbers (gp-09): hull fraction under
## RunDef.crippled_hull, or at least RunDef.crippled_subsystems subsystems at health 0.
static func crippled(world: SimWorld, ship: int) -> bool:
	var def: RunDef = world.run_def
	if def == null:
		return false
	if DamageSystem.hull_fraction(world, ship) < def.crippled_hull:
		return true
	if def.crippled_subsystems <= 0:
		return false
	var dead: int = 0
	var hull: int = world.damage.hull_row(ship)
	for r: int in range(hull + 1, hull + 1 + world.defs[ship].subsystems.size()):
		if world.damage.health[r] <= 0.0:
			dead += 1
	return dead >= def.crippled_subsystems


static func _check_losses(world: SimWorld, id: int) -> void:
	var table: EncounterTable = world.encounters
	var mask: int = table.ships_mask[id]
	for ship: int in _ships(mask):
		# A ship still in play and in this encounter stays; one reset out of it (FT-MIS-011)
		# or destroyed has left as a loss.
		if (
			world.ships.status[ship] == ShipStateTable.Status.IN_PLAY
			and world.ships.encounter[ship] == id
		):
			continue
		if EncounterTable.has_bit(table.losses_mask[id] | table.fled_mask[id], ship):
			continue
		table.losses_mask[id] |= 1 << ship
		if world.ships.encounter[ship] == id:
			_leave(world, ship)
	if (table.losses_mask[id] | table.fled_mask[id]) == mask:
		var lost: bool = table.losses_mask[id] != 0
		finish(world, id, EncounterTable.Result.LOST if lost else EncounterTable.Result.FLED)


## A ship leaves its encounter: one more done, no longer in one or crippled in one.
static func _leave(world: SimWorld, ship: int) -> void:
	world.ships.encounter[ship] = -1
	world.ships.crippled_tick[ship] = -1
	world.ships.limp_seen_by[ship] = -1
	world.ships.encounters_done[ship] += 1


## The first live ship spawned since the ship's encounter opened (w-fng: leftovers of older
## encounters, D326, and the travel legs they sit on don't count) of a faction hostile to the
## ship's that detects it (D233), or -1. With need_detect false (step 4, w-ckm), instead one
## of a faction other than Factions.DEBRIS in the fight, seen or not: within the ship's
## sensor_range of the ship or of its encounter's site.
static func hostile_seeing(world: SimWorld, ship: int, need_detect: bool = true) -> int:
	var faction: int = world.faction_of(ship)
	var e: int = world.ships.encounter[ship]
	var first: int = world.encounters.npc_floor[e] if e >= 0 else 0
	var reach: float = world.defs[ship].sensor_range
	for o: int in range(first, world.ship_count()):
		if o == ship or not world.kin.is_alive(o):
			continue
		var f: int = world.faction_of(o)
		if not world.is_hostile(faction, f):
			continue
		if need_detect:
			if KnowledgeSystem.is_detected(world, f, ship):
				return o
		elif (
			f != Factions.DEBRIS
			and (
				world.kin.relative(ship, o).length() <= reach
				or (
					e >= 0
					and SiteTable.offset_to(world, o, world.encounters.site[e]).length() <= reach
				)
			)
		):
			return o
	return -1


## Ships that emitted `kind` during this tick (events of the tick being stepped).
static func _ships_with(world: SimWorld, kind: StringName) -> Dictionary[int, bool]:
	var out: Dictionary[int, bool] = {}
	var events: Array[SimEvent] = world.events
	var i: int = events.size() - 1
	while i >= 0 and events[i].tick == world.tick:
		if events[i].kind == kind:
			out[events[i].ship_id] = true
		i -= 1
	return out


static func _timeout_ticks(world: SimWorld) -> int:
	if world.run_def == null:
		return 0
	return SimRate.ticks(world.run_def.director.arrival_timeout)


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
