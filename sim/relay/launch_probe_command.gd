class_name LaunchProbeCommand
extends SimCommand
## Relay launches a probe from the ship's stock to a site-local point (m, wrapped onto
## the site's cube; FT-RLY-004, D56). See ProbeSystem.launch.

var x: float = 0.0
var y: float = 0.0
var z: float = 0.0


func kind() -> StringName:
	return &"launch_probe"


func apply(world: SimWorld) -> bool:
	return ProbeSystem.launch(world, ship_id, x, y, z)
