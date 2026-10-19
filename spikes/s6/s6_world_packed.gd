class_name S6WorldPacked
extends RefCounted
## S6 spike world, packed layout: one packed array per field, indexed by
## entity id (structure of arrays). Positions are site-local float32 offsets
## (site id plus Vector3); FT-SIM-035 now asks for three 64-bit floats
## (D104). Iteration is in id order (FT-ARC-009) and every random draw comes
## from one seeded RNG (FT-ARC-008).

const DT: float = 1.0 / 60.0
const HALF_DT: float = 0.5 / 60.0
const HALF_DT2: float = 0.5 / 3600.0
const SHIP_RADIUS: float = 25.0
const PROJ_RADIUS: float = 0.5
const PROXIMITY: float = 100.0
const CELL: float = 250.0
const INV_CELL: float = 1.0 / 250.0
const KEY_OFF: int = 1 << 19
const PROJ_SPEED: float = 1500.0
const PROJ_TTL: int = 180
const MAX_SPEED: float = 150.0
const TURN_GAIN: float = 1.0
const MAX_TURN: float = 0.6
const ASSIST_TAU: float = 1.0
const ARENA: float = 2000.0
const WAYPOINT_REACHED: float = 150.0
const EV_HIT: int = 1
const EV_PROXIMITY: int = 2
const EV_CONTACT: int = 3
const EMPTY: Array = []

## Benchmark mode: ships fly assisted to random waypoints and dead
## projectiles are refired at once. Scripted mode keeps inputs as set.
var benchmark: bool = false
var tick: int = 0
## Events of the last tick, four ints each: tick, kind, a, b.
var events: PackedInt32Array = PackedInt32Array()
var total_hits: int = 0
var total_contacts: int = 0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _n_ships: int = 0
var _site: PackedInt32Array = PackedInt32Array()
var _pos: PackedVector3Array = PackedVector3Array()
var _pos_old: PackedVector3Array = PackedVector3Array()
var _vel: PackedVector3Array = PackedVector3Array()
var _rot: Array[Quaternion] = []
var _ang: PackedVector3Array = PackedVector3Array()
var _thrust: PackedVector3Array = PackedVector3Array()
var _torque: PackedVector3Array = PackedVector3Array()
var _waypoint: PackedVector3Array = PackedVector3Array()
var _mass: PackedFloat32Array = PackedFloat32Array()
var _inertia: PackedVector3Array = PackedVector3Array()
var _max_thrust: PackedVector3Array = PackedVector3Array()
var _max_torque: PackedVector3Array = PackedVector3Array()

var _n_proj: int = 0
var _p_site: PackedInt32Array = PackedInt32Array()
var _p_pos: PackedVector3Array = PackedVector3Array()
var _p_vel: PackedVector3Array = PackedVector3Array()
var _p_ttl: PackedInt32Array = PackedInt32Array()

var _cells: Dictionary[int, Array] = {}


func _init(seed_value: int) -> void:
	_rng.seed = seed_value


## Fills the world for the R6 benchmark: ships spread over a cube of
## 2 * ARENA metres at site 0, every projectile already fired.
func setup_benchmark(n_ships: int, n_proj: int) -> void:
	benchmark = true
	for i in n_ships:
		var p := _rand_in_arena()
		var axis := Vector3(_rng.randf() - 0.5, _rng.randf() - 0.5, _rng.randf() - 0.5)
		var rot := Quaternion(axis.normalized(), _rng.randf() * TAU)
		add_ship(0, p, Vector3.ZERO, rot, Vector3.ZERO, Vector3.ZERO)
		_waypoint[i] = _rand_in_arena()
	for k in n_proj:
		add_projectile(0, Vector3.ZERO, Vector3.ZERO, 0)
		_fire(k)


## Adds a ship with a fixed definition (50 t corvette). Returns its id.
func add_ship(
	site: int, pos: Vector3, vel: Vector3, rot: Quaternion, thrust: Vector3, torque: Vector3
) -> int:
	_site.append(site)
	_pos.append(pos)
	_pos_old.append(pos)
	_vel.append(vel)
	_rot.append(rot)
	_ang.append(Vector3.ZERO)
	_thrust.append(thrust)
	_torque.append(torque)
	_waypoint.append(pos)
	_mass.append(5.0e4)
	_inertia.append(Vector3(2.0e6, 2.5e6, 1.5e6))
	_max_thrust.append(Vector3(5.0e5, 5.0e5, 1.0e6))
	_max_torque.append(Vector3(2.0e6, 2.0e6, 2.0e6))
	_n_ships += 1
	return _n_ships - 1


