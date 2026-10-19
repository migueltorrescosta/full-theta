class_name PowerSystem
extends RefCounted
## Power bus PWR (T030, spec §7.1): pips per subsystem within the reactor cap, overcharge
## heat and heat faults (FT-SIM-026), the boost (P1), the weapons energy store, and the
## thrust envelope it writes to kin.thrust_scale / kin.torque_scale each tick
## (FT-SIM-006).

## A subsystem may fault again once its heat falls below this share of its threshold;
## the gap keeps a fault from re-firing while heat hovers at the threshold.
const FAULT_REARM: float = 0.8


static func step(world: SimWorld) -> void:
	var t: PowerTable = world.power
	for s: int in t.size():
		if not world.kin.is_alive(s):
			continue
		var def: ShipDef = world.defs[s]
		for i: int in def.subsystems.size():
			_step_heat(world, s, i)
		var charge: float = (
			def.power.reactor_output
			* _pips_of(world, s, SubsystemDef.Kind.WEAPONS)
			/ def.power.reactor_pips
			* SimWorld.DT
		)
		t.weapon_energy[s] = minf(t.weapon_energy[s] + charge, def.power.weapons_capacity)
		world.kin.thrust_scale[s] = kind_envelope(world, s, SubsystemDef.Kind.ENGINES)
		world.kin.torque_scale[s] = kind_envelope(world, s, SubsystemDef.Kind.THRUSTERS)
		# Last, so a boost of n ticks raises heat and the envelope for exactly n ticks.
		if t.boost_ticks[s] > 0:
			t.boost_ticks[s] -= 1


## Draws energy for a shot or other use (J); false, and nothing drawn, if not enough.
static func draw_energy(world: SimWorld, ship_id: int, joules: float) -> bool:
	if joules > world.power.weapon_energy[ship_id]:
		return false
	world.power.weapon_energy[ship_id] -= maxf(joules, 0.0)
	return true


## Sets the pips of the ship's first subsystem of a kind (FT-ENG-002). Rejects the
## reactor, a missing kind, pips outside [0, max_pips_per_subsystem] and a total over
## reactor_pips; nothing changes when rejected.
static func set_pips(world: SimWorld, ship_id: int, kind: int, pips: int) -> bool:
	var def: ShipDef = world.defs[ship_id]
	var i: int = subsystem_index(def, kind)
	if i < 0 or kind == SubsystemDef.Kind.REACTOR:
		return false
	if pips < 0 or pips > def.power.max_pips_per_subsystem:
		return false
	var d: DamageTable = world.damage
	var first: int = d.subsystem_row(ship_id, 0)
	var total: int = 0
	for r: int in range(first, first + def.subsystems.size()):
		total += d.pips[r]
	if total - d.pips[first + i] + pips > def.power.reactor_pips:
		return false
	d.pips[first + i] = pips
	return true


## Starts a boost: engines and thrusters run at max_pips_per_subsystem for
## PowerDef.boost_duration, above the reactor cap, building overcharge heat (P1).
## Rejected while a boost runs.
static func boost(world: SimWorld, ship_id: int) -> bool:
	if world.power.boost_ticks[ship_id] > 0:
		return false
	var duration: float = world.defs[ship_id].power.boost_duration
	world.power.boost_ticks[ship_id] = roundi(duration * SimWorld.HZ)
	return true


## Pips subsystem i draws now (count): the set pips, or the maximum during a boost for
## engines and thrusters.
static func effective_pips(world: SimWorld, ship_id: int, i: int) -> int:
	var def: ShipDef = world.defs[ship_id]
	var kind: int = def.subsystems[i].kind
	var boosted: bool = kind == SubsystemDef.Kind.ENGINES or kind == SubsystemDef.Kind.THRUSTERS
	if boosted and world.power.boost_ticks[ship_id] > 0:
		return def.power.max_pips_per_subsystem
	return world.damage.pips[world.damage.subsystem_row(ship_id, i)]


## Effective pips of a kind over its nominal pips (dimensionless); 1 when the ship has
## no such subsystem or its nominal is 0.
static func power_ratio(world: SimWorld, ship_id: int, kind: int) -> float:
	var nominal: int = 0
	for s: SubsystemDef in world.defs[ship_id].subsystems:
		if s.kind == kind:
			nominal += s.nominal_pips
	if nominal == 0:
		return 1.0
	return float(_pips_of(world, ship_id, kind)) / nominal


