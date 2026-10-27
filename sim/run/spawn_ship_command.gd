class_name SpawnShipCommand
extends ServerCommand
## Spawns an enemy ship from the world's catalogue (E07, FT-MIS-005): the Scenario API's
## spawn_* writes. The enemy is looked up by key in SimWorld.catalog (read-only data app/
## fills from DefLibrary). The new ship's id is the world's ship count at that moment, and
## result_id carries it to the API's handle.

var enemy_key: StringName = &""
var faction: int = 0
var x: float = 0.0
var y: float = 0.0
var z: float = 0.0
var rot: Quaternion = Quaternion.IDENTITY


func kind() -> StringName:
	return &"spawn_ship"


## Rejects an unknown enemy key, a negative faction, a non-finite point or an unusable
## rotation; the point wraps onto the cube (FT-SIM-035).
func apply(world: SimWorld) -> bool:
	var enemy: EnemyDef = world.catalog.get(enemy_key)
	if enemy == null or faction < 0:
		return false
	if world.kin.wrap_point(x, y, z).is_empty():
		return false
	if not rot.is_finite() or rot.length_squared() < 1e-12:
		return false
	var id: int = world.spawn_enemy(enemy, faction, Vector3(x, y, z), rot)
	world.emit(&"ship_spawned", id, -1, 0.0, Vector3.ZERO, enemy_key)
	result_id = id
	return true
