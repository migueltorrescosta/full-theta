class_name FireGuidedCommand
extends SimCommand
## Asks a mount for one guided shot this tick, at a tracked contact or a point
## (FT-WPN-008, P8): the client resolves the mark it fires at to a contact id (a mark
## attached to a contact) or a site-local point. The mount's weapon must be guided
## ordnance. A contact must be tracked by the shooter's faction (GuidanceSystem.is_tracked);
## the shot itself is gated like FireCommand's (arc, cooldown, ammunition, energy).

var mount_index: int = 0
## Ship id of the contact to follow, or -1 for none.
var target: int = -1
## Whether (x, y, z), a site-local point (m, D104), is the guide point.
var has_point: bool = false
var x: float = 0.0
var y: float = 0.0
var z: float = 0.0


func kind() -> StringName:
	return &"fire_guided"


func apply(world: SimWorld) -> bool:
	var row: int = world.mounts.row_for(ship_id, mount_index)
	if row < 0 or not WeaponSystem.weapon_of(world, row).is_guided():
		return false
	if target < 0 and not has_point:
		return false
	if target == ship_id:
		return false
	if target >= 0 and not GuidanceSystem.is_tracked(world, world.faction_of(ship_id), target):
		return false
	var p: PackedFloat64Array = PackedFloat64Array([x, y, z])
	if has_point:
		p = world.kin.wrap_point(x, y, z)
		if p.is_empty():
			return false
	var mounts: MountTable = world.mounts
	mounts.fire_requested[row] = 1
	mounts.guide_target[row] = target
	mounts.guide_point[row] = 1 if has_point else 0
	if has_point:
		mounts.guide_x[row] = p[0]
		mounts.guide_y[row] = p[1]
		mounts.guide_z[row] = p[2]
	return true
