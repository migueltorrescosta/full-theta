class_name AlignCommand
extends SimCommand
## One Align press (FT-HLM-007, D124; there is no privileged up): the first press rolls
## the ship so the selected target (contact, mark or point) lies at 12 o'clock, in the
## ship's pitch plane above the bow direction; a second press, or a press with the roll
## already done, also faces it (pitch and yaw onto it); further presses keep that.
## Rejected with nothing selected or a target Helm can't fly to (undetected, another
## site). Ends within tolerance, on rotation input or when the target is lost
## (AssistSystem).


func kind() -> StringName:
	return &"helm_align"


func apply(world: SimWorld) -> bool:
	if not AssistSystem.has_target(world, ship_id):
		return false
	var helm: HelmTable = world.helm
	var rolled: bool = absf(AssistSystem.align_roll_error(world, ship_id)) < AssistSystem.ROLLED
	if helm.align[ship_id] == HelmTable.Align.OFF and not rolled:
		helm.align[ship_id] = HelmTable.Align.ROLL
	else:
		helm.align[ship_id] = HelmTable.Align.ROLL_AND_FACE
	return true
