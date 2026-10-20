extends RefCounted

func dx(kin: Kinematics, i: int, j: int) -> float:
	return kin.px[i] - kin.px[j]

func drop(proj: ProjectileTable, k: int) -> void:
	proj.pz[k] = 0.0
	world.kin . py.fill(0.0)
