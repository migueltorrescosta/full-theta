class_name CollisionSystem
extends RefCounted
## Ship contacts, proximity warnings and swept projectiles (T029, FT-SIM-009,
## FT-SIM-010, FT-ARC-007: no Godot physics). Runs after the integrator and the weapons
## each tick. Broadphase is a uniform grid per site, rebuilt every tick and keyed by
## Vector4i(site, ix, iy, iz), so ships at different sites never share a cell (S6).
## Ships at the start of the tick are taken as end position minus velocity times DT;
## the error is a dt^2 / 2, under 3 mm at 20 m/s^2.

## Projectile broadphase cell (m, S6).
const CELL: float = 250.0
## Ship-pair broadphase cell (m): pairs up to this far apart are always checked, so
## proximity warnings get the full horizon for closing speeds up to about
## (PAIR_CELL - reach) / WARNING_HORIZON (190 m/s for two corvettes) and at least
## PAIR_CELL of warning distance above that.
const PAIR_CELL: float = 500.0
## Coefficient of restitution of ship-ship contacts (dimensionless): hulls are mostly
## inelastic, so most of the closing kinetic energy turns into damage.
const RESTITUTION: float = 0.2
## Ships on course to touch within this time get a &"proximity" warning (s, FT-SIM-010).
const WARNING_HORIZON: float = 5.0
## While a pair stays inside the horizon the warning repeats on ticks that are a
## multiple of this (ticks); the first one fires on the tick the pair enters it.
const WARNING_REPEAT_TICKS: int = 30
const EMPTY: Array = []


static func step(world: SimWorld) -> void:
	if world.ship_count() > 1:
		_ship_pairs(world)
	if world.projectiles.size() > 0:
		_projectiles(world)


## Uniform grid of live ships: cell key to ship ids in id order.
static func build_grid(kin: Kinematics, cell: float) -> Dictionary[Vector4i, Array]:
	var grid: Dictionary[Vector4i, Array] = {}
	var inv: float = 1.0 / cell
	for i: int in kin.size():
		if not kin.is_alive(i):
			continue
		var key: Vector4i = Vector4i(
			kin.site[i], floori(kin.px[i] * inv), floori(kin.py[i] * inv), floori(kin.pz[i] * inv)
		)
		var ids: Array = grid.get(key, EMPTY)
		if ids.is_empty():
			ids = []
			grid[key] = ids
		ids.append(i)
	return grid


static func _ship_pairs(world: SimWorld) -> void:
	var kin: Kinematics = world.kin
	var grid: Dictionary[Vector4i, Array] = build_grid(kin, PAIR_CELL)
	var n: int = kin.size()
	# Per ship: bounding radius plus the distance it covers in the warning horizon, so
	# a pair farther apart than the sum can neither touch nor warn (cheap reject).
	var reach: PackedFloat64Array = PackedFloat64Array()
	reach.resize(n)
	var reach_max: float = 0.0
	for i: int in n:
		reach[i] = kin.radius[i] + kin.half_length[i] + kin.vel[i].length() * WARNING_HORIZON
		if kin.is_alive(i):
			reach_max = maxf(reach_max, reach[i])
	for i: int in n:
		if not kin.is_alive(i):
			continue
		# Only the cells within the pair search distance, at most PAIR_CELL (S6).
		var box: float = minf(reach[i] + reach_max, PAIR_CELL)
		var x: float = kin.px[i]
		var y: float = kin.py[i]
		var z: float = kin.pz[i]
		for ix: int in range(floori((x - box) / PAIR_CELL), floori((x + box) / PAIR_CELL) + 1):
			for iy: int in range(floori((y - box) / PAIR_CELL), floori((y + box) / PAIR_CELL) + 1):
				for iz: int in range(
					floori((z - box) / PAIR_CELL), floori((z + box) / PAIR_CELL) + 1
				):
					for j: int in grid.get(Vector4i(kin.site[i], ix, iy, iz), EMPTY):
						if j <= i:
							continue
						var far: float = reach[i] + reach[j]
						var ex: float = kin.px[j] - x
						var ey: float = kin.py[j] - y
						var ez: float = kin.pz[j] - z
						if ex * ex + ey * ey + ez * ez <= far * far:
							_pair(world, i, j)


