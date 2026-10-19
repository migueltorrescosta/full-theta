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
## Hits resolve before ShieldSystem.step, so a tracking focus is the one from the
## previous tick's tracking (a one-tick lag, negligible).
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


## Engineering sets shield power (pips, exactly -1 keeps them) and tightness (exactly -1
## keeps it); rejects tightness outside the definition's range or not finite, pips over
## the cap and any other negative value, changing nothing (FT-ENG-003).
static func set_power_and_tightness(
	world: SimWorld, ship_id: int, pips: int, new_tightness: float
) -> bool:
	var def: ShieldDef = world.defs[ship_id].shields
	var keep: bool = new_tightness == -1.0
	var in_range: bool = new_tightness >= def.tightness_min and new_tightness <= def.tightness_max
	if not keep and not (is_finite(new_tightness) and in_range):
		return false
	if pips < -1:
		return false
	if pips >= 0 and not PowerSystem.set_pips(world, ship_id, SubsystemDef.Kind.SHIELDS, pips):
		return false
	if not keep:
		world.shields.tightness[ship_id] = new_tightness
	return true


## Helm sets the focus direction (ship frame), or tracks another ship at the same site
## when target >= 0 (D48, FT-HLM-010). Rejects a zero or non-finite direction, an invalid
## target and one its faction doesn't detect now (FT-ARC-013). A track lasts until Helm
## sets another focus; see _track.
static func set_focus(world: SimWorld, ship_id: int, direction: Vector3, target: int) -> bool:
	if target >= 0:
		if not _can_track(world, ship_id, target):
			return false
		world.shields.track_id[ship_id] = target
		_track(world, ship_id)
		return true
	if not direction.is_finite() or direction.length() < 1e-6:
		return false
	world.shields.track_id[ship_id] = -1
	world.shields.focus[ship_id] = direction.normalized()
	return true


## Points a tracking focus at its target. Like Helm's face, the track is kept while the
## target is out of reach or undetected: the focus stays where it last was (no ground
## truth leaks, FT-ARC-013) and follows again once the target is detected.
static func _track(world: SimWorld, s: int) -> void:
	var target: int = world.shields.track_id[s]
	if target < 0 or not _can_track(world, s, target):
		return
	var kin: Kinematics = world.kin
	var local: Vector3 = kin.to_local(s, kin.relative(s, target))
	if local.length() > 1e-6:
		world.shields.focus[s] = local.normalized()


static func _can_track(world: SimWorld, s: int, target: int) -> bool:
	return (
		world.kin.can_reach(s, target)
		and KnowledgeSystem.is_detected(world, world.faction_of(s), target)
	)
