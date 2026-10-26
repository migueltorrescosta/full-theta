class_name CollisionSystem
extends RefCounted
## Ship contacts, proximity warnings and swept projectiles (T029, FT-SIM-009,
## FT-SIM-010, FT-ARC-007: no Godot physics). Runs after the integrator and the weapons
## each tick. Broadphase is a uniform grid over the one cube, rebuilt every tick: cell
## (ix, iy, iz packed into one int, _key) to ship ids (S6, D230). Ship pairs
## scan the later ships directly when there are fewer of them than cells to look up, with
## the same pairs in the same order.
## The cube wraps (FT-SIM-035, D124, D229): cell indexes wrap modulo the cells per axis (the
## period is a multiple of both cell sizes, SimWorld.period_errors) and every distance
## is a minimum image, so contacts, warnings and shots work across the seams.
## Ships at the start of the tick are taken as end position minus velocity times DT;
## the error is a dt^2 / 2, under 3 mm at 20 m/s^2.

## Projectile broadphase cell (m, S6).
const CELL: float = PeriodRules.CELL
## Ship-pair broadphase cell (m): pairs up to this far apart are always checked, so
## proximity warnings get the full horizon for closing speeds up to about
## (PAIR_CELL - reach) / WARNING_HORIZON (90 m/s for two corvettes, D119) and at least
## PAIR_CELL of warning distance above that.
const PAIR_CELL: float = PeriodRules.PAIR_CELL
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


static func step(world: SimWorld) -> void:
	if world.ship_count() > 1:
		_ship_pairs(world)
	if world.projectiles.size() > 0:
		_projectiles(world)


## Bounding radius of a ship's capsule (m): radius plus half length.
static func _bound(kin: Kinematics, row: int) -> float:
	return kin.radius[row] + kin.half_length[row]


## Cells per axis of the cube for a cell size (m).
static func _cells_per_axis(kin: Kinematics, cell: float) -> int:
	return maxi(1, roundi(kin.period / cell))


## Uniform grid of live ships: cell key (_key of the wrapped cell) to ship ids in id
## order.
static func build_grid(kin: Kinematics, cell: float) -> Dictionary[int, PackedInt32Array]:
	var grid: Dictionary[int, PackedInt32Array] = {}
	var n: int = _cells_per_axis(kin, cell)
	var alive: PackedByteArray = kin.alive
	var c: PackedInt32Array = PackedInt32Array()
	kin.cell_coords(cell, c)
	for i: int in alive.size():
		if alive[i] != 1:
			continue
		_add(
			grid, _key(posmod(c[3 * i], n), posmod(c[3 * i + 1], n), posmod(c[3 * i + 2], n), n), i
		)
	return grid


## Appends ship i to the grid's cell key.
static func _add(grid: Dictionary[int, PackedInt32Array], key: int, i: int) -> void:
	if grid.has(key):
		grid[key].append(i)
	else:
		grid[key] = PackedInt32Array([i])


## Grid key of a wrapped cell (x, y, z in [0, n)), n cells per axis: below 2^60 as
## n is at most SimWorld.MAX_CELLS_PER_AXIS (SimWorld.period_errors).
static func _key(x: int, y: int, z: int, n: int) -> int:
	return (x * n + y) * n + z


## Fills out with the ship ids in the grid cells box[0..2]..box[3..5] (unwrapped,
## inclusive), each wrapped modulo n and each cell visited once, in cell order
## then id order.
static func _in_cells(
	grid: Dictionary[int, PackedInt32Array], box: PackedInt32Array, n: int, out: PackedInt32Array
) -> void:
	out.clear()
	var lx: int = box[0]
	var ly: int = box[1]
	var lz: int = box[2]
	var cx: int = mini(box[3] - lx + 1, n)
	var cy: int = mini(box[4] - ly + 1, n)
	var cz: int = mini(box[5] - lz + 1, n)
	for ix: int in range(lx, lx + cx):
		var kx: int = posmod(ix, n)
		for iy: int in range(ly, ly + cy):
			var ky: int = kx * n + posmod(iy, n)
			for iz: int in range(lz, lz + cz):
				var key: int = ky * n + posmod(iz, n)
				if grid.has(key):
					out.append_array(grid[key])


