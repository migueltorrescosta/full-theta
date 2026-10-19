class_name CollisionSystem
extends RefCounted
## Ship contacts, proximity warnings and swept projectiles (T029, FT-SIM-009,
## FT-SIM-010, FT-ARC-007: no Godot physics). Runs after the integrator and the weapons
## each tick. Broadphase is a uniform grid per site, rebuilt every tick and keyed by
## Vector4i(site, ix, iy, iz), so ships at different sites never share a cell (S6).
## Sites wrap (FT-SIM-035, D124): cell indexes wrap modulo the cells per axis (the
## period is a multiple of both cell sizes, SimWorld.period_errors) and every distance
## is a minimum image, so contacts, warnings and shots work across the seams.
## Ships at the start of the tick are taken as end position minus velocity times DT;
## the error is a dt^2 / 2, under 3 mm at 20 m/s^2.

## Projectile broadphase cell (m, S6).
const CELL: float = 250.0
## Ship-pair broadphase cell (m): pairs up to this far apart are always checked, so
## proximity warnings get the full horizon for closing speeds up to about
## (PAIR_CELL - reach) / WARNING_HORIZON (90 m/s for two corvettes, D119) and at least
## PAIR_CELL of warning distance above that.
const PAIR_CELL: float = 500.0
## Coefficient of restitution of ship-ship contacts (dimensionless): hulls are mostly
## inelastic, so most of the closing kinetic energy turns into damage.
const RESTITUTION: float = 0.2
## Ships on course to touch within this time get a &"proximity" warning (s, FT-SIM-010).
const WARNING_HORIZON: float = 5.0
## While a pair stays warnable (within PAIR_CELL and on course to touch inside the
## horizon) the warning repeats on ticks that are a multiple of this (ticks). The first
## one fires on the tick motion brings the pair within reach; when a velocity change
## makes it warnable instead, it can wait up to this many ticks (stateless check).
const WARNING_REPEAT_TICKS: int = 30
const EMPTY: Array = []


static func step(world: SimWorld) -> void:
	if world.ship_count() > 1:
		_ship_pairs(world)
	if world.projectiles.size() > 0:
		_projectiles(world)


## Bounding radius of a ship's capsule (m): radius plus half length.
static func _bound(kin: Kinematics, row: int) -> float:
	return kin.radius[row] + kin.half_length[row]


## Cells per axis of a site for a cell size (m).
static func _cells_per_axis(kin: Kinematics, cell: float) -> int:
	return maxi(1, roundi(kin.period / cell))


## Uniform grid of live ships: cell key (wrapped) to ship ids in id order.
static func build_grid(kin: Kinematics, cell: float) -> Dictionary[Vector4i, Array]:
	var grid: Dictionary[Vector4i, Array] = {}
	var n: int = _cells_per_axis(kin, cell)
	var c: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0])
	for i: int in kin.size():
		if not kin.is_alive(i):
			continue
		kin.cell_range(i, cell, 0.0, c)
		var key: Vector4i = Vector4i(kin.site[i], posmod(c[0], n), posmod(c[1], n), posmod(c[2], n))
		var ids: Array = grid.get(key, EMPTY)
		if ids.is_empty():
			ids = []
			grid[key] = ids
		ids.append(i)
	return grid


## Fills out with the ship ids in the grid cells box[0..2]..box[3..5] (unwrapped,
## inclusive) of a site, each wrapped modulo n and each cell visited once, in cell order
## then id order.
static func _in_cells(
	grid: Dictionary[Vector4i, Array], site: int, box: PackedInt32Array, n: int, out: Array[int]
) -> void:
	out.clear()
	var lo: Vector3i = Vector3i(box[0], box[1], box[2])
	var hi: Vector3i = Vector3i(box[3], box[4], box[5])
	var count: Vector3i = (hi - lo + Vector3i.ONE).mini(n)
	for ix: int in range(lo.x, lo.x + count.x):
		for iy: int in range(lo.y, lo.y + count.y):
			for iz: int in range(lo.z, lo.z + count.z):
				var key: Vector4i = Vector4i(site, posmod(ix, n), posmod(iy, n), posmod(iz, n))
				for j: int in grid.get(key, EMPTY):
					out.append(j)


static func _ship_pairs(world: SimWorld) -> void:
	var kin: Kinematics = world.kin
	var grid: Dictionary[Vector4i, Array] = build_grid(kin, PAIR_CELL)
	var cells: int = _cells_per_axis(kin, PAIR_CELL)
	var n: int = kin.size()
	# Per ship: bounding radius plus the distance it covers in the warning horizon, so
	# a pair farther apart than the sum can neither touch nor warn (cheap reject).
	var reach: PackedFloat64Array = PackedFloat64Array()
	reach.resize(n)
	var reach_max: float = 0.0
	for i: int in n:
		reach[i] = _bound(kin, i) + kin.vel[i].length() * WARNING_HORIZON
		if kin.is_alive(i):
			reach_max = maxf(reach_max, reach[i])
	var box: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0])
	var near: Array[int] = []
	for i: int in n:
		if not kin.is_alive(i):
			continue
		# Only the cells within the pair search distance, at most PAIR_CELL (S6): farther
		# pairs can neither touch nor warn.
		kin.cell_range(i, PAIR_CELL, minf(reach[i] + reach_max, PAIR_CELL), box)
		_in_cells(grid, kin.site[i], box, cells, near)
		for j: int in near:
			if j <= i:
				continue
			var far: float = reach[i] + reach[j]
			if kin.relative(i, j).length_squared() <= far * far:
				_pair(world, i, j)


