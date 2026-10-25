class_name P4Scenario
extends RefCounted
## P4 Helm + Relay pair scenario (spec §7.4, FT-PAIR-015, FT-RLY-004): the M1 corvette,
## at rest at the origin with its bow on -Z, must fly 8 km to an intercept point dead
## ahead. A dust cloud (hazard zone, radius 2 km, D205) sits on the straight line, halfway.
## The sim has no hazard physics: the environment plays the cloud, the same in both
## variants. Inside it the hull takes DAMAGE_W J/s and the ship loses DRAG of its velocity
## per second, which the speed hold buys back with propellant.
## - Helm (both variants): selects the point it is told to fly to, holds Face, throttles up
##   once the bow is on it, and takes the next point when within WAYPOINT_R of this one.
## - Relay (co-op only): sees the cloud on its 3D map and sends a route around it, one
##   waypoint abeam of the cloud (the route ribbon, FT-RLY-005), then the intercept point.
## - Solo: Helm has only the intercept point and the compass, no knowledge of the cloud
##   until it is in it: it flies the straight line (FT-PAIR-004).
## Metrics: hull lost (J), propellant used (kg) and time (s) to within CAPTURE of the point.

const SEED: int = 104
const PLAYER: int = 0
const POINT: Vector3 = Vector3(0.0, 0.0, -8000.0)
const CLOUD_AT: Vector3 = Vector3(0.0, 0.0, -4000.0)
const CLOUD_RADIUS: float = 2000.0
## Hull damage in the cloud (J/s) and the share of velocity it removes per second.
const DAMAGE_W: float = 1e6
const DRAG: float = 0.08
## Relay's route: a waypoint 2.7 km abeam of the cloud's centre; the legs to and from it
## clear the cloud's edge by 238 m.
const ROUTE: Array[Vector3] = [Vector3(2700.0, 0.0, -4000.0), POINT]
const WAYPOINT_R: float = 300.0
const CAPTURE: float = 50.0
const ON_POINT: float = PI / 36.0
## Helm cruises at this forward speed (m/s): the turn at the waypoint is flown at it.
const CRUISE: float = 100.0
const TICK_LIMIT: int = 240 * SimWorld.HZ


static func harness() -> PairHarness:
	return PairHarness.new(build, cloud, done, measure, TICK_LIMIT)


static func build() -> SimWorld:
	var w: SimWorld = SimWorld.new(SEED, "p4")
	w.spawn_ship(TestDefs.corvette(), 1, 0)
	return w


## The environment: inside the cloud, hull damage and drag.
static func cloud(w: SimWorld) -> void:
	if w.kin.relative_to_point(PLAYER, CLOUD_AT.x, CLOUD_AT.y, CLOUD_AT.z).length() > CLOUD_RADIUS:
		return
	var hull: int = w.damage.hull_row(PLAYER)
	w.damage.health[hull] = maxf(0.0, w.damage.health[hull] - DAMAGE_W * SimWorld.DT)
	w.kin.vel[PLAYER] *= 1.0 - DRAG * SimWorld.DT


static func done(w: SimWorld) -> bool:
	return w.kin.relative_to_point(PLAYER, POINT.x, POINT.y, POINT.z).length() < CAPTURE


static func measure(w: SimWorld) -> Dictionary:
	var hull_lost: float = (1.0 - DamageSystem.hull_fraction(w, PLAYER)) * w.defs[PLAYER].hull_max
	return {
		"hull_lost": hull_lost,
		"propellant": w.kin.propellant_used[PLAYER],
		"time": w.tick * SimWorld.DT
	}


static func solo(w: SimWorld) -> void:
	helm(w, [POINT])


static func coop(w: SimWorld) -> void:
	helm(w, ROUTE)


## Helm flying the points in order. A point is passed when the ship is within
## WAYPOINT_R of it; the next is selected then (the selection is read back from the
## helm table, so the script keeps no state).
static func helm(w: SimWorld, points: Array[Vector3]) -> void:
	var leg: int = 0
	while (
		leg < points.size() - 1
		and (
			(
				(
					w
					. kin
					. relative_to_point(PLAYER, points[leg].x, points[leg].y, points[leg].z)
					. length()
				)
				< WAYPOINT_R
			)
			or _passed(w, points, leg)
		)
	):
		leg += 1
	var p: Vector3 = points[leg]
	if (
		w.helm.target_kind[PLAYER] != HelmTable.Target.POINT
		or w.helm.target_z[PLAYER] != p.z
		or w.helm.target_x[PLAYER] != p.x
	):
		var select: SelectTargetCommand = SelectTargetCommand.new()
		select.site = 0
		select.x = p.x
		select.y = p.y
		select.z = p.z
		_submit(w, select)
	var to_point: Vector3 = w.kin.relative_to_point(PLAYER, p.x, p.y, p.z)
	var on_point: bool = w.kin.forward(PLAYER).angle_to(to_point) < ON_POINT
	var throttle: float = 1.0 if w.helm.throttle_setpoint[PLAYER] < CRUISE and on_point else 0.0
	if w.tick == 0 or throttle != w.helm.input_translation[PLAYER].z:
		_submit(w, _helm_input(throttle))


## Whether the ship is moving away from the point after closing on it.
static func _passed(w: SimWorld, points: Array[Vector3], leg: int) -> bool:
	var p: Vector3 = points[leg]
	var to_point: Vector3 = w.kin.relative_to_point(PLAYER, p.x, p.y, p.z)
	return w.tick > 0 and w.kin.vel[PLAYER].dot(to_point) < 0.0


static func _helm_input(throttle: float) -> HelmInputCommand:
	var c: HelmInputCommand = HelmInputCommand.new()
	c.face = true
	c.throttle = throttle
	return c


static func _submit(w: SimWorld, c: SimCommand) -> void:
	c.ship_id = PLAYER
	w.submit(c)
