class_name HazardTable
extends SimTable
## Per-ship hazard state (D208): for each ship, which fronts of SimWorld.hazards have
## already crossed it (bit i is hazards[i]), so a front hits a ship once. Zones keep no
## state: a ship is in one or not. A front also needs to know whether it has looked at the
## ship yet: a ship that is already behind its surface at the first look (spawned or reset
## there) was never swept, so it isn't hit. The hazards themselves are definitions, not state.

## Fronts that crossed the ship, one bit per hazard index (so at most MAX_HAZARDS).
var crossed: PackedInt32Array = PackedInt32Array()
## Fronts that have already been evaluated for the ship, same bits.
var seen: PackedInt32Array = PackedInt32Array()


func add_ship(ship_id: int, faction: int, _def: ShipDef) -> void:
	add_key(ship_id, faction)
	crossed.append(0)
	seen.append(0)


func columns() -> Array:
	return super() + [["crossed", crossed], ["seen", seen]]
