class_name SpawnShipCommand
extends ServerCommand
## Spawns an NPC ship from the world's catalogue (E07, FT-MIS-005): the Scenario API's
## spawn_* writes. The NPC is looked up by key in SimWorld.catalog (read-only data app/
## fills from DefLibrary). The new ship's id is the world's ship count at that moment, and
## result_id carries it to the API's handle.

var npc_key: StringName = &""
var faction: int = 0
var x: float = 0.0
var y: float = 0.0
var z: float = 0.0
var rot: Quaternion = Quaternion.IDENTITY


func kind() -> StringName:
	return &"spawn_ship"


## Rejects an unknown NPC key, a negative faction, a non-finite point or an unusable
## rotation; the point wraps onto the cube (FT-SIM-035).
func apply(world: SimWorld) -> bool:
	var npc: NpcDef = world.catalog.get(npc_key)
	if npc == null or faction < 0:
		return false
	var at: PackedFloat64Array = world.kin.wrap_point(CubePoint.make(x, y, z))
	if at.is_empty():
		return false
	if not rot.is_finite() or rot.length_squared() < 1e-12:
		return false
	var id: int = world.spawn_npc(npc, faction, at, rot)
	world.emit(&"ship_spawned", id, -1, 0.0, Vector3.ZERO, npc_key)
	result_id = id
	return true