static func _ship_pairs(world: SimWorld) -> void:
	var kin: Kinematics = world.kin
	var cells: int = _cells_per_axis(kin, PAIR_CELL)
	var n: int = kin.size()
	var alive: PackedByteArray = kin.alive
	var vel: PackedVector3Array = kin.vel
	# The grid (build_grid), each live ship's wrapped cell, and the live ships in id
	# order. Collisions don't change liveness, so the list holds for the whole pass.
	var grid: Dictionary[int, PackedInt32Array] = {}
	var cell: PackedInt32Array = PackedInt32Array()
	kin.cell_coords(PAIR_CELL, cell)
	var live: PackedInt32Array = PackedInt32Array()
	var box: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0])
	# Per ship: bounding radius plus the distance it covers in the warning horizon, so
	# a pair farther apart than the sum can neither touch nor warn (cheap reject).
	var reach: PackedFloat64Array = PackedFloat64Array()
	reach.resize(n)
	var reach_max: float = 0.0
	for i: int in n:
		reach[i] = kin.radius[i] + kin.half_length[i] + vel[i].length() * WARNING_HORIZON
		if alive[i] != 1:
			continue
		reach_max = maxf(reach_max, reach[i])
		var x: int = posmod(cell[3 * i], cells)
		var y: int = posmod(cell[3 * i + 1], cells)
		var z: int = posmod(cell[3 * i + 2], cells)
		cell[3 * i] = x
		cell[3 * i + 1] = y
		cell[3 * i + 2] = z
		live.append(i)
		_add(grid, _key(x, y, z, cells), i)
	var near: PackedInt32Array = PackedInt32Array()
	var order: PackedInt64Array = PackedInt64Array()
	for li: int in live.size():
		var i: int = live[li]
		# Only the cells within the pair search distance, at most PAIR_CELL (S6): farther
		# pairs can neither touch nor warn.
		kin.cell_range(i, PAIR_CELL, minf(reach[i] + reach_max, PAIR_CELL), box)
		var cx: int = mini(box[3] - box[0] + 1, cells)
		var cy: int = mini(box[4] - box[1] + 1, cells)
		var cz: int = mini(box[5] - box[2] + 1, cells)
		if live.size() - li - 1 < cx * cy * cz:
			# Fewer later ships than cells: the later ships in the box, in the order
			# _in_cells lists them (cell order, then id), found by their cells' offsets
			# from the box's low corner.
			near.clear()
			order.clear()
			for lj: int in range(li + 1, live.size()):
				var j: int = live[lj]
				var ox: int = posmod(cell[3 * j] - box[0], cells)
				var oy: int = posmod(cell[3 * j + 1] - box[1], cells)
				var oz: int = posmod(cell[3 * j + 2] - box[2], cells)
				if ox < cx and oy < cy and oz < cz:
					order.append((((ox * cy + oy) * cz + oz) << 32) | j)
			order.sort()
			for k: int in order:
				near.append(k & 0xFFFFFFFF)
		else:
			_in_cells(grid, box, cells, near)
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


## point and toward are world-frame vectors relative to the target's centre.
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
	var grid: Dictionary[int, PackedInt32Array] = build_grid(kin, CELL)
	var cells: int = _cells_per_axis(kin, CELL)
	var pad: float = _ship_pad(kin)
	var dt: float = SimWorld.DT
	var dead: PackedInt32Array = PackedInt32Array()
	var box: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0])
	var near: PackedInt32Array = PackedInt32Array()
	var ttl: PackedInt32Array = proj.ttl
	var shooters: PackedInt32Array = proj.ship_ids
	var radius: PackedFloat64Array = proj.radius
	var pvel: PackedVector3Array = proj.vel
	for k: int in shooters.size():
		ttl[k] -= 1
		var shooter: int = shooters[k]
		proj.cell_box(k, dt, pad + radius[k], CELL, box)
		_in_cells(grid, box, cells, near)
		var best: int = -1
		var best_t: float = 2.0
		var best_start: Vector3 = Vector3.ZERO
		for s: int in near:
			if s == shooter:
				continue
			var start: Vector3 = proj.relative_start(k, kin, s, dt)
			var t: float = _sweep(kin, s, start, pvel[k], radius[k])
			if t >= 0.0 and t < best_t:
				best_t = t
				best = s
				best_start = start
		proj.advance(k, kin, dt)
		if best >= 0:
			_projectile_hit(world, k, best, best_start, best_t)
			dead.append(k)
		elif ttl[k] <= 0:
			dead.append(k)
	proj.remove_rows(dead)


## Largest ship bounding radius plus the largest distance a ship moved this tick (m).
static func _ship_pad(kin: Kinematics) -> float:
	var most: float = 0.0
	var moved: float = 0.0
	var alive: PackedByteArray = kin.alive
	var radius: PackedFloat64Array = kin.radius
	var half_length: PackedFloat64Array = kin.half_length
	var vel: PackedVector3Array = kin.vel
	for i: int in alive.size():
		if alive[i] == 1:
			most = maxf(most, radius[i] + half_length[i])
			moved = maxf(moved, vel[i].length() * SimWorld.DT)
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
	hit.damage_type = proj.damage_type[k]
	world.hits.append(hit)
