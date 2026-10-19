class_name BoostCommand
extends SimCommand
## Engineering boosts engines and thrusters: a short overcharge above the reactor cap
## that builds heat (P1); rejected while a boost runs.


func kind() -> StringName:
	return &"boost"


func apply(world: SimWorld) -> bool:
	return PowerSystem.boost(world, ship_id)
