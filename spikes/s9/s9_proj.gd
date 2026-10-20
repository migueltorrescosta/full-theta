class_name S9Proj
extends RefCounted
## Projectile section of one ship: live projectiles within `range_m`, for the
## views that draw tracers. Projectiles fly straight, so each is sent once,
## when it enters the range or its id is refired, as a position and velocity
## at the snapshot's tick; clients extrapolate it. Ids that leave the range or
## die are listed as gone.
##
## Model: id -> generation (S9World.proj_gen) the clients hold.

const KIND: int = 4

var ship: int = 0
var range_m: float = 1000.0
var model: Dictionary = {}
var records_sent: int = 0
## Full records need the state, so keep the last sent one per id.
var _sent: Dictionary = {}


func _init(own_ship: int, proj_range_m: float = 1000.0) -> void:
	ship = own_ship
	range_m = proj_range_m


## `near` lists the live projectile ids within range of this ship, ascending.
## Delta: u16 n, n records (u16 id, 3 x s32 position, 3 x s16 velocity),
## u16 g, g gone ids.
func update(world: S9World, near: PackedInt32Array, tick: int) -> PackedByteArray:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.put_u16(0)
	var n: int = 0
	var seen: Dictionary = {}
	for id: int in near:
		seen[id] = true
		var gen: int = world.proj_gen[id]
		if model.get(id, -1) == gen:
			continue
		model[id] = gen
		var p: Vector3i = S9Codec.quant_pos(world.proj_pos(id))
		var v: Vector3i = Vector3i((world.proj_vel(id) * S9Codec.PROJ_VEL_Q).round())
		_sent[id] = [p, v, tick]
		_put_rec(buf, id, p, v)
		n += 1
	var gone: PackedInt32Array = PackedInt32Array()
	if model.size() > seen.size():
		for id: int in model.keys():
			if not seen.has(id):
				gone.append(id)
				_sent.erase(id)
	S9Radar.put_gone(buf, gone, model)
	records_sent += n
	buf.seek(0)
	buf.put_u16(n)
	return buf.data_array


## Full: u16 n, n records each with a u16 age in ticks.
func full(tick: int) -> PackedByteArray:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.put_u16(_sent.size())
	for id: int in _sent:
		var entry: Array = _sent[id]
		_put_rec(buf, id, entry[0], entry[1])
		buf.put_u16(tick - int(entry[2]))
	return buf.data_array


## Client side: id -> [Vector3i position, Vector3i velocity, int tick].
static func apply(into: Dictionary, buf: StreamPeerBuffer, is_full: bool, tick: int) -> void:
	if is_full:
		into.clear()
	var n: int = buf.get_u16()
	for i: int in range(n):
		var id: int = buf.get_u16()
		var p: Vector3i = Vector3i(buf.get_32(), buf.get_32(), buf.get_32())
		var v: Vector3i = Vector3i(buf.get_16(), buf.get_16(), buf.get_16())
		var at: int = tick - buf.get_u16() if is_full else tick
		into[id] = [p, v, at]
	if not is_full:
		S9Radar.get_gone(buf, into)


## Live projectile ids within `range_m` of each of `ships`, in one pass.
static func near_lists(
	world: S9World, ships: PackedInt32Array, range_m: float
) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	var centres: PackedVector3Array = PackedVector3Array()
	for s: int in ships:
		out.append(PackedInt32Array())
		centres.append(world.ship_pos(s))
	var r2: float = range_m * range_m
	var positions: PackedVector3Array = world.proj_positions()
	for j: int in range(ships.size()):
		var c: Vector3 = centres[j]
		var ids: PackedInt32Array = PackedInt32Array()
		var k: int = 0
		for p: Vector3 in positions:
			if p.distance_squared_to(c) <= r2 and world.proj_live(k):
				ids.append(k)
			k += 1
		out[j] = ids
	return out


static func _put_rec(buf: StreamPeerBuffer, id: int, p: Vector3i, v: Vector3i) -> void:
	buf.put_u16(id)
	buf.put_32(p.x)
	buf.put_32(p.y)
	buf.put_32(p.z)
	buf.put_16(v.x)
	buf.put_16(v.y)
	buf.put_16(v.z)
