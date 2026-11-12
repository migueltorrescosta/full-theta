extends RefCounted

func dx(kin: Kinematics, i: int, j: int) -> float:
	return kin.pos_x[i] - kin.pos_x[j]

func drop(proj: ProjectileTable, k: int) -> void:
	proj.pos_z[k] = 0.0
	world.kin . pos_y.fill(0.0)