## Contact (impulse and damage) or proximity warning for one pair; j > i.
static func _pair(world: SimWorld, i: int, j: int) -> void:
	var kin: Kinematics = world.kin
	var r: Vector3 = kin.relative(i, j)
	var v: Vector3 = kin.vel[j] - kin.vel[i]
	var reach: float = kin.radius[i] + kin.half_length[i] + kin.radius[j] + kin.half_length[j]
	var far: float = reach + v.length() * WARNING_HORIZON
	if r.length_squared() > far * far:
		return
	var ai: Vector3 = kin.to_world(i, Vector3(0.0, 0.0, kin.half_length[i]))
	var aj: Vector3 = kin.to_world(j, Vector3(0.0, 0.0, kin.half_length[j]))
	var c: PackedVector3Array = Sweep.closest_points(-ai, ai, r - aj, r + aj)
	var gap: Vector3 = c[1] - c[0]
	var touch: float = kin.radius[i] + kin.radius[j]
	if gap.length_squared() < touch * touch:
		_contact(world, i, j, c[0], c[1])
		return
	# FT-SIM-010: warn both ships before impact, from bounding spheres (early, never late).
	var ttc: float = Sweep.time_to_reach(r, v, reach)
	if ttc < 0.0 or ttc > WARNING_HORIZON:
		return
	if ttc > WARNING_HORIZON - SimWorld.DT or world.tick % WARNING_REPEAT_TICKS == 0:
		world.emit(&"proximity", i, j, ttc)
		world.emit(&"proximity", j, i, ttc)


## Ships i and j touch; ci and cj are the closest points of their segments, relative
## to i's centre. Separates them by inverse mass, applies a normal impulse with
## RESTITUTION when closing, and damages both with the kinetic energy lost, half each
## (FT-SIM-009; friendly ships too, FT-SIM-010).
static func _contact(world: SimWorld, i: int, j: int, ci: Vector3, cj: Vector3) -> void:
	var kin: Kinematics = world.kin
	var gap: Vector3 = cj - ci
	var dist: float = gap.length()
	var n: Vector3 = gap / dist if dist > 1e-6 else _fallback_normal(kin, i, j)
	var inv_i: float = 1.0 / kin.mass[i]
	var inv_j: float = 1.0 / kin.mass[j]
	var share_i: float = inv_i / (inv_i + inv_j)
	var pen: float = kin.radius[i] + kin.radius[j] - dist
	_shift(kin, i, -n * (pen * share_i))
	_shift(kin, j, n * (pen * (1.0 - share_i)))
	var vn: float = (kin.vel[j] - kin.vel[i]).dot(n)
	if vn >= 0.0:
		return
	var impulse: float = -(1.0 + RESTITUTION) * vn / (inv_i + inv_j)
	kin.vel[i] -= n * (impulse * inv_i)
	kin.vel[j] += n * (impulse * inv_j)
	var lost: float = 0.5 * vn * vn * (1.0 - RESTITUTION * RESTITUTION) / (inv_i + inv_j)
	var rel_j: Vector3 = kin.relative(i, j)
	_collision_hit(world, i, j, ci + n * kin.radius[i], n, 0.5 * lost)
	_collision_hit(world, j, i, cj - rel_j - n * kin.radius[j], -n, 0.5 * lost)


static func _fallback_normal(kin: Kinematics, i: int, j: int) -> Vector3:
	var r: Vector3 = kin.relative(i, j)
	return r.normalized() if r.length_squared() > 1e-12 else Vector3.UP


static func _shift(kin: Kinematics, row: int, d: Vector3) -> void:
	kin.px[row] += d.x
	kin.py[row] += d.y
	kin.pz[row] += d.z
	kin.check_offset(row)


## point and toward are site-frame vectors relative to the target's centre.
static func _collision_hit(
	world: SimWorld, target: int, other: int, point: Vector3, toward: Vector3, energy: float
) -> void:
	var hit: SimHit = SimHit.new()
	hit.target_id = target
	hit.source_id = other
	hit.kind = &"collision"
	hit.point_local = world.kin.to_local(target, point)
	hit.from_local = world.kin.to_local(target, toward).normalized()
	hit.energy = energy
	world.hits.append(hit)


