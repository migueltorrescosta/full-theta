class_name S9World
extends S6WorldPacked
## S9 spike world: the S6 benchmark load (100 ships, 500 projectiles) with the
## read access the snapshot sections need. Ships 0..5 are the player ships.
## A projectile id is reused when S6 refires it, so each refire bumps a
## generation counter that tells the sections a new projectile took the id.

## Generation per projectile id, bumped on every refire.
var proj_gen: PackedInt32Array = PackedInt32Array()


func setup_benchmark(n_ships: int, n_proj: int) -> void:
	proj_gen.resize(n_proj)
	super.setup_benchmark(n_ships, n_proj)


func ship_ang(i: int) -> Vector3:
	return _ang[i]


func ship_site(i: int) -> int:
	return _site[i]


func proj_count() -> int:
	return _n_proj


func proj_vel(k: int) -> Vector3:
	return _p_vel[k]


func proj_live(k: int) -> bool:
	return _p_ttl[k] > 0


## Packed views for the hot loops (copy-on-write, so read-only and cheap).
func ship_positions() -> PackedVector3Array:
	return _pos


func proj_positions() -> PackedVector3Array:
	return _p_pos


func _fire(k: int) -> void:
	if k < proj_gen.size():
		proj_gen[k] += 1
	super._fire(k)
