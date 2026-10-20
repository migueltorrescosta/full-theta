class_name S5ShipBody
extends RefCounted
## Rigid-body state and ship limits, SI units (FT-SIM-002). Local axes follow Godot:
## -Z is the bow, +X starboard, +Y up. Angular velocity is in the body frame
## (x pitch, y yaw, z roll). Pure data; promote to T027 with the integrator.

var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var orientation: Quaternion = Quaternion.IDENTITY
var angular_velocity: Vector3 = Vector3.ZERO
var mass: float = 50000.0
## Diagonal inertia tensor in the body frame (kg m^2).
var inertia: Vector3 = Vector3(2.0e6, 2.4e6, 1.2e6)
## Maximum thrust along +X, +Y, +Z (N). +Z is astern, so max_thrust_pos.z brakes.
var max_thrust_pos: Vector3 = Vector3(6.0e5, 6.0e5, 5.0e5)
## Maximum thrust along -X, -Y, -Z (N, positive numbers). max_thrust_neg.z is the main drive.
var max_thrust_neg: Vector3 = Vector3(6.0e5, 6.0e5, 1.0e6)
## Maximum torque per body axis (N m).
var max_torque: Vector3 = Vector3(3.0e6, 3.6e6, 3.0e6)
## Propellant mass (kg); spent in proportion to impulse (FT-SIM-007).
var propellant: float = 10000.0
## Effective exhaust velocity (m/s): propellant used = impulse / exhaust_velocity.
var exhaust_velocity: float = 60000.0
## Lever arm (m) that turns torque into the thruster force it costs.
var lever_arm: float = 10.0


func forward() -> Vector3:
	return orientation * Vector3.FORWARD


func up() -> Vector3:
	return orientation * Vector3.UP


func to_local(world: Vector3) -> Vector3:
	return orientation.inverse() * world


func to_world(local: Vector3) -> Vector3:
	return orientation * local


## Clamps a local force to the thrust envelope, axis by axis.
func clamp_thrust(force: Vector3) -> Vector3:
	return Vector3(
		clampf(force.x, -max_thrust_neg.x, max_thrust_pos.x),
		clampf(force.y, -max_thrust_neg.y, max_thrust_pos.y),
		clampf(force.z, -max_thrust_neg.z, max_thrust_pos.z)
	)


func clamp_torque(torque: Vector3) -> Vector3:
	return torque.clamp(-max_torque, max_torque)


## Full-deflection force for an input in [-1, 1] per local axis.
func thrust_for_input(input: Vector3) -> Vector3:
	return Vector3(
		input.x * (max_thrust_pos.x if input.x > 0.0 else max_thrust_neg.x),
		input.y * (max_thrust_pos.y if input.y > 0.0 else max_thrust_neg.y),
		input.z * (max_thrust_pos.z if input.z > 0.0 else max_thrust_neg.z)
	)


func copy() -> S5ShipBody:
	var b: S5ShipBody = S5ShipBody.new()
	b.position = position
	b.velocity = velocity
	b.orientation = orientation
	b.angular_velocity = angular_velocity
	b.mass = mass
	b.inertia = inertia
	b.max_thrust_pos = max_thrust_pos
	b.max_thrust_neg = max_thrust_neg
	b.max_torque = max_torque
	b.propellant = propellant
	b.exhaust_velocity = exhaust_velocity
	b.lever_arm = lever_arm
	return b