## Contact (impulse and damage) or proximity warning for one pair; j > i.
static func _pair(world: SimWorld, i: int, j: int) -> void:
	var kin: Kinematics = world.kin
	var r: Vector3 = kin.relative(i, j)
	var v: Vector3 = kin.vel[j] - kin.vel[i]
	var reach: float = _bound(kin, i) + _bound(kin, j)
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
	var ttc: float = _warning_time(r, v, reach)
	if ttc < 0.0:
		return
	# Stateless first warning: the pair was not warnable at the start of the tick.
	var first: bool = _warning_time(r - v * SimWorld.DT, v, reach) < 0.0
	if first or world.tick % WARNING_REPEAT_TICKS == 0:
		world.emit(&"proximity", i, j, ttc)
		world.emit(&"proximity", j, i, ttc)


## Time until bounding spheres reach (s) when the pair is warnable (within PAIR_CELL and
## inside the horizon), else -1.
static func _warning_time(r: Vector3, v: Vector3, reach: float) -> float:
	if r.length_squared() > PAIR_CELL * PAIR_CELL:
		return -1.0
	var ttc: float = Sweep.time_to_reach(r, v, reach)
	return ttc if ttc <= WARNING_HORIZON else -1.0


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
	# j's centre before the separation: cj is relative to i's centre before it too.
	var rel_j: Vector3 = kin.relative(i, j)
	_shift(kin, i, -n * (pen * share_i))
	_shift(kin, j, n * (pen * (1.0 - share_i)))
	var vn: float = (kin.vel[j] - kin.vel[i]).dot(n)
	if vn >= 0.0:
		return
	var impulse: float = -(1.0 + RESTITUTION) * vn / (inv_i + inv_j)
	kin.vel[i] -= n * (impulse * inv_i)
	kin.vel[j] += n * (impulse * inv_j)
	var lost: float = 0.5 * vn * vn * (1.0 - RESTITUTION * RESTITUTION) / (inv_i + inv_j)
	_collision_hit(world, i, j, ci + n * kin.radius[i], n, 0.5 * lost)
	_collision_hit(world, j, i, cj - rel_j - n * kin.radius[j], -n, 0.5 * lost)


static func _fallback_normal(kin: Kinematics, i: int, j: int) -> Vector3:
	var r: Vector3 = kin.relative(i, j)
	return r.normalized() if r.length_squared() > 1e-12 else Vector3.UP


static func _shift(kin: Kinematics, row: int, d: Vector3) -> void:
	kin.translate(row, d.x, d.y, d.z)


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
## never hits its own shooter (it leaves from inside the shooter's hull). Start points
## are minimum images, so a shot across a seam hits (FT-SIM-035).
static func _projectiles(world: SimWorld) -> void:
	var kin: Kinematics = world.kin
	var proj: ProjectileTable = world.projectiles
	var grid: Dictionary[Vector4i, Array] = build_grid(kin, CELL)
	var cells: int = _cells_per_axis(kin, CELL)
	var pad: float = _ship_pad(kin)
	var dt: float = SimWorld.DT
	var dead: PackedInt32Array = PackedInt32Array()
	var box: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0])
	var near: Array[int] = []
	for k: int in proj.size():
		proj.ttl[k] -= 1
		var shooter: int = proj.ship_ids[k]
		proj.cell_box(k, dt, pad + proj.radius[k], CELL, box)
		_in_cells(grid, proj.site[k], box, cells, near)
		var best: int = -1
		var best_t: float = 2.0
		var best_start: Vector3 = Vector3.ZERO
		for s: int in near:
			if s == shooter:
				continue
			var start: Vector3 = proj.relative_start(k, kin, s, dt)
			var t: float = _sweep(kin, s, start, proj.vel[k], proj.radius[k])
			if t >= 0.0 and t < best_t:
				best_t = t
				best = s
				best_start = start
		proj.advance(k, kin, dt)
		if best >= 0:
			_projectile_hit(world, k, best, best_start, best_t)
			dead.append(k)
		elif proj.ttl[k] <= 0:
			dead.append(k)
	proj.remove_rows(dead)


## Largest ship bounding radius plus the largest distance a ship moved this tick (m).
static func _ship_pad(kin: Kinematics) -> float:
	var most: float = 0.0
	var moved: float = 0.0
	for i: int in kin.size():
		if kin.is_alive(i):
			most = maxf(most, _bound(kin, i))
			moved = maxf(moved, kin.vel[i].length() * SimWorld.DT)
	return most + moved


## Sweep time in [0, 1] of a projectile starting this tick at `start` relative to ship
## s at the start of the tick, with velocity pv, against s, or Sweep.NONE.
static func _sweep(kin: Kinematics, s: int, start: Vector3, pv: Vector3, r: float) -> float:
	var axis: Vector3 = kin.to_world(s, Vector3(0.0, 0.0, kin.half_length[s]))
	return Sweep.capsule(start, (pv - kin.vel[s]) * SimWorld.DT, axis, kin.radius[s] + r)


static func _projectile_hit(world: SimWorld, k: int, target: int, start: Vector3, t: float) -> void:
	var kin: Kinematics = world.kin
	var proj: ProjectileTable = world.projectiles
	var rel_vel: Vector3 = proj.vel[k] - kin.vel[target]
	var hit: SimHit = SimHit.new()
	hit.target_id = target
	hit.source_id = proj.ship_ids[k]
	hit.kind = &"projectile"
	hit.point_local = kin.to_local(target, start + rel_vel * (SimWorld.DT * t))
	hit.from_local = kin.to_local(target, -rel_vel).normalized()
	hit.energy = proj.energy[k]
	world.hits.append(hit)
