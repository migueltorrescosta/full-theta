class_name S6WorldObject
extends RefCounted
## S6 spike world, object layout: one RefCounted per ship and projectile,
## held in arrays ordered by id (FT-ARC-009). Same rules, constants and
## arithmetic as S6WorldPacked, so both give the same state for one seed.

const W := preload("res://spikes/s6/s6_world_packed.gd")


class Ship:
	extends RefCounted
	var id: int
	var site: int
	var pos: Vector3
	var pos_old: Vector3
	var vel: Vector3
	var rot: Quaternion
	var ang: Vector3
	var thrust: Vector3
	var torque: Vector3
	var waypoint: Vector3
	var mass: float = 5.0e4
	var inertia: Vector3 = Vector3(2.0e6, 2.5e6, 1.5e6)
	var max_thrust: Vector3 = Vector3(5.0e5, 5.0e5, 1.0e6)
	var max_torque: Vector3 = Vector3(2.0e6, 2.0e6, 2.0e6)


class Projectile:
	extends RefCounted
	var site: int
	var pos: Vector3
	var vel: Vector3
	var ttl: int


var benchmark: bool = false
var tick: int = 0
var events: PackedInt32Array = PackedInt32Array()
var total_hits: int = 0
var total_contacts: int = 0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _ships: Array[Ship] = []
var _projs: Array[Projectile] = []
var _cells: Dictionary[int, Array] = {}


func _init(seed_value: int) -> void:
	_rng.seed = seed_value


func setup_benchmark(n_ships: int, n_proj: int) -> void:
	benchmark = true
	for i in n_ships:
		var p := _rand_in_arena()
		var axis := Vector3(_rng.randf() - 0.5, _rng.randf() - 0.5, _rng.randf() - 0.5)
		var rot := Quaternion(axis.normalized(), _rng.randf() * TAU)
		add_ship(0, p, Vector3.ZERO, rot, Vector3.ZERO, Vector3.ZERO)
		_ships[i].waypoint = _rand_in_arena()
	for k in n_proj:
		add_projectile(0, Vector3.ZERO, Vector3.ZERO, 0)
		_fire(_projs[k])


func add_ship(
	site: int, pos: Vector3, vel: Vector3, rot: Quaternion, thrust: Vector3, torque: Vector3
) -> int:
	var s := Ship.new()
	s.id = _ships.size()
	s.site = site
	s.pos = pos
	s.pos_old = pos
	s.vel = vel
	s.rot = rot
	s.thrust = thrust
	s.torque = torque
	s.waypoint = pos
	_ships.append(s)
	return s.id


func add_projectile(site: int, pos: Vector3, vel: Vector3, ttl: int) -> int:
	var pr := Projectile.new()
	pr.site = site
	pr.pos = pos
	pr.vel = vel
	pr.ttl = ttl
	_projs.append(pr)
	return _projs.size() - 1


func ship_pos(i: int) -> Vector3:
	return _ships[i].pos


func ship_vel(i: int) -> Vector3:
	return _ships[i].vel


func ship_rot(i: int) -> Quaternion:
	return _ships[i].rot


func proj_pos(k: int) -> Vector3:
	return _projs[k].pos


func ship_count() -> int:
	return _ships.size()


func step() -> void:
	events.clear()
	_step_ships()
	_build_grid()
	_ship_pairs()
	_step_projectiles()
	tick += 1


func checksum() -> float:
	var s: float = 0.0
	for sh in _ships:
		s += sh.pos.x + sh.pos.y + sh.pos.z
	for pr in _projs:
		s += pr.pos.x + pr.pos.y + pr.pos.z
	return s


func _step_ships() -> void:
	for s in _ships:
		var q: Quaternion = s.rot
		var p: Vector3 = s.pos
		var v: Vector3 = s.vel
		var w: Vector3 = s.ang
		if benchmark:
			_assist(s, q, p, v, w)
		var acc: Vector3 = (q * s.thrust) / s.mass
		s.pos_old = p
		s.pos = p + v * W.DT + acc * W.HALF_DT2
		s.vel = v + acc * W.DT
		var w_dot: Vector3 = (s.torque - w.cross(s.inertia * w)) / s.inertia
		w += w_dot * W.DT
		s.ang = w
		var h: Vector3 = w * W.HALF_DT
		s.rot = (q * Quaternion(h.x, h.y, h.z, 1.0)).normalized()


func _assist(s: Ship, q: Quaternion, p: Vector3, v: Vector3, w: Vector3) -> void:
	var to_wp: Vector3 = s.waypoint - p
	var dist: float = to_wp.length()
	if dist < W.WAYPOINT_REACHED:
		s.waypoint = _rand_in_arena()
		to_wp = s.waypoint - p
		dist = to_wp.length()
	var dir: Vector3 = to_wp / dist
	var desired: Vector3 = dir * minf(W.MAX_SPEED, dist * 0.25)
	var q_inv: Quaternion = q.inverse()
	s.thrust = ((q_inv * (desired - v)) * (s.mass / W.ASSIST_TAU)).clamp(
		-s.max_thrust, s.max_thrust
	)
	var turn: Vector3 = Vector3.FORWARD.cross(q_inv * dir) * W.TURN_GAIN
	var mt := W.MAX_TURN
	turn = turn.clamp(Vector3(-mt, -mt, -mt), Vector3(mt, mt, mt))
	s.torque = ((turn - w) * s.inertia / W.ASSIST_TAU).clamp(-s.max_torque, s.max_torque)


