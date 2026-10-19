class_name DamageSystem
extends RefCounted
## Hull and subsystem damage by hit location, and repair crews with spare parts (T033).
## Damage is a pure function of the hit energy and the table state: no random draws and
## no outcome forcing (FT-SIM-029).
##
## Events (FT-SIM-030), all on the damaged ship:
## - &"subsystem_damaged": tag subsystem id, value health fraction after, vector the
##   subsystem position (ship frame, for hit markers), other_id the source ship or -1.
## - &"subsystem_destroyed": the subsystem's health reached 0 (same fields).
## - &"destroyed": the hull reached 0; other_id the source ship or -1.
## - &"repair_started", &"repair_finished", &"repair_recalled", &"repair_no_parts":
##   tag subsystem id, value the crew number.


## Repairs: each crew on a subsystem restores its repair_rate (J/s) per tick; when the
## subsystem is whole, its crews go idle (FT-SIM-024).
static func step(world: SimWorld) -> void:
	var t: DamageTable = world.damage
	for ship: int in world.ship_count():
		if not world.kin.is_alive(ship):
			continue
		var subs: Array[SubsystemDef] = world.defs[ship].subsystems
		var h: int = t.hull_row(ship)
		for i: int in subs.size():
			var r: int = h + 1 + i
			var mask: int = t.crews[r]
			if mask == 0:
				continue
			var s: SubsystemDef = subs[i]
			t.health[r] = minf(
				s.health_max, t.health[r] + s.repair_rate * _count(mask) * SimWorld.DT
			)
			if t.health[r] >= s.health_max:
				t.crews[r] = 0
				for c: int in DamageTable.MAX_CREWS:
					if mask & (1 << c):
						world.emit(&"repair_finished", ship, -1, c, s.position, s.id)


## Applies the energy that passed the shields, split between the subsystem nearest the
## impact point (subsystem_damage_share of it) and the hull (the rest); a ship without
## subsystems puts it all on the hull (FT-SIM-020, owner decision Q5 B).
static func apply_hit(world: SimWorld, hit: SimHit, energy: float) -> void:
	var ship: int = hit.target_id
	if energy <= 0.0 or not world.kin.is_alive(ship):
		return
	var def: ShipDef = world.defs[ship]
	var i: int = nearest_subsystem(def, hit.point_local)
	var to_hull: float = energy
	if i >= 0:
		var to_subsystem: float = energy * def.subsystem_damage_share
		to_hull -= to_subsystem
		_damage_row(world, ship, i, to_subsystem, hit.source_id)
	var t: DamageTable = world.damage
	var h: int = t.hull_row(ship)
	t.health[h] = maxf(0.0, t.health[h] - to_hull)
	if t.health[h] <= 0.0:
		world.kin.alive[ship] = 0
		world.emit(&"destroyed", ship, hit.source_id)


## Index in def.subsystems of the subsystem nearest the point (ship frame), or -1; the
## lower index wins a tie (FT-SIM-020, D26).
static func nearest_subsystem(def: ShipDef, point_local: Vector3) -> int:
	var best: int = -1
	var best_d2: float = INF
	for i: int in def.subsystems.size():
		var d2: float = def.subsystems[i].position.distance_squared_to(point_local)
		if d2 < best_d2:
			best = i
			best_d2 = d2
	return best


## Effectiveness of the ship's subsystem, 0..1, from its health and the definition's
## curve (FT-SIM-021); 1 when the ship has no such subsystem.
static func effectiveness(world: SimWorld, ship_id: int, subsystem_id: StringName) -> float:
	var r: int = world.damage.find_subsystem(ship_id, subsystem_id)
	if r < 0:
		return 1.0
	return PowerSystem.curve_at(
		_sub_def(world, ship_id, r).effectiveness, health_fraction(world, ship_id, subsystem_id)
	)


## Hull left as a share of hull_max, 0..1.
static func hull_fraction(world: SimWorld, ship_id: int) -> float:
	var h: int = world.damage.hull_row(ship_id)
	if h < 0:
		return 1.0
	return world.damage.health[h] / world.defs[ship_id].hull_max


## Health left as a share of health_max, 0..1; 1 when the ship has no such subsystem.
static func health_fraction(world: SimWorld, ship_id: int, subsystem_id: StringName) -> float:
	var t: DamageTable = world.damage
	var r: int = t.find_subsystem(ship_id, subsystem_id)
	if r < 0:
		return 1.0
	return t.health[r] / _sub_def(world, ship_id, r).health_max


