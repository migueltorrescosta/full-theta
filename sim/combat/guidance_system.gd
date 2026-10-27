class_name GuidanceSystem
extends RefCounted
## Steers guided ordnance (missiles and torpedoes, FT-SIM-013, FT-WPN-008, P8). Each tick,
## before collisions, a projectile with a turn rate turns its velocity toward the tracked
## contact it follows, at most turn_rate * dt and keeping its speed; the turn rate is cut by
## the track's quality (D214, track_quality). A contact the shooter's faction stops
## tracking, or that is destroyed, is dropped: the ordnance then flies
## on straight (&"guidance_lost" on the shooter, other_id the contact).

## The least quality of a track (dimensionless): a tracked contact is never quite lost.
const MIN_QUALITY: float = 0.05


## Whether the faction tracks the ship, so ordnance may be fired at it and keep
## following it: its own sensors, or a friendly probe's coverage (P8, FT-WPN-008).
static func is_tracked(world: SimWorld, faction: int, ship_id: int) -> bool:
	if ship_id < 0 or ship_id >= world.ship_count() or not world.kin.is_alive(ship_id):
		return false
	if KnowledgeSystem.is_detected(world, faction, ship_id):
		return true
	var p: PackedFloat64Array = world.kin.point_at(ship_id, Vector3.ZERO)
	return ProbeSystem.coverage_at(world, faction, Vector3(p[0], p[1], p[2]))


## How good the faction's track of the ship is, 0..1 (D214, FT-WPN-007, P8): 0 when it is
## not tracked; 1 for its own ships; else the better of its own sensors' (closeness within
## each sensor range, cut by the scan noise of the sensors' mode and pips) and a deployed
## probe's (closeness within its bubble). Guided ordnance turns at WeaponDef.track_floor
## up to its full turn rate by this; Weapons' track feed draws it as a bar.
static func track_quality(world: SimWorld, faction: int, ship_id: int) -> float:
	if not is_tracked(world, faction, ship_id):
		return 0.0
	if world.faction_of(ship_id) == faction:
		return 1.0
	var kin: Kinematics = world.kin
	var best: float = 0.0
	for o: int in world.ship_count():
		if kin.factions[o] != faction or not kin.is_alive(o) or not kin.can_reach(o, ship_id):
			continue
		var reach: float = (
			world.defs[o].sensor_range * DamageSystem.effectiveness(world, o, &"sensors")
		)
		if reach <= 0.0:
			continue
		var close: float = 1.0 - kin.relative(o, ship_id).length() / reach
		var noise: float = 0.0
		if world.science_def != null:
			noise = ScienceSystem.contact_noise(world, o, ship_id)
		best = maxf(best, close * (1.0 - noise))
	var p: PackedFloat64Array = kin.point_at(ship_id, Vector3.ZERO)
	var probes: ProbeTable = world.probes
	for r: int in probes.size():
		if probes.factions[r] != faction or probes.deployed[r] == 0:
			continue
		var off: Vector3 = Vector3(
			kin.wrap(p[0] - probes.at_x[r]),
			kin.wrap(p[1] - probes.at_y[r]),
			kin.wrap(p[2] - probes.at_z[r])
		)
		best = maxf(best, 1.0 - off.length() / world.defs[probes.ship_ids[r]].probe_range)
	return clampf(best, MIN_QUALITY, 1.0)


static func step(world: SimWorld) -> void:
	var proj: ProjectileTable = world.projectiles
	var kin: Kinematics = world.kin
	# One quality per faction and contact and tick.
	var quality: Dictionary[int, float] = {}
	for k: int in proj.size():
		if proj.turn_rate[k] <= 0.0:
			continue
		var want: Variant = null
		var rate: float = proj.turn_rate[k]
		var target: int = proj.guide_target[k]
		if target >= 0:
			if is_tracked(world, proj.factions[k], target):
				want = proj.offset_to_ship(k, kin, target)
				var key: int = proj.factions[k] * 65536 + target
				if not quality.has(key):
					quality[key] = track_quality(world, proj.factions[k], target)
				rate *= lerpf(proj.track_floor[k], 1.0, quality[key])
			else:
				world.emit(&"guidance_lost", proj.ship_ids[k], target)
				proj.guide_target[k] = -1
		if want == null:
			continue
		var to: Vector3 = want
		var v: Vector3 = proj.vel[k]
		var speed: float = v.length()
		if to.length_squared() < 1e-12 or speed < 1e-9:
			continue
		proj.vel[k] = (
			WeaponSystem.turn_toward(v / speed, to.normalized(), rate * SimWorld.DT) * speed
		)
