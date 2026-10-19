class_name ShieldSystem
extends RefCounted
## Shields (T031): one focus direction set by Helm, total power (shield pips) and focus
## tightness set by Engineering (FT-SIM-018, D16). A hit absorbs
## 1 - exp(-absorption * power * coverage) of its energy, drawn from the shield's
## strength (FT-SIM-019); coverage is a lobe around the focus whose mean over all
## directions is 1, so tightening moves protection from the far side to the focus.
## There is no frequency mechanic (FT-SIM-017, D28).


## Regenerates strength with power, tracks the focus target and raises the low-shield
## alert (FT-SIM-031).
static func step(world: SimWorld) -> void:
	var t: ShieldTable = world.shields
	for s: int in t.size():
		if not world.kin.is_alive(s):
			continue
		var def: ShieldDef = world.defs[s].shields
		_track(world, s)
		var regen: float = def.regen_rate * power(world, s) * SimWorld.DT
		t.strength[s] = minf(t.strength[s] + regen, def.max_strength)
		var fraction: float = t.strength[s] / def.max_strength
		if fraction <= def.low_alert_fraction and t.low_armed[s] == 1:
			t.low_armed[s] = 0
			world.emit(&"shield_low", s, -1, fraction)
		elif fraction > def.low_alert_fraction and t.low_armed[s] == 0:
			t.low_armed[s] = 1


## Returns the energy that passes the shields (J); the absorbed part comes off strength.
static func absorb(world: SimWorld, hit: SimHit) -> float:
	var s: int = hit.target_id
	var absorbed: float = minf(
		hit.energy * absorb_fraction(world, s, hit.from_local), world.shields.strength[s]
	)
	absorbed = maxf(absorbed, 0.0)
	world.shields.strength[s] -= absorbed
	return hit.energy - absorbed


## Share of a hit from a ship-frame direction the shields would absorb now, before the
## strength limit (FT-SIM-019); also gives Engineering's per-face strength (FT-ENG-007).
static func absorb_fraction(world: SimWorld, ship_id: int, from_local: Vector3) -> float:
	var def: ShieldDef = world.defs[ship_id].shields
	var c: float = world.shields.focus[ship_id].dot(from_local.normalized())
	var g: float = coverage(world.shields.tightness[ship_id], c)
	return 1.0 - exp(-def.absorption * power(world, ship_id) * g)


## Shield power (dimensionless): shield pips over nominal times shield effectiveness.
static func power(world: SimWorld, ship_id: int) -> float:
	var k: int = SubsystemDef.Kind.SHIELDS
	return (
		PowerSystem.power_ratio(world, ship_id, k)
		* PowerSystem.kind_effectiveness(world, ship_id, k)
	)


## Coverage lobe (dimensionless) at cos_angle from the focus for a tightness k:
## k e^(k cos) / sinh k (a von Mises-Fisher density times 4 pi), whose mean over the
## sphere is 1; tightness 0 gives 1 everywhere (an even spread).
static func coverage(k: float, cos_angle: float) -> float:
	if k < 1e-6:
		return 1.0
	return 2.0 * k * exp(k * (cos_angle - 1.0)) / (1.0 - exp(-2.0 * k))


## Engineering sets shield power (pips, -1 keeps them) and tightness (-1 keeps it);
## rejects tightness outside the definition's range or pips over the cap, changing
## nothing (FT-ENG-003).
static func set_power_and_tightness(
	world: SimWorld, ship_id: int, pips: int, new_tightness: float
) -> bool:
	var def: ShieldDef = world.defs[ship_id].shields
	var keep: bool = new_tightness < 0.0
	if not keep and (new_tightness < def.tightness_min or new_tightness > def.tightness_max):
		return false
	if pips >= 0 and not PowerSystem.set_pips(world, ship_id, SubsystemDef.Kind.SHIELDS, pips):
		return false
	if not keep:
		world.shields.tightness[ship_id] = new_tightness
	return true


## Helm sets the focus direction (ship frame), or tracks another ship at the same site
## when target >= 0 (D48, FT-HLM-010). Rejects a zero direction or an invalid target.
static func set_focus(world: SimWorld, ship_id: int, direction: Vector3, target: int) -> bool:
	if target >= 0:
		var ok: bool = (
			target < world.ship_count()
			and target != ship_id
			and world.kin.is_alive(target)
			and world.kin.same_site(ship_id, target)
		)
		if not ok:
			return false
		world.shields.track_id[ship_id] = target
		_track(world, ship_id)
		return true
	if direction.length() < 1e-6:
		return false
	world.shields.track_id[ship_id] = -1
	world.shields.focus[ship_id] = direction.normalized()
	return true


## Points a tracking focus at its target; drops the track once the target is gone.
static func _track(world: SimWorld, s: int) -> void:
	var target: int = world.shields.track_id[s]
	if target < 0:
		return
	var kin: Kinematics = world.kin
	if not kin.is_alive(target) or not kin.same_site(s, target):
		world.shields.track_id[s] = -1
		return
	var local: Vector3 = kin.to_local(s, kin.relative(s, target))
	if local.length() > 1e-6:
		world.shields.focus[s] = local.normalized()
