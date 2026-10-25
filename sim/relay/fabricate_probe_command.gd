class_name FabricateProbeCommand
extends SimCommand
## Engineering builds a probe from spare parts (P11, D56): the parts are taken now and
## the probe joins Relay's stock after the ship's fabrication time. See
## ProbeSystem.fabricate.


func kind() -> StringName:
	return &"fabricate_probe"


func apply(world: SimWorld) -> bool:
	return ProbeSystem.fabricate(world, ship_id)