## Moves every projectile one tick and sweeps it against the ships near its path,
## using its motion relative to each ship (FT-SIM-009), so nothing tunnels at any
## speed. The earliest hit wins; hit and expired projectiles are removed. A projectile
## never hits its own shooter (it leaves from inside the shooter's hull).
static func _projectiles(world: SimWorld) -> void:
	var kin: Kinematics = world.kin
	var proj: ProjectileTable = world.projectiles
	var grid: Dictionary[Vector4i, Array] = build_grid(kin, CELL)
	var pad: float = _ship_pad(kin)
	var dt: float = SimWorld.DT
	var dead: PackedInt32Array = PackedInt32Array()
	for k: int in proj.size():
		var pv: Vector3 = proj.vel[k]
		var x0: float = proj.px[k]
		var y0: float = proj.py[k]
		var z0: float = proj.pz[k]
		proj.px[k] = x0 + pv.x * dt
		proj.py[k] = y0 + pv.y * dt
		proj.pz[k] = z0 + pv.z * dt
		proj.ttl[k] -= 1
		var pr: float = proj.radius[k]
		var site: int = proj.site[k]
		var shooter: int = proj.ship_ids[k]
		var reach: float = pad + pr
		var lo: Vector3i = Vector3i(
			floori((minf(x0, proj.px[k]) - reach) / CELL),
			floori((minf(y0, proj.py[k]) - reach) / CELL),
			floori((minf(z0, proj.pz[k]) - reach) / CELL)
		)
		var hi: Vector3i = Vector3i(
			floori((maxf(x0, proj.px[k]) + reach) / CELL),
			floori((maxf(y0, proj.py[k]) + reach) / CELL),
			floori((maxf(z0, proj.pz[k]) + reach) / CELL)
		)
		var best: int = -1
		var best_t: float = 2.0
		for ix: int in range(lo.x, hi.x + 1):
			for iy: int in range(lo.y, hi.y + 1):
				for iz: int in range(lo.z, hi.z + 1):
					for s: int in grid.get(Vector4i(site, ix, iy, iz), EMPTY):
						if s == shooter:
							continue
						var t: float = _sweep(kin, s, x0, y0, z0, pv, pr)
						if t >= 0.0 and t < best_t:
							best_t = t
							best = s
		if best >= 0:
			_projectile_hit(world, k, best, x0, y0, z0, best_t)
			dead.append(k)
		elif proj.ttl[k] <= 0:
			dead.append(k)
	proj.remove_rows(dead)


## Largest ship bounding radius plus the largest distance a ship moved this tick (m).
static func _ship_pad(kin: Kinematics) -> float:
	var bound: float = 0.0
	var moved: float = 0.0
	for i: int in kin.size():
		if kin.is_alive(i):
			bound = maxf(bound, kin.radius[i] + kin.half_length[i])
			moved = maxf(moved, kin.vel[i].length() * SimWorld.DT)
	return bound + moved


## Sweep time in [0, 1] of a projectile starting this tick at (x0, y0, z0) with
## velocity pv against ship s, or Sweep.NONE.
static func _sweep(
	kin: Kinematics, s: int, x0: float, y0: float, z0: float, pv: Vector3, r: float
) -> float:
	var vs: Vector3 = kin.vel[s]
	var dt: float = SimWorld.DT
	var start: Vector3 = Vector3(
		x0 - (kin.px[s] - vs.x * dt), y0 - (kin.py[s] - vs.y * dt), z0 - (kin.pz[s] - vs.z * dt)
	)
	if kin.half_length[s] == 0.0:
		return Sweep.sphere(start, (pv - vs) * dt, kin.radius[s] + r)
	var axis: Vector3 = kin.to_world(s, Vector3(0.0, 0.0, kin.half_length[s]))
	return Sweep.capsule(start, (pv - vs) * dt, axis, kin.radius[s] + r)


static func _projectile_hit(
	world: SimWorld, k: int, target: int, x0: float, y0: float, z0: float, t: float
) -> void:
	var kin: Kinematics = world.kin
	var proj: ProjectileTable = world.projectiles
	var vs: Vector3 = kin.vel[target]
	var dt: float = SimWorld.DT
	var rel_vel: Vector3 = proj.vel[k] - vs
	var start: Vector3 = Vector3(
		x0 - (kin.px[target] - vs.x * dt),
		y0 - (kin.py[target] - vs.y * dt),
		z0 - (kin.pz[target] - vs.z * dt)
	)
	var hit: SimHit = SimHit.new()
	hit.target_id = target
	hit.source_id = proj.ship_ids[k]
	hit.kind = &"projectile"
	hit.point_local = kin.to_local(target, start + rel_vel * (dt * t))
	hit.from_local = kin.to_local(target, -rel_vel).normalized()
	hit.energy = proj.energy[k]
	world.hits.append(hit)
