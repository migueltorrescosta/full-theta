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


## Applies the energy that passed the shields, split between the subsystems
## (subsystem_damage_share of it) and the hull (the rest); a ship without subsystems puts
## it all on the hull (FT-SIM-020, D116, owner decision Q5 B). The subsystem share goes
## to the live subsystem nearest the impact point; what it can't absorb (the part beyond
## its remaining health) passes to the next-nearest live one, and so on, then to the
## hull when none is left, so hull and subsystems together take the whole energy (D123).
static func apply_hit(world: SimWorld, hit: SimHit, energy: float) -> void:
	var ship: int = hit.target_id
	if energy <= 0.0 or not world.kin.is_alive(ship):
		return
	var def: ShipDef = world.defs[ship]
	var left: float = energy * def.subsystem_damage_share if def.subsystems.size() > 0 else 0.0
	var to_hull: float = energy - left
	# Each pass either absorbs the rest or destroys a subsystem, so this ends (D123).
	while left > 0.0:
		var i: int = _nearest_live(world, ship, hit.point_local)
		if i < 0:
			break
		left = _damage_row(world, ship, i, left, hit.source_id)
	to_hull += left
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
	# DamageTable.find_subsystem and effectiveness_at inlined (hot path).
	var t: DamageTable = world.damage
	var h: int = t.hull_row(ship_id)
	if h < 0 or subsystem_id == DamageTable.HULL:
		return 1.0
	var r: int = h + 1
	var n: int = t.size()
	while r < n and t.ship_ids[r] == ship_id:
		if t.part_ids[r] == subsystem_id:
			return t.row_effectiveness(r, world.defs[ship_id].subsystems[r - h - 1])
		r += 1
	return 1.0


## Effectiveness of the ship's subsystem with that index in ShipDef.subsystems, 0..1
## (FT-SIM-021); the caller passes a valid index.
static func effectiveness_at(world: SimWorld, ship_id: int, i: int) -> float:
	var t: DamageTable = world.damage
	return t.row_effectiveness(t.subsystem_row(ship_id, i), world.defs[ship_id].subsystems[i])


## Hull left as a share of hull_max, 0..1.
static func hull_fraction(world: SimWorld, ship_id: int) -> float:
	var h: int = world.damage.hull_row(ship_id)
	if h < 0:
		return 1.0
	return world.damage.health[h] / world.defs[ship_id].hull_max


## Damages the ship's subsystem with that index in ShipDef.subsystems directly (heat
## faults, FT-SIM-026). The &"subsystem_damaged" event carries the subsystem id as its
## tag; the caller reports the cause in its own fault event. A fault damages only the
## subsystem that overheated: on a destroyed subsystem it changes nothing, and damage
## beyond its remaining health is dropped, not passed on (D123 covers hits only).
static func damage_subsystem(world: SimWorld, ship_id: int, i: int, energy: float) -> void:
	_damage_row(world, ship_id, i, energy, -1)


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
	_unassign(world, ship_id, crew)
	t.spare_parts[h] -= s.parts_per_repair
	t.crews[r] |= 1 << crew
	world.emit(&"repair_started", ship_id, -1, crew, s.position, s.id)
	return true


## Calls the crew back from its job; false if it was idle. Parts already used stay used.
static func recall(world: SimWorld, ship_id: int, crew: int) -> bool:
	var r: int = _unassign(world, ship_id, crew)
	if r < 0:
		return false
	var s: SubsystemDef = _sub_def(world, ship_id, r)
	world.emit(&"repair_recalled", ship_id, -1, crew, s.position, s.id)
	return true


## Damages one subsystem by up to its remaining health; returns the energy it couldn't
## absorb (all of it once destroyed, D123).
static func _damage_row(
	world: SimWorld, ship_id: int, index: int, energy: float, source_id: int
) -> float:
	var t: DamageTable = world.damage
	var r: int = t.subsystem_row(ship_id, index)
	if energy <= 0.0 or t.health[r] <= 0.0:
		return maxf(0.0, energy)
	var s: SubsystemDef = world.defs[ship_id].subsystems[index]
	var overflow: float = maxf(0.0, energy - t.health[r])
	t.health[r] = maxf(0.0, t.health[r] - energy)
	var frac: float = t.health[r] / s.health_max
	world.emit(&"subsystem_damaged", ship_id, source_id, frac, s.position, s.id)
	if t.health[r] <= 0.0:
		world.emit(&"subsystem_destroyed", ship_id, source_id, 0.0, s.position, s.id)
	return overflow


## Index of the live subsystem (health above 0) nearest the point (ship frame), or -1
## when none is live; the lower index wins a tie, as in nearest_subsystem (D123).
static func _nearest_live(world: SimWorld, ship_id: int, point_local: Vector3) -> int:
	var subs: Array[SubsystemDef] = world.defs[ship_id].subsystems
	var health: PackedFloat64Array = world.damage.health
	var first: int = world.damage.subsystem_row(ship_id, 0)
	var best: int = -1
	var best_d2: float = INF
	for i: int in subs.size():
		if health[first + i] <= 0.0:
			continue
		var d2: float = subs[i].position.distance_squared_to(point_local)
		if d2 < best_d2:
			best = i
			best_d2 = d2
	return best


## The definition of the subsystem on a damage table row.
static func _sub_def(world: SimWorld, ship_id: int, row: int) -> SubsystemDef:
	return world.defs[ship_id].subsystems[row - world.damage.hull_row(ship_id) - 1]


## Clears the crew from whichever subsystem it works on; returns that row or -1.
static func _unassign(world: SimWorld, ship_id: int, crew: int) -> int:
	if crew < 0 or crew >= DamageTable.MAX_CREWS:
		return -1
	var t: DamageTable = world.damage
	var bit: int = 1 << crew
	var first: int = t.subsystem_row(ship_id, 0)
	for r: int in range(first, first + world.defs[ship_id].subsystems.size()):
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
