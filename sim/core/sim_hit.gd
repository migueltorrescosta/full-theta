class_name SimHit
extends RefCounted
## One impact on a ship this tick, produced by collisions and projectiles (FT-SIM-009)
## and resolved by HitResolver: shields absorb first (FT-SIM-019), the rest damages
## the hull and the nearest subsystem (FT-SIM-020). Energy is the unit of damage (J).

var target_id: int = -1
## The shooter or the other ship, or -1.
var source_id: int = -1
## &"projectile", &"beam" or &"collision".
var kind: StringName = &""
## Impact point in the target's body frame, relative to its centre (m).
var point_local: Vector3 = Vector3.ZERO
## Unit direction from the target's centre toward where the hit came from, body frame.
var from_local: Vector3 = Vector3.FORWARD
## Damage energy before shields (J).
var energy: float = 0.0
## Damage type, matched against the target's resistances (FT-SIM-022).
var damage_type: StringName = &"kinetic"
