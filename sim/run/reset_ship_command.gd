class_name ResetShipCommand
extends SimCommand
## Resets one ship's run state and places it again (FT-GEN-002, FT-MIS-017) through
## SimWorld.reset_ship. The server sends it, not a crew, so its source is SERVER; it is
## logged like crew commands so a replay re-applies it (FT-ARC-008), and it applies to
## a destroyed ship (resetting one is its purpose).

## Site and site-local offset (m, 64-bit, D104) to place the ship at.
var site: int = 0
var x: float = 0.0
var y: float = 0.0
var z: float = 0.0
var rotation: Quaternion = Quaternion.IDENTITY


func _init() -> void:
	source = Source.SERVER


func kind() -> StringName:
	return &"reset_ship"


func applies_to_destroyed() -> bool:
	return true


## Rejects an offset off the site grid (FT-SIM-035).
func apply(world: SimWorld) -> bool:
	if site < 0 or not Kinematics.in_bounds(x, y, z):
		return false
	world.reset_ship(ship_id, site, x, y, z, rotation)
	return true
