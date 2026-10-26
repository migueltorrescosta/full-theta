class_name JumpSystem
extends RefCounted
## The jump drive and docking holds (FT-SIM-034, FT-HLM-013, D229). Runs after AssistSystem.
## A spooling ship counts its ticks down; at zero it moves to ShipDef.jump_standoff_m short
## of the target point along the line from where it is (minimum image; it stays put when
## already closer), at rest relative to the target, in the same cube. It emits
## &"jump_arrive" (value: the target site id or -1, tag: the site it left, or "-1"). A
## docked ship is held at its dock site's point, at rest.


static func step(world: SimWorld) -> void:
	var helm: HelmTable = world.helm
	var kin: Kinematics = world.kin
	for row: int in kin.alive.size():
		if kin.alive[row] != 1:
			continue
		if helm.docked_site[row] >= 0:
			_hold(world, row)
		elif helm.jump_left[row] > 0:
			helm.jump_left[row] -= 1
			if helm.jump_left[row] == 0:
				_arrive(world, row)


static func _arrive(world: SimWorld, row: int) -> void:
	var helm: HelmTable = world.helm
	var kin: Kinematics = world.kin
	var origin: int = SiteTable.at_site(world, row)
	var offset: Vector3 = kin.relative_to_point(
		row, helm.jump_x[row], helm.jump_y[row], helm.jump_z[row]
	)
	var dist: float = offset.length()
	var standoff: float = world.defs[row].jump_standoff_m
	if dist > standoff:
		var move: Vector3 = offset * (1.0 - standoff / dist)
		kin.translate(row, move.x, move.y, move.z)
	kin.vel[row] = Vector3.ZERO
	kin.force_cmd[row] = Vector3.ZERO
	helm.throttle_setpoint[row] = 0.0
	world.emit(
		&"jump_arrive", row, -1, float(helm.jump_target[row]), Vector3.ZERO, StringName(str(origin))
	)


## Holds a docked ship at its site's point: no velocity, no thrust, no spin.
static func _hold(world: SimWorld, row: int) -> void:
	var kin: Kinematics = world.kin
	var site: int = world.helm.docked_site[row]
	var sites: SiteTable = world.sites
	kin.place(row, sites.pos_x[site], sites.pos_y[site], sites.pos_z[site])
	kin.vel[row] = Vector3.ZERO
	kin.force_cmd[row] = Vector3.ZERO
	kin.torque_cmd[row] = Vector3.ZERO
	kin.set_angular_velocity(row, Vector3.ZERO)
