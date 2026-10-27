class_name ModuleSystem
extends RefCounted
## Fits slot modules (FT-MIS-035, FT-MIS-022, FT-DAT-014, D86; PROVISIONAL Q6). The ship's
## effective definition is a copy of its base definition with the fitted modules' deltas
## applied; every system already reads world.defs, so a fit takes effect at once. The base
## stays in world.base_defs and is never changed (FT-ARC-020); the fitted modules are
## state (ModuleTable, hashed), the derived definition is not. Only stats the systems read
## every tick are on offer (ModuleDef.STATS); capacities set at spawn (hull, ammunition)
## don't change.

## Smallest factor a stat can reach, however many costs stack.
const MIN_FACTOR: float = 0.05


## Index of the module in SimWorld.module_defs, or -1.
static func index_of(world: SimWorld, module_id: StringName) -> int:
	for i: int in world.module_defs.size():
		if world.module_defs[i].id == module_id:
			return i
	return -1


## The module fitted in the ship's slot, or null (empty or no such slot).
static func fitted(world: SimWorld, ship: int, slot: int) -> ModuleDef:
	var r: int = world.modules.slot_row(ship, slot)
	if r < 0 or world.modules.module_ix[r] < 0:
		return null
	return world.module_defs[world.modules.module_ix[r]]


## Puts a module (or null for none) in a slot without any money changing hands, and
## refits. False for an unknown slot or a module of another type.
static func fit(world: SimWorld, ship: int, slot: int, module: ModuleDef) -> bool:
	var r: int = world.modules.slot_row(ship, slot)
	if r < 0:
		return false
	if module == null:
		world.modules.module_ix[r] = -1
	else:
		var ix: int = index_of(world, module.id)
		if ix < 0 or module.slot_type != world.modules.slot_type[r]:
			return false
		world.modules.module_ix[r] = ix
	refit(world, ship)
	return true


## Rebuilds world.defs[ship] from the base definition and the fitted modules.
static func refit(world: SimWorld, ship: int) -> void:
	var base: ShipDef = world.base_defs[ship]
	var sums: Dictionary[StringName, float] = {}
	for r: int in world.modules.rows_of(ship):
		var ix: int = world.modules.module_ix[r]
		if ix < 0:
			continue
		var module: ModuleDef = world.module_defs[ix]
		for stat: StringName in module.deltas:
			sums[stat] = sums.get(stat, 0.0) + module.deltas[stat]
	var def: ShipDef = base
	if not sums.is_empty():
		def = base.duplicate()
		for stat: StringName in sums:
			_apply(def, stat, maxf(1.0 + sums[stat], MIN_FACTOR))
	world.defs[ship] = def
	# Flight reads the kinematics columns, copied from the definition at spawn: carry the
	# module-scaled mass, inertia, thrust and torque there too.
	var kin: Kinematics = world.kin
	if ship >= 0 and ship < kin.size():
		kin.mass[ship] = def.mass
		kin.inertia[ship] = def.inertia
		kin.max_thrust_pos[ship] = def.max_thrust_pos
		kin.max_thrust_neg[ship] = def.max_thrust_neg
		kin.max_torque[ship] = def.max_torque


## Scales one stat of a private copy of the definition, copying the sub-resource first
## (duplicate() shares those, tests/README.md).
static func _apply(def: ShipDef, stat: StringName, factor: float) -> void:
	match stat:
		&"thrust":
			def.max_thrust_pos *= factor
			def.max_thrust_neg *= factor
		&"torque":
			def.max_torque *= factor
		&"mass":
			# Inertia grows with mass, so a heavy module slows turning as well (review 2 L4).
			def.mass *= factor
			def.inertia *= factor
		&"sensor_range":
			def.sensor_range *= factor
			def.identify_range = minf(def.identify_range, def.sensor_range)
		&"reactor_output":
			def.power = def.power.duplicate()
			def.power.reactor_output *= factor
		&"weapons_capacity":
			def.power = def.power.duplicate()
			def.power.weapons_capacity *= factor
		&"shield_strength":
			def.shields = def.shields.duplicate()
			def.shields.max_strength *= factor
		&"shield_regen":
			def.shields = def.shields.duplicate()
			def.shields.regen_rate *= factor
		&"heat_capacity", &"heat_dissipation", &"repair_rate":
			var subs: Array[SubsystemDef] = []
			for s: SubsystemDef in def.subsystems:
				var c: SubsystemDef = s.duplicate()
				match stat:
					&"heat_capacity":
						c.fault_heat_threshold *= factor
					&"heat_dissipation":
						c.heat_dissipation *= factor
					_:
						c.repair_rate *= factor
				subs.append(c)
			def.subsystems = subs
