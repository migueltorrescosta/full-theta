class_name AlignCommand
extends SimCommand
## One Align press (FT-HLM-007, D124; there is no privileged up): the first press rolls
## the ship so the selected target (contact, mark or point) lies at 12 o'clock, in the
## ship's pitch plane above the bow direction; a second press, or a press with the roll
## already done, also faces it (pitch and yaw onto it); further presses keep that.
## With mount_index set (the direct "bring mount N to bear" of a joint view, FT-JNT-005) it
## turns that mount's rest direction onto the target instead, with no roll.
## Rejected with nothing selected or a target Helm can't fly to (undetected),
## or with a mount the ship doesn't have. Ends within tolerance, on rotation input
## or when the target is lost (AssistSystem).

## The mount whose rest direction is brought onto the target, or -1 for the bow.
var mount_index: int = -1


func kind() -> StringName:
	return &"helm_align"


func apply(world: SimWorld) -> bool:
	if not AssistSystem.has_target(world, ship_id):
		return false
	var helm: HelmTable = world.helm
	if mount_index >= 0:
		if mount_index >= world.defs[ship_id].mounts.size():
			return false
		helm.align_bow[ship_id] = world.defs[ship_id].mounts[mount_index].forward
		helm.align_mount[ship_id] = 1
		helm.align[ship_id] = HelmTable.Align.ROLL_AND_FACE
		return true
	helm.align_bow[ship_id] = Vector3.FORWARD
	helm.align_mount[ship_id] = 0
	var local: Vector3 = world.kin.to_local(ship_id, AssistSystem.target_offset(world, ship_id))
	var rolled: bool = absf(AssistSystem.align_roll_error(local)) < AssistSystem.ROLLED
	if helm.align[ship_id] == HelmTable.Align.OFF and not rolled:
		helm.align[ship_id] = HelmTable.Align.ROLL
	else:
		helm.align[ship_id] = HelmTable.Align.ROLL_AND_FACE
	return true
