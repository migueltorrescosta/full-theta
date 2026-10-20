class_name S5HelmInput
extends RefCounted
## One tick of Helm intent, device independent (research/tech §5). Axes are in [-1, 1].
## Edge fields (*_pressed) are true only on the tick the button went down.

## Starboard (+) / port (-) strafe.
var strafe: float = 0.0
## Up (+) / down (-) translation.
var lift: float = 0.0
## Forward (+) / astern (-). With assist it ramps the speed setpoint; decoupled, it fires
## the main drive or the retro thrusters directly.
var throttle: float = 0.0
## Nose up (+) / down (-).
var pitch: float = 0.0
## Nose to port (+) / starboard (-), the right-hand rotation about +Y.
var yaw: float = 0.0
## Roll to port (+) / starboard (-), the right-hand rotation about +Z.
var roll: float = 0.0
## Hold to face the selected item (FT-HLM-005).
var face: bool = false
## Hold to approach the selected item (FT-SIM-037).
var approach: bool = false
var all_stop_pressed: bool = false
var decoupled_pressed: bool = false
var level_pressed: bool = false
var select_pressed: bool = false


func has_manual_input(dead_zone: float) -> bool:
	return (
		absf(strafe) > dead_zone
		or absf(lift) > dead_zone
		or absf(throttle) > dead_zone
		or absf(pitch) > dead_zone
		or absf(yaw) > dead_zone
		or absf(roll) > dead_zone
	)
