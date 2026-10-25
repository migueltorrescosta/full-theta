class_name HitResolver
extends RefCounted
## Resolves the tick's hits in order: shields absorb part (FT-SIM-019), the rest goes
## to hull and subsystem damage (FT-SIM-020), and each hit emits a &"hit" event
## (FT-SIM-030). Before the shields, the target's resistance to the hit's damage type
## scales its energy (FT-SIM-022).


static func resolve(world: SimWorld) -> void:
	for hit: SimHit in world.hits:
		if not world.kin.is_alive(hit.target_id):
			continue
		var resist: Dictionary[StringName, float] = world.defs[hit.target_id].resistances
		if not resist.is_empty():
			hit.energy *= resist.get(hit.damage_type, 1.0)
		var through: float = ShieldSystem.absorb(world, hit)
		world.emit(&"hit", hit.target_id, hit.source_id, through, hit.point_local, hit.kind)
		DamageSystem.apply_hit(world, hit, through)
	world.hits.clear()