## Adds a projectile; ttl in ticks (0 or less means dead). Returns its id.
func add_projectile(site: int, pos: Vector3, vel: Vector3, ttl: int) -> int:
	_p_site.append(site)
	_p_pos.append(pos)
	_p_vel.append(vel)
	_p_ttl.append(ttl)
	_n_proj += 1
	return _n_proj - 1


func ship_pos(i: int) -> Vector3:
	return _pos[i]


func ship_vel(i: int) -> Vector3:
	return _vel[i]


func ship_rot(i: int) -> Quaternion:
	return _rot[i]


func proj_pos(k: int) -> Vector3:
	return _p_pos[k]


func ship_count() -> int:
	return _n_ships


func step() -> void:
	events.clear()
	_step_ships()
	_build_grid()
	_ship_pairs()
	_step_projectiles()
	tick += 1


## Sum of all coordinates, to compare runs and layouts.
func checksum() -> float:
	var s: float = 0.0
	for i in _n_ships:
		var p: Vector3 = _pos[i]
		s += p.x + p.y + p.z
	for k in _n_proj:
		var p: Vector3 = _p_pos[k]
		s += p.x + p.y + p.z
	return s


func _step_ships() -> void:
	for i in _n_ships:
		var q: Quaternion = _rot[i]
		var p: Vector3 = _pos[i]
		var v: Vector3 = _vel[i]
		var w: Vector3 = _ang[i]
		var inertia: Vector3 = _inertia[i]
		var mass: float = _mass[i]
		if benchmark:
			_assist(i, q, p, v, w, inertia, mass)
		var acc: Vector3 = (q * _thrust[i]) / mass
		_pos_old[i] = p
		_pos[i] = p + v * DT + acc * HALF_DT2
		_vel[i] = v + acc * DT
		# Euler's equations with diagonal inertia, body frame.
		var w_dot: Vector3 = (_torque[i] - w.cross(inertia * w)) / inertia
		w += w_dot * DT
		_ang[i] = w
		var h: Vector3 = w * HALF_DT
		_rot[i] = (q * Quaternion(h.x, h.y, h.z, 1.0)).normalized()


## Assist-like controller: velocity hold towards the waypoint and face
## assist, both as thruster commands clamped to the ship's limits.
func _assist(
	i: int, q: Quaternion, p: Vector3, v: Vector3, w: Vector3, inertia: Vector3, mass: float
) -> void:
	var to_wp: Vector3 = _waypoint[i] - p
	var dist: float = to_wp.length()
	if dist < WAYPOINT_REACHED:
		_waypoint[i] = _rand_in_arena()
		to_wp = _waypoint[i] - p
		dist = to_wp.length()
	var dir: Vector3 = to_wp / dist
	var desired: Vector3 = dir * minf(MAX_SPEED, dist * 0.25)
	var q_inv: Quaternion = q.inverse()
	var max_f: Vector3 = _max_thrust[i]
	_thrust[i] = ((q_inv * (desired - v)) * (mass / ASSIST_TAU)).clamp(-max_f, max_f)
	var turn: Vector3 = Vector3.FORWARD.cross(q_inv * dir) * TURN_GAIN
	turn = turn.clamp(
		Vector3(-MAX_TURN, -MAX_TURN, -MAX_TURN), Vector3(MAX_TURN, MAX_TURN, MAX_TURN)
	)
	var max_t: Vector3 = _max_torque[i]
	_torque[i] = ((turn - w) * inertia / ASSIST_TAU).clamp(-max_t, max_t)


## Only the site's low 4 bits survive the shift (bits 60-63), so the narrow
## phases also compare sites.
func _cell_key(site: int, ix: int, iy: int, iz: int) -> int:
	return (((site << 20) | (ix + KEY_OFF)) << 20 | (iy + KEY_OFF)) << 20 | (iz + KEY_OFF)


## Uniform grid broadphase, rebuilt each tick; cells list ship ids in order.
func _build_grid() -> void:
	_cells.clear()
	for i in _n_ships:
		var p: Vector3 = _pos[i]
		var key := _cell_key(
			_site[i], floori(p.x * INV_CELL), floori(p.y * INV_CELL), floori(p.z * INV_CELL)
		)
		var cell: Array = _cells.get(key, [])
		if cell.is_empty():
			_cells[key] = cell
		cell.append(i)


