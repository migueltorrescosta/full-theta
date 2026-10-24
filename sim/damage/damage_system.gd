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
## - &"weak_point_hit": a hit on a revealed weak point (FT-SIM-023); tag subsystem id,
##   other_id the shooter.
## - &"fault_inflicted", &"fault_cause_revealed", &"fault_cause_picked", &"fault_cleared":
##   unknown-cause faults (FT-SIM-025); tag subsystem id. The events never name the cause
##   (Engineering sees symptoms only); fault_cause_revealed and fault_cause_picked carry
##   the cause's index in SubsystemDef.fault_causes plus 1 as value.
## - &"hardened", &"harden_expired", &"harden_no_parts": FT-ENG-008; tag subsystem id.


## Repairs: each crew on a subsystem restores its repair_rate (J/s) per tick; when the
## subsystem is whole, its crews go idle (FT-SIM-024).
static func step(world: SimWorld) -> void:
	var t: DamageTable = world.damage
	var alive: PackedByteArray = world.kin.alive
	var crews: PackedInt32Array = t.crews
	var defs: Array[ShipDef] = world.defs
	for ship: int in world.ship_count():
		if alive[ship] != 1:
			continue
		var subs: Array[SubsystemDef] = defs[ship].subsystems
		var h: int = t.hull_row(ship)
		for i: int in subs.size():
			var r: int = h + 1 + i
			if t.hardened_ticks[r] > 0:
				t.hardened_ticks[r] -= 1
				if t.hardened_ticks[r] == 0:
					world.emit(&"harden_expired", ship, -1, 0.0, subs[i].position, subs[i].id)
			var mask: int = crews[r]
			if mask == 0:
				continue
			var s: SubsystemDef = subs[i]
			var gain: float = s.repair_rate * _count(mask) * SimWorld.DT
			# FT-SIM-025: a fault repairs at full rate only with its cause picked.
			if t.fault_cause[r] != &"" and t.fault_pick[r] != t.fault_cause[r]:
				gain *= s.fault_brute_force_factor
			t.health[r] = minf(s.health_max, t.health[r] + gain)
			if t.health[r] >= s.health_max:
				t.crews[r] = 0
				if t.fault_cause[r] != &"":
					_clear_fault(t, r)
					world.emit(&"fault_cleared", ship, -1, 0.0, s.position, s.id)
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
	var share: float = def.subsystem_damage_share
	var weak: int = _weak_point(world, hit)
	if weak >= 0:
		share = maxf(share, def.subsystems[weak].weak_point_share)
		var ws: SubsystemDef = def.subsystems[weak]
		world.emit(&"weak_point_hit", ship, hit.source_id, energy, ws.position, ws.id)
	var left: float = energy * share if def.subsystems.size() > 0 else 0.0
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


## Index of the weak point a hit lands on, or -1 (FT-SIM-023, P7): the subsystem nearest
## the impact is a weak point that the shooter's faction has had revealed. Collisions
## have no aim, so never hit one.
static func _weak_point(world: SimWorld, hit: SimHit) -> int:
	if hit.source_id < 0 or hit.kind == &"collision":
		return -1
	var subs: Array[SubsystemDef] = world.defs[hit.target_id].subsystems
	var any: bool = false
	for s: SubsystemDef in subs:
		any = any or s.weak_point
	if not any:
		return -1
	var i: int = _nearest_live(world, hit.target_id, hit.point_local)
	if i < 0 or not subs[i].weak_point:
		return -1
	var faction: int = world.faction_of(hit.source_id)
	if KnowledgeSystem.knows_weak_point(world, faction, hit.target_id, subs[i].id):
		return i
	return -1


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
	var t: DamageTable = world.damage
	var r: int = t.find_subsystem(ship_id, subsystem_id)
	if r < 0:
		return 1.0
	return t.row_effectiveness(r, world.defs[ship_id].subsystems[r - t.hull_row(ship_id) - 1])


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


## Gives the subsystem an unknown-cause fault (FT-SIM-025, P10): damages it by energy
## and records the true cause, hidden until revealed. False, changing nothing, for an
## unknown subsystem, a cause the subsystem doesn't list or energy not above 0.
static func inflict_fault(
	world: SimWorld, ship_id: int, subsystem_id: StringName, cause: StringName, energy: float
) -> bool:
	var t: DamageTable = world.damage
	var r: int = t.find_subsystem(ship_id, subsystem_id)
	if r < 0 or not (energy > 0.0) or not _sub_def(world, ship_id, r).fault_causes.has(cause):
		return false
	_clear_fault(t, r)
	t.fault_cause[r] = cause
	_damage_row(world, ship_id, r - t.hull_row(ship_id) - 1, energy, -1)
	world.emit(
		&"fault_inflicted", ship_id, -1, 0.0, _sub_def(world, ship_id, r).position, subsystem_id
	)
	return true


