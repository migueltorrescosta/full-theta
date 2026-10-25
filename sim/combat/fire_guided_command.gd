class_name FireGuidedCommand
extends SimCommand
## Asks a mount for one guided shot this tick, at a tracked contact (FT-WPN-008, D209, P8):
## the client resolves the mark it fires at to the contact id the mark is attached to; a
## free mark in space is refused. The mount's weapon must be guided ordnance and the
## contact tracked by the shooter's faction (GuidanceSystem.is_tracked); the shot itself is
## gated like FireCommand's (arc, cooldown, ammunition, energy).

var mount_index: int = 0
## Ship id of the contact to follow.
var target: int = -1


func kind() -> StringName:
	return &"fire_guided"


func apply(world: SimWorld) -> bool:
	var row: int = world.mounts.row_for(ship_id, mount_index)
	if row < 0 or not WeaponSystem.weapon_of(world, row).is_guided():
		return false
	if target < 0 or target == ship_id:
		return false
	if not GuidanceSystem.is_tracked(world, world.faction_of(ship_id), target):
		return false
	world.mounts.fire_requested[row] = 1
	world.mounts.guide_target[row] = target
	return true
