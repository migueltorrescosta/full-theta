class_name HelmInputCommand
extends SimCommand
## Helm's continuous input (FT-ARC-005): stick axes, throttle and the held face and
## approach buttons. Latched in HelmTable until the next HelmInputCommand, so a station
## sends one when the input changes, not every tick. Axes are clamped to [-1, 1];
## non-finite values are rejected.

## x pitch (nose up +), y yaw (nose to port +), z roll (to port +), each in [-1, 1].
var rotation: Vector3 = Vector3.ZERO
## Starboard (+) / port (-) strafe.
var strafe: float = 0.0
## Up (+) / down (-) translation.
var lift: float = 0.0
## Forward (+) / astern (-): with assist it ramps the speed setpoint; decoupled, it
## fires the main drive or the retro thrusters.
var throttle: float = 0.0
## Hold to face the selected target (FT-HLM-005).
var face: bool = false
## Hold to approach the selected target (FT-SIM-037).
var approach: bool = false


func kind() -> StringName:
	return &"helm_input"


func apply(world: SimWorld) -> bool:
	var move: Vector3 = Vector3(strafe, lift, throttle)
	if not rotation.is_finite() or not move.is_finite():
		return false
	var helm: HelmTable = world.helm
	helm.input_rotation[ship_id] = rotation.clamp(-Vector3.ONE, Vector3.ONE)
	helm.input_translation[ship_id] = move.clamp(-Vector3.ONE, Vector3.ONE)
	helm.face_held[ship_id] = 1 if face else 0
	if helm.approach_held[ship_id] == 1 and not approach:
		# Releasing approach returns control at the current forward speed (FT-SIM-037).
		helm.throttle_setpoint[ship_id] = AssistSystem.forward_speed(world, ship_id)
	helm.approach_held[ship_id] = 1 if approach else 0
	return true