## Damages one subsystem directly (heat faults, FT-SIM-026); cause names the source. The
## &"subsystem_damaged" event carries the subsystem id as its tag, so the caller reports
## the cause in its own fault event.
static func damage_subsystem(
	world: SimWorld, ship_id: int, subsystem_id: StringName, energy: float, _cause: StringName
) -> void:
	if ship_id < 0 or ship_id >= world.ship_count() or not world.kin.is_alive(ship_id):
		return
	var t: DamageTable = world.damage
	var r: int = t.find_subsystem(ship_id, subsystem_id)
	if r >= 0:
		_damage_row(world, ship_id, r - t.hull_row(ship_id) - 1, energy, -1)


## Sends crew to repair the subsystem (FT-SIM-024, FT-M1-009). Each job takes the
## subsystem's parts_per_repair from stock when it starts; a crew already working
## elsewhere drops that job. Returns false, changing nothing, for an unknown crew or
## subsystem, a whole subsystem or a crew already there; with too few parts it also
## emits &"repair_no_parts" (no parts, no repair).
static func dispatch(world: SimWorld, ship_id: int, crew: int, subsystem_id: StringName) -> bool:
	var t: DamageTable = world.damage
	var def: ShipDef = world.defs[ship_id]
	var r: int = t.find_subsystem(ship_id, subsystem_id)
	if crew < 0 or crew >= def.repair_crews or r < 0:
		return false
	var h: int = t.hull_row(ship_id)
	var s: SubsystemDef = _sub_def(world, ship_id, r)
	if t.crews[r] & (1 << crew) or t.health[r] >= s.health_max:
		return false
	if t.spare_parts[h] < s.parts_per_repair:
		world.emit(&"repair_no_parts", ship_id, -1, crew, s.position, s.id)
		return false
	_unassign(t, ship_id, crew)
	t.spare_parts[h] -= s.parts_per_repair
	t.crews[r] |= 1 << crew
	world.emit(&"repair_started", ship_id, -1, crew, s.position, s.id)
	return true


## Calls the crew back from its job; false if it was idle. Parts already used stay used.
static func recall(world: SimWorld, ship_id: int, crew: int) -> bool:
	var t: DamageTable = world.damage
	var r: int = _unassign(t, ship_id, crew)
	if r < 0:
		return false
	var s: SubsystemDef = _sub_def(world, ship_id, r)
	world.emit(&"repair_recalled", ship_id, -1, crew, s.position, s.id)
	return true


## Subsystem id the crew is working on, or &"" when idle.
static func crew_job(world: SimWorld, ship_id: int, crew: int) -> StringName:
	var t: DamageTable = world.damage
	for r: int in t.rows_of(ship_id):
		if crew >= 0 and t.crews[r] & (1 << crew):
			return t.part_ids[r]
	return &""


## Spare parts in stock (count).
static func spare_parts(world: SimWorld, ship_id: int) -> int:
	return world.damage.spare_parts[world.damage.hull_row(ship_id)]


static func _damage_row(
	world: SimWorld, ship_id: int, index: int, energy: float, source_id: int
) -> void:
	var t: DamageTable = world.damage
	var r: int = t.subsystem_row(ship_id, index)
	if energy <= 0.0 or t.health[r] <= 0.0:
		return
	var s: SubsystemDef = world.defs[ship_id].subsystems[index]
	t.health[r] = maxf(0.0, t.health[r] - energy)
	var frac: float = t.health[r] / s.health_max
	world.emit(&"subsystem_damaged", ship_id, source_id, frac, s.position, s.id)
	if t.health[r] <= 0.0:
		world.emit(&"subsystem_destroyed", ship_id, source_id, 0.0, s.position, s.id)


## The definition of the subsystem on a damage table row.
static func _sub_def(world: SimWorld, ship_id: int, row: int) -> SubsystemDef:
	return world.defs[ship_id].subsystems[row - world.damage.hull_row(ship_id) - 1]


## Clears the crew from whichever subsystem it works on; returns that row or -1.
static func _unassign(t: DamageTable, ship_id: int, crew: int) -> int:
	if crew < 0 or crew >= DamageTable.MAX_CREWS:
		return -1
	var bit: int = 1 << crew
	for r: int in t.rows_of(ship_id):
		if t.crews[r] & bit:
			t.crews[r] &= ~bit
			return r
	return -1


static func _count(mask: int) -> int:
	var n: int = 0
	while mask != 0:
		n += mask & 1
		mask >>= 1
	return n
