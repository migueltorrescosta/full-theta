class_name HazardSystem
extends RefCounted
## Plays the world's hazards (D208, FT-RLY-004, P4, P11). Once per tick, before the
## integrator, for every live ship in id order:
## - a ZONE damages the ship inside it (damage_w J/s) and drags it (drag, the share of its
##   velocity removed per second). The damage goes to the hull, or to the named subsystems
##   in chunks every DAMAGE_EVERY ticks, so the events stay few;
## - a FRONT, a plane or an expanding sphere shell, hits a ship the tick its surface
##   reaches it, once (hit_j to the hull or to each named subsystem). A ship already behind
##   the surface when the front sets off is not hit.
## Nothing here is random: the geometry is a function of the tick, so a replay agrees.
## A faction knows of a hazard when its sensors reach the hazard's surface (detect_range) or
## a deployed probe's bubble does (known_to); HazardView shows those to Relay and
## Engineering. Events: &"hazard_hit" (ship; value = energy, tag = hazard id).

## Subsystem damage of a zone is applied every this many ticks.
const DAMAGE_EVERY: int = 6
## A front has reached a ship when the ship is this close to it, or behind it (m).
const EDGE_EPS: float = 0.01
## Most hazards a world holds (one bit each in HazardTable.crossed).
const MAX_HAZARDS: int = 30


static func step(world: SimWorld) -> void:
	var hazards: Array[HazardDef] = world.hazards
	if hazards.is_empty():
		return
	var t: float = world.tick * SimWorld.DT
	for ship: int in world.ship_count():
		if not world.kin.is_alive(ship):
			continue
		for i: int in hazards.size():
			var h: HazardDef = hazards[i]
			if h.site != world.kin.site[ship]:
				continue
			if h.is_front():
				_front(world, ship, i, h, t)
			else:
				_zone(world, ship, h)


## How far a point at `from_centre` (m, the offset from the hazard's centre) is outside the
## hazard's surface at time t (s): positive ahead of a front or outside a zone, zero on the
## surface, negative inside the zone or behind the front.
static func edge_distance(h: HazardDef, from_centre: Vector3, t: float) -> float:
	var since: float = maxf(0.0, t - h.start_s)
	if not h.is_front():
		return from_centre.length() - h.radius
	if h.shape == HazardDef.Shape.PLANE:
		return from_centre.dot(h.direction) - h.speed * since
	return from_centre.length() - (h.radius + h.speed * since)


## Whether the front is out at time t: it has set off and not faded (zones always are).
static func is_live(h: HazardDef, t: float) -> bool:
	if not h.is_front():
		return true
	return t >= h.start_s and (h.duration_s <= 0.0 or t <= h.start_s + h.duration_s)


## Offset (m) from the hazard's centre to the ship, by minimum image.
static func ship_offset(world: SimWorld, ship: int, h: HazardDef) -> Vector3:
	return -world.kin.relative_to_point(ship, h.center.x, h.center.y, h.center.z)


## Whether the faction knows of the hazard i now: it is live, and one of the faction's live
## ships on its site has its sensors (detect_range, scaled by their health) or one of its
## deployed probes has its bubble within reach of the hazard's surface.
static func known_to(world: SimWorld, faction: int, i: int) -> bool:
	var h: HazardDef = world.hazards[i]
	var t: float = world.tick * SimWorld.DT
	if not is_live(h, t):
		return false
	var kin: Kinematics = world.kin
	for s: int in world.ship_count():
		if kin.factions[s] != faction or not kin.is_alive(s) or kin.site[s] != h.site:
			continue
		var reach: float = h.detect_range * DamageSystem.effectiveness(world, s, &"sensors")
		if _gap(h, ship_offset(world, s, h), t) <= reach:
			return true
	var probes: ProbeTable = world.probes
	for p: int in probes.size():
		if probes.factions[p] != faction or probes.deployed[p] == 0 or probes.site[p] != h.site:
			continue
		var at: Vector3 = Vector3(
			kin.wrap(probes.at_x[p] - h.center.x),
			kin.wrap(probes.at_y[p] - h.center.y),
			kin.wrap(probes.at_z[p] - h.center.z)
		)
		if _gap(h, at, t) <= world.defs[probes.ship_ids[p]].probe_range:
			return true
	return false


## Seconds until hazard i reaches the ship if it goes on at its present velocity: 0 when it
## is in a zone, -1 when the hazard is not coming (a zone it is not closing on, a front it
## outruns or that has passed). Zones count to their edge.
static func eta(world: SimWorld, ship: int, i: int) -> float:
	var h: HazardDef = world.hazards[i]
	var t: float = world.tick * SimWorld.DT
	if h.site != world.kin.site[ship] or not is_live(h, t):
		return -1.0
	var from_centre: Vector3 = ship_offset(world, ship, h)
	var d: float = edge_distance(h, from_centre, t)
	var vel: Vector3 = world.kin.vel[ship]
	var closing: float
	if h.is_front() and h.shape == HazardDef.Shape.PLANE:
		closing = h.speed - vel.dot(h.direction)
	else:
		var away: Vector3 = from_centre.normalized() if from_centre.length() > 1e-9 else Vector3.UP
		closing = (h.speed if h.is_front() else 0.0) - vel.dot(away)
	if not h.is_front() and d <= 0.0:
		return 0.0
	if d <= 0.0 or closing < 0.5:
		return -1.0
	return d / closing


static func _zone(world: SimWorld, ship: int, h: HazardDef) -> void:
	if edge_distance(h, ship_offset(world, ship, h), 0.0) > 0.0:
		return
	if h.drag > 0.0:
		world.kin.vel[ship] *= 1.0 - h.drag * SimWorld.DT
	if h.damage_w <= 0.0:
		return
	if h.targets.is_empty():
		DamageSystem.damage_hull(world, ship, h.damage_w * SimWorld.DT)
	elif world.tick % DAMAGE_EVERY == 0:
		_damage_targets(world, ship, h.damage_w * SimWorld.DT * DAMAGE_EVERY, h)


static func _front(world: SimWorld, ship: int, i: int, h: HazardDef, t: float) -> void:
	var table: HazardTable = world.hazard_state
	var bit: int = 1 << i
	if table.crossed[ship] & bit != 0:
		return
	if h.duration_s > 0.0 and t > h.start_s + h.duration_s:
		return
	var d: float = edge_distance(h, ship_offset(world, ship, h), t)
	var first_look: bool = table.seen[ship] & bit == 0
	table.seen[ship] |= bit
	if d > EDGE_EPS:
		return
	table.crossed[ship] |= bit
	# A ship already behind the surface at the first look (the front sets off behind it, or
	# the ship is spawned or reset there) is crossed without a hit.
	if first_look:
		return
	world.emit(&"hazard_hit", ship, -1, h.hit_j, Vector3.ZERO, h.id)
	if h.targets.is_empty():
		DamageSystem.damage_hull(world, ship, h.hit_j)
	else:
		_damage_targets(world, ship, h.hit_j, h)


static func _damage_targets(world: SimWorld, ship: int, energy: float, h: HazardDef) -> void:
	var subs: Array[SubsystemDef] = world.defs[ship].subsystems
	for id: StringName in h.targets:
		for k: int in subs.size():
			if subs[k].id == id:
				DamageSystem.damage_subsystem(world, ship, k, energy)


## How far a point is from the hazard's surface: 0 inside a zone, the distance to the
## surface of a front on either side of it.
static func _gap(h: HazardDef, from_centre: Vector3, t: float) -> float:
	var d: float = edge_distance(h, from_centre, t)
	return maxf(d, 0.0) if not h.is_front() else absf(d)
