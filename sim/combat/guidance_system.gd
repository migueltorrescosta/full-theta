class_name GuidanceSystem
extends RefCounted
## Steers guided ordnance (missiles and torpedoes, FT-SIM-013, FT-WPN-008, P8). Each tick,
## before collisions, a projectile with a turn rate turns its velocity toward the tracked
## contact it follows, else toward its guide point, at most turn_rate * dt and keeping
## its speed. A contact the shooter's faction stops tracking, or that is destroyed or at
## another site, is dropped: the ordnance then flies on straight (&"guidance_lost" on
## the shooter, other_id the contact).


## Whether the faction tracks the ship, so ordnance may be fired at it and keep
## following it: its own sensors, or a friendly probe's coverage (P8, FT-WPN-008).
static func is_tracked(world: SimWorld, faction: int, ship_id: int) -> bool:
	if ship_id < 0 or ship_id >= world.ship_count() or not world.kin.is_alive(ship_id):
		return false
	if KnowledgeSystem.is_detected(world, faction, ship_id):
		return true
	var p: PackedFloat64Array = world.kin.point_at(ship_id, Vector3.ZERO)
	return ProbeSystem.coverage_at(
		world, faction, Vector3(p[0], p[1], p[2]), world.kin.site[ship_id]
	)


static func step(world: SimWorld) -> void:
	var proj: ProjectileTable = world.projectiles
	var kin: Kinematics = world.kin
	for k: int in proj.size():
		if proj.turn_rate[k] <= 0.0:
			continue
		var want: Variant = null
		var target: int = proj.guide_target[k]
		if target >= 0:
			if kin.site[target] == proj.site[k] and is_tracked(world, proj.factions[k], target):
				want = proj.offset_to_ship(k, kin, target)
			else:
				world.emit(&"guidance_lost", proj.ship_ids[k], target)
				proj.guide_target[k] = -1
				if proj.guide_point[k] == 1:
					want = proj.offset_to_guide_point(k, kin)
		elif proj.guide_point[k] == 1:
			want = proj.offset_to_guide_point(k, kin)
		if want == null:
			continue
		var to: Vector3 = want
		var v: Vector3 = proj.vel[k]
		var speed: float = v.length()
		if to.length_squared() < 1e-12 or speed < 1e-9:
			continue
		proj.vel[k] = (
			WeaponSystem.turn_toward(v / speed, to.normalized(), proj.turn_rate[k] * SimWorld.DT)
			* speed
		)
