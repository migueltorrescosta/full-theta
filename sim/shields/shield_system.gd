class_name ShieldSystem
extends RefCounted
## Shield regeneration and absorption (T031). Stub until its task lands.


static func step(_world: SimWorld) -> void:
	pass


## Returns the energy that passes the shields (J).
static func absorb(_world: SimWorld, hit: SimHit) -> float:
	return hit.energy
