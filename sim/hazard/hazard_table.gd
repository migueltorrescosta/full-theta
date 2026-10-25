class_name HazardTable
extends SimTable
## Per-ship hazard state (D208): for each ship, which fronts of SimWorld.hazards have
## already crossed it (bit i is hazards[i]), so a front hits a ship once. Zones keep no
## state: a ship is in one or not. The hazards themselves are definitions, not state.

## Fronts that crossed the ship, one bit per hazard index (so at most MAX_HAZARDS).
var crossed: PackedInt32Array = PackedInt32Array()


func add_ship(ship_id: int, faction: int, _def: ShipDef) -> void:
	add_key(ship_id, faction)
	crossed.append(0)


func columns() -> Array:
	return super() + [["crossed", crossed]]
