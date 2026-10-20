class_name S5Autopilot
extends RefCounted
## Scripted pilot for the intercept test (T012). It only produces Helm intent (stick and
## throttle), like a player with assist on; assist and the integrator do the flying.
## It wants a velocity that closes on the target along the line of sight and brakes in
## time to match it, points the bow along that velocity with some over-correction for
## the drift assist hasn't killed yet, and sets the throttle to the speed along the bow.

## Closing speed far out (m/s).
var closing_speed: float = 280.0
## Braking the closing plan assumes (m/s^2), below the retro thrust.
var brake: float = 8.0
## Over-correction: how far past the wanted velocity the bow points.
var lead_gain: float = 1.5
## Stick deflection per radian of pointing error.
var stick_gain: float = 2.5


func input_for(world: S5World, target: S5Item) -> S5HelmInput:
	var ship: S5ShipBody = world.ship
	var inp: S5HelmInput = S5HelmInput.new()
	var rel: Vector3 = target.position - ship.position
	var dist: float = maxf(rel.length(), 1.0)
	var close: float = minf(closing_speed, sqrt(2.0 * brake * dist))
	var v_want: Vector3 = target.velocity + rel / dist * close
	v_want = v_want.limit_length(world.assist.max_speed)
	var aim: Vector3 = v_want + (v_want - ship.velocity) * lead_gain

	var d: Vector3 = ship.to_local(aim.normalized())
	var angle: float = Vector3.FORWARD.angle_to(d)
	var axis: Vector3 = Vector3.FORWARD.cross(d)
	axis = axis.normalized() if axis.length_squared() > 1e-12 else Vector3.RIGHT
	var stick: Vector3 = axis * clampf(angle * stick_gain, 0.0, 1.0)
	inp.pitch = stick.x
	inp.yaw = stick.y

	# Throttle toward the wanted speed along the bow; ease off while far off-heading.
	var want: float = maxf(v_want.dot(ship.forward()), 0.0) * clampf(cos(angle), 0.0, 1.0)
	inp.throttle = clampf((want - world.helm.throttle_setpoint) / 10.0, -1.0, 1.0)
	return inp