## Science's own-ship scan names the fault's cause (FT-SIM-025, P10). With prefill
## (Easy's diagnosed-cause shortcut, FT-ENG-006) it also becomes Engineering's pick unless
## one is set. False when the subsystem has no fault.
static func reveal_fault_cause(
	world: SimWorld, ship_id: int, subsystem_id: StringName, prefill: bool = false
) -> bool:
	var t: DamageTable = world.damage
	var r: int = t.find_subsystem(ship_id, subsystem_id)
	if r < 0 or t.fault_cause[r] == &"":
		return false
	t.fault_known[r] = 1
	if prefill and t.fault_pick[r] == &"":
		t.fault_pick[r] = t.fault_cause[r]
	var s: SubsystemDef = _sub_def(world, ship_id, r)
	world.emit(
		&"fault_cause_revealed",
		ship_id,
		-1,
		s.fault_causes.find(t.fault_cause[r]) + 1.0,
		s.position,
		s.id
	)
	return true


## Engineering picks the cause of a subsystem's fault (FT-ENG-006); a wrong guess is
## allowed and repairs at the brute-force rate. False for a subsystem without a fault or
## a cause it doesn't list.
static func pick_fault_cause(
	world: SimWorld, ship_id: int, subsystem_id: StringName, cause: StringName
) -> bool:
	var t: DamageTable = world.damage
	var r: int = t.find_subsystem(ship_id, subsystem_id)
	if r < 0 or t.fault_cause[r] == &"":
		return false
	var s: SubsystemDef = _sub_def(world, ship_id, r)
	var at: int = s.fault_causes.find(cause)
	if at < 0:
		return false
	t.fault_pick[r] = cause
	world.emit(&"fault_cause_picked", ship_id, -1, at + 1.0, s.position, s.id)
	return true


## The cause of the subsystem's fault as the station may see it: the true cause once
## revealed, else &"" (unknown or no fault).
static func known_fault_cause(
	world: SimWorld, ship_id: int, subsystem_id: StringName
) -> StringName:
	var t: DamageTable = world.damage
	var r: int = t.find_subsystem(ship_id, subsystem_id)
	if r < 0 or t.fault_known[r] == 0:
		return &""
	return t.fault_cause[r]


## Pre-hardens the subsystem for its harden_duration (FT-ENG-008, P11): hits and faults
## then do harden_factor of their damage to it. Takes harden_parts from the spare parts;
## refused (false, nothing changed) for an unknown subsystem or one already hardened,
## and with too few parts it also emits &"harden_no_parts".
static func harden(world: SimWorld, ship_id: int, subsystem_id: StringName) -> bool:
	var t: DamageTable = world.damage
	var r: int = t.find_subsystem(ship_id, subsystem_id)
	if r < 0 or t.hardened_ticks[r] > 0:
		return false
	var s: SubsystemDef = _sub_def(world, ship_id, r)
	var h: int = t.hull_row(ship_id)
	if t.spare_parts[h] < s.harden_parts:
		world.emit(&"harden_no_parts", ship_id, -1, 0.0, s.position, s.id)
		return false
	t.spare_parts[h] -= s.harden_parts
	t.hardened_ticks[r] = ceili(s.harden_duration * SimWorld.HZ)
	world.emit(&"hardened", ship_id, -1, s.harden_duration, s.position, s.id)
	return true


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
	var overflow: float = 0.0
	if t.hardened_ticks[r] > 0:
		# FT-ENG-008: a hardened subsystem takes harden_factor of the energy; what it
		# can't absorb is the energy beyond the part that would finish it.
		var dealt: float = energy * s.harden_factor
		if dealt > t.health[r]:
			overflow = energy - t.health[r] / s.harden_factor
		t.health[r] = maxf(0.0, t.health[r] - dealt)
	else:
		overflow = maxf(0.0, energy - t.health[r])
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


static func _clear_fault(t: DamageTable, r: int) -> void:
	t.fault_cause[r] = &""
	t.fault_known[r] = 0
	t.fault_pick[r] = &""


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
