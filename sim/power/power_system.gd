class_name PowerSystem
extends RefCounted
## Power and heat: sets the thrust envelope (T030). Stub until its task lands.


static func step(_world: SimWorld) -> void:
	pass


## Draws energy for a shot or other use (J); false, and nothing drawn, if not enough.
static func draw_energy(_world: SimWorld, _ship_id: int, _joules: float) -> bool:
	return true