func _cell_key(site: int, ix: int, iy: int, iz: int) -> int:
	var o := W.KEY_OFF
	return (((site << 20) | (ix + o)) << 20 | (iy + o)) << 20 | (iz + o)


func _build_grid() -> void:
	_cells.clear()
	for s in _ships:
		var p: Vector3 = s.pos
		var key := _cell_key(
			s.site, floori(p.x * W.INV_CELL), floori(p.y * W.INV_CELL), floori(p.z * W.INV_CELL)
		)
		var cell: Array = _cells.get(key, [])
		if cell.is_empty():
			_cells[key] = cell
		cell.append(s)


func _ship_pairs() -> void:
	var reach: float = 2.0 * W.SHIP_RADIUS + W.PROXIMITY
	var warn2: float = reach * reach
	var touch2: float = 4.0 * W.SHIP_RADIUS * W.SHIP_RADIUS
	var pad := Vector3(reach, reach, reach)
	for a in _ships:
		var p: Vector3 = a.pos
		var lo: Vector3 = (p - pad) * W.INV_CELL
		var hi: Vector3 = (p + pad) * W.INV_CELL
		for ix in range(floori(lo.x), floori(hi.x) + 1):
			for iy in range(floori(lo.y), floori(hi.y) + 1):
				for iz in range(floori(lo.z), floori(hi.z) + 1):
					var cell: Array = _cells.get(_cell_key(a.site, ix, iy, iz), W.EMPTY)
					for b: Ship in cell:
						if b.id <= a.id:
							continue
						var d2: float = p.distance_squared_to(b.pos)
						if d2 < touch2:
							_event(W.EV_CONTACT, a.id, b.id)
							total_contacts += 1
						elif d2 < warn2:
							_event(W.EV_PROXIMITY, a.id, b.id)


func _step_projectiles() -> void:
	var reach: float = W.SHIP_RADIUS + W.PROJ_RADIUS
	var reach2: float = reach * reach
	var pad := Vector3(reach + 5.0, reach + 5.0, reach + 5.0)
	for k in _projs.size():
		var pr: Projectile = _projs[k]
		if pr.ttl <= 0:
			if benchmark:
				_fire(pr)
			continue
		var p0: Vector3 = pr.pos
		var p1: Vector3 = p0 + pr.vel * W.DT
		pr.pos = p1
		pr.ttl -= 1
		var lo: Vector3 = (p0.min(p1) - pad) * W.INV_CELL
		var hi: Vector3 = (p0.max(p1) + pad) * W.INV_CELL
		var best: Ship = null
		var best_t: float = 2.0
		for ix in range(floori(lo.x), floori(hi.x) + 1):
			for iy in range(floori(lo.y), floori(hi.y) + 1):
				for iz in range(floori(lo.z), floori(hi.z) + 1):
					var cell: Array = _cells.get(_cell_key(pr.site, ix, iy, iz), W.EMPTY)
					for s: Ship in cell:
						var rel0: Vector3 = p0 - s.pos_old
						var d: Vector3 = (p1 - p0) - (s.pos - s.pos_old)
						var dd: float = d.length_squared()
						var t: float = 0.0
						if dd > 0.0:
							t = clampf(-rel0.dot(d) / dd, 0.0, 1.0)
						if (rel0 + d * t).length_squared() <= reach2 and t < best_t:
							best_t = t
							best = s
		if best != null:
			_event(W.EV_HIT, k, best.id)
			total_hits += 1
			pr.ttl = 0
			if benchmark:
				_fire(pr)


func _fire(pr: Projectile) -> void:
	var n := _ships.size()
	var shooter: Ship = _ships[_rng.randi_range(0, n - 1)]
	var target: Ship = _ships[(shooter.id + _rng.randi_range(1, n - 1)) % n]
	var rel: Vector3 = target.pos - shooter.pos
	var lead: float = rel.length() / W.PROJ_SPEED
	var aim: Vector3 = rel + (target.vel - shooter.vel) * lead
	var spread := Vector3(_rng.randf() - 0.5, _rng.randf() - 0.5, _rng.randf() - 0.5) * 0.004
	var dir: Vector3 = (aim.normalized() + spread).normalized()
	pr.site = shooter.site
	pr.pos = shooter.pos + dir * (W.SHIP_RADIUS + 2.0)
	pr.vel = shooter.vel + dir * W.PROJ_SPEED
	pr.ttl = W.PROJ_TTL


func _event(kind: int, a: int, b: int) -> void:
	events.append(tick)
	events.append(kind)
	events.append(a)
	events.append(b)


func _rand_in_arena() -> Vector3:
	return Vector3(
		(_rng.randf() * 2.0 - 1.0) * W.ARENA,
		(_rng.randf() * 2.0 - 1.0) * W.ARENA,
		(_rng.randf() * 2.0 - 1.0) * W.ARENA
	)
