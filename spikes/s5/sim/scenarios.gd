class_name S5Scenarios
extends RefCounted
## Headless scenarios shared by the tests and spikes/s5/measure.gd. Each runs whole
## ticks of S5World and returns its numbers in a Dictionary.

const CAPTURE_RADIUS: float = 100.0
const INTERCEPT_LIMIT: float = 60.0


## Starting geometries for the intercept: [name, ship yaw (deg), ship velocity].
static func intercept_cases() -> Array[Array]:
	return [
		["from rest, facing -Z", 0.0, Vector3.ZERO],
		["from rest, facing away", 180.0, Vector3.ZERO],
		["drifting 120 m/s to port", 90.0, Vector3(-120.0, 0.0, 0.0)],
	]


## Autopilot with assist chases H2 until within CAPTURE_RADIUS or the time limit.
static func intercept(
	yaw_deg: float, start_velocity: Vector3, pilot: S5Autopilot = null
) -> Dictionary:
	var world: S5World = S5World.new()
	world.ship.orientation = Quaternion(Vector3.UP, deg_to_rad(yaw_deg))
	world.ship.velocity = start_velocity
	world.helm.throttle_setpoint = 0.0
	if pilot == null:
		pilot = S5Autopilot.new()
	var target: S5Item = world.items[S5World.TARGET]
	var start_dist: float = (target.position - world.ship.position).length()
	var dist: float = start_dist
	while world.time < INTERCEPT_LIMIT:
		world.step(pilot.input_for(world, target))
		dist = (target.position - world.ship.position).length()
		if dist < CAPTURE_RADIUS:
			break
	return {
		"captured": dist < CAPTURE_RADIUS,
		"time": world.time,
		"start_distance": start_dist,
		"distance": dist,
		"relative_speed": (target.velocity - world.ship.velocity).length(),
		"propellant": world.propellant_used,
	}


## All-stop from a tumbling, drifting start, then hold-to-approach to the Bravo mark.
static func stop_then_approach(hold_time: float) -> Dictionary:
	var world: S5World = S5World.new()
	world.ship.velocity = Vector3(90.0, 25.0, -160.0)
	world.ship.angular_velocity = Vector3(0.3, -0.2, 0.5)
	world.helm.throttle_setpoint = 180.0
	var idle: S5HelmInput = S5HelmInput.new()
	var press: S5HelmInput = S5HelmInput.new()
	press.all_stop_pressed = true
	world.step(press)
	while world.helm.all_stop and world.time < 60.0:
		world.step(idle)
	var stop_time: float = world.time
	var stopped_at: Vector3 = world.ship.position
	var stop_speed: float = world.ship.velocity.length()

	world.helm.selected = S5World.MARK
	var mark: S5Item = world.items[S5World.MARK]
	var hold: S5HelmInput = S5HelmInput.new()
	hold.approach = true
	var start: float = world.time
	var settled: float = -1.0
	while world.time - start < hold_time:
		world.step(hold)
		var near: bool = (mark.position - world.ship.position).length() < 1000.0
		if settled < 0.0 and near and world.ship.velocity.length() < 0.5:
			settled = world.time - start
	world.step(idle)  # release
	for i: int in 120:
		world.step(idle)
	return {
		"stop_time": stop_time,
		"stop_speed": stop_speed,
		"stop_drift": stopped_at.length(),
		"mark_distance_at_start": (mark.position - stopped_at).length(),
		"approach_settled": settled,
		"distance": (mark.position - world.ship.position).length(),
		"speed": world.ship.velocity.length(),
		"rate": world.ship.angular_velocity.length(),
		"propellant": world.propellant_used,
	}