## Ship pairs within the proximity distance (warning) or touching (contact).
func _ship_pairs() -> void:
	var reach: float = 2.0 * SHIP_RADIUS + PROXIMITY
	var warn2: float = reach * reach
	var touch2: float = 4.0 * SHIP_RADIUS * SHIP_RADIUS
	var pad := Vector3(reach, reach, reach)
	for i in _n_ships:
		var p: Vector3 = _pos[i]
		var site: int = _site[i]
		# Only the cells the proximity sphere overlaps (about 10 of 27).
		var lo: Vector3 = (p - pad) * INV_CELL
		var hi: Vector3 = (p + pad) * INV_CELL
		for ix in range(floori(lo.x), floori(hi.x) + 1):
			for iy in range(floori(lo.y), floori(hi.y) + 1):
				for iz in range(floori(lo.z), floori(hi.z) + 1):
					var cell: Array = _cells.get(_cell_key(site, ix, iy, iz), EMPTY)
					for j: int in cell:
						if j <= i or _site[j] != site:
							continue
						var d2: float = p.distance_squared_to(_pos[j])
						if d2 < touch2:
							_event(EV_CONTACT, i, j)
							total_contacts += 1
						elif d2 < warn2:
							_event(EV_PROXIMITY, i, j)


## Moves projectiles and sweeps each segment against ship spheres, using
## motion relative to each candidate ship over the tick (FT-SIM-009).
func _step_projectiles() -> void:
	var reach: float = SHIP_RADIUS + PROJ_RADIUS
	var reach2: float = reach * reach
	var pad := Vector3(reach + 5.0, reach + 5.0, reach + 5.0)
	for k in _n_proj:
		if _p_ttl[k] <= 0:
			if benchmark:
				_fire(k)
			continue
		var p0: Vector3 = _p_pos[k]
		var pv: Vector3 = _p_vel[k]
		var p1: Vector3 = p0 + pv * DT
		_p_pos[k] = p1
		_p_ttl[k] -= 1
		var lo: Vector3 = (p0.min(p1) - pad) * INV_CELL
		var hi: Vector3 = (p0.max(p1) + pad) * INV_CELL
		var site: int = _p_site[k]
		var best: int = -1
		var best_t: float = 2.0
		for ix in range(floori(lo.x), floori(hi.x) + 1):
			for iy in range(floori(lo.y), floori(hi.y) + 1):
				for iz in range(floori(lo.z), floori(hi.z) + 1):
					var cell: Array = _cells.get(_cell_key(site, ix, iy, iz), EMPTY)
					for s: int in cell:
						if _site[s] != site:
							continue
						var s0: Vector3 = _pos_old[s]
						var rel0: Vector3 = p0 - s0
						var d: Vector3 = (p1 - p0) - (_pos[s] - s0)
						var dd: float = d.length_squared()
						var t: float = 0.0
						if dd > 0.0:
							t = clampf(-rel0.dot(d) / dd, 0.0, 1.0)
						if (rel0 + d * t).length_squared() <= reach2 and t < best_t:
							best_t = t
							best = s
		if best >= 0:
			_event(EV_HIT, k, best)
			total_hits += 1
			_p_ttl[k] = 0
			if benchmark:
				_fire(k)


## Fires projectile k from a random ship at another, with first-order lead.
func _fire(k: int) -> void:
	var shooter: int = _rng.randi_range(0, _n_ships - 1)
	var target: int = (shooter + _rng.randi_range(1, _n_ships - 1)) % _n_ships
	var sp: Vector3 = _pos[shooter]
	var sv: Vector3 = _vel[shooter]
	var rel: Vector3 = _pos[target] - sp
	var lead: float = rel.length() / PROJ_SPEED
	var aim: Vector3 = rel + (_vel[target] - sv) * lead
	var spread := Vector3(_rng.randf() - 0.5, _rng.randf() - 0.5, _rng.randf() - 0.5) * 0.004
	var dir: Vector3 = (aim.normalized() + spread).normalized()
	_p_site[k] = _site[shooter]
	_p_pos[k] = sp + dir * (SHIP_RADIUS + 2.0)
	_p_vel[k] = sv + dir * PROJ_SPEED
	_p_ttl[k] = PROJ_TTL


func _event(kind: int, a: int, b: int) -> void:
	events.append(tick)
	events.append(kind)
	events.append(a)
	events.append(b)


func _rand_in_arena() -> Vector3:
	return Vector3(
		(_rng.randf() * 2.0 - 1.0) * ARENA,
		(_rng.randf() * 2.0 - 1.0) * ARENA,
		(_rng.randf() * 2.0 - 1.0) * ARENA
	)