## Mean effectiveness of the ship's subsystems of a kind (0..1; 1 if none, FT-SIM-021).
static func kind_effectiveness(world: SimWorld, ship_id: int, kind: int) -> float:
	var total: float = 0.0
	var n: int = 0
	var subs: Array[SubsystemDef] = world.defs[ship_id].subsystems
	for i: int in subs.size():
		if subs[i].kind == kind:
			total += DamageSystem.effectiveness_at(world, ship_id, i)
			n += 1
	return total / n if n > 0 else 1.0


## Highest heat over threshold among the ship's subsystems of a kind (dimensionless).
static func heat_ratio(world: SimWorld, ship_id: int, kind: int) -> float:
	var def: ShipDef = world.defs[ship_id]
	var first: int = world.damage.subsystem_row(ship_id, 0)
	var r: float = 0.0
	for i: int in def.subsystems.size():
		var s: SubsystemDef = def.subsystems[i]
		if s.kind == kind:
			r = maxf(r, world.damage.heat[first + i] / s.fault_heat_threshold)
	return r


## Envelope scale of the ship's engines or thrusters now (FT-SIM-006).
static func kind_envelope(world: SimWorld, ship_id: int, kind: int) -> float:
	return envelope(
		world.defs[ship_id].power,
		power_ratio(world, ship_id, kind),
		kind_effectiveness(world, ship_id, kind),
		heat_ratio(world, ship_id, kind)
	)


## The envelope function (FT-SIM-006): envelope_curve(pip ratio) * effectiveness *
## heat_derate(heat ratio). Nominal pips, full health and no heat give 1.
static func envelope(
	power: PowerDef, pip_ratio: float, effectiveness: float, heat_over_threshold: float
) -> float:
	return (
		curve_at(power.envelope_curve, pip_ratio)
		* effectiveness
		* curve_at(power.heat_derate, heat_over_threshold)
	)


## Piecewise-linear curve through ascending points, clamped past the ends; 1 for an
## empty curve. Also samples subsystem effectiveness curves (FT-SIM-021).
static func curve_at(curve: PackedVector2Array, x: float) -> float:
	var n: int = curve.size()
	if n == 0:
		return 1.0
	if x <= curve[0].x:
		return curve[0].y
	for i: int in range(1, n):
		if x <= curve[i].x:
			var a: Vector2 = curve[i - 1]
			var b: Vector2 = curve[i]
			return lerpf(a.y, b.y, (x - a.x) / (b.x - a.x))
	return curve[n - 1].y


## Index of the ship's first subsystem of a kind, or -1.
static func subsystem_index(def: ShipDef, kind: int) -> int:
	for i: int in def.subsystems.size():
		if def.subsystems[i].kind == kind:
			return i
	return -1


## Heat for one tick: dT/dt = heat_per_overcharge_pip * overcharge - heat_dissipation * T,
## stepped exactly; past fault_heat_threshold a fault damages the subsystem once
## (FT-SIM-026).
static func _step_heat(world: SimWorld, s: int, i: int) -> void:
	var sd: SubsystemDef = world.defs[s].subsystems[i]
	var over: int = maxi(effective_pips(world, s, i) - sd.nominal_pips, 0)
	var q: float = sd.heat_per_overcharge_pip * over
	var k: float = sd.heat_dissipation
	var d: DamageTable = world.damage
	var r: int = d.subsystem_row(s, i)
	var h: float = d.heat[r]
	if k > 0.0:
		h = q / k + (h - q / k) * exp(-k * SimWorld.DT)
	else:
		h += q * SimWorld.DT
	d.heat[r] = h
	if h > sd.fault_heat_threshold and d.fault_armed[r] == 1:
		d.fault_armed[r] = 0
		DamageSystem.damage_subsystem(world, s, i, sd.heat_fault_damage)
		world.emit(&"fault", s, -1, h, Vector3.ZERO, sd.id)
	elif h < sd.fault_heat_threshold * FAULT_REARM and d.fault_armed[r] == 0:
		d.fault_armed[r] = 1


## Sum of effective pips over the ship's subsystems of a kind (count).
static func _pips_of(world: SimWorld, ship_id: int, kind: int) -> int:
	var def: ShipDef = world.defs[ship_id]
	var total: int = 0
	for i: int in def.subsystems.size():
		if def.subsystems[i].kind == kind:
			total += effective_pips(world, ship_id, i)
	return total
