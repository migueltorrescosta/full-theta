class_name ProjectilesSection
extends SnapshotSection
## Live projectiles within range_m of one ship (Section.PROJECTILES, promoted from
## S9Proj), for the views that draw tracers. Projectiles fly straight, so each is sent
## once, when it enters the range, as a position and velocity at the snapshot's tick;
## clients extrapolate it (NetCodec.predict with PROJ_PRED_DEN) and wrap it. Ids that
## leave the range or die are listed as gone.
##
## ProjectileTable rows have no stable id, so the section names each projectile by its
## shooter and expiry tick (tick + ttl, constant over its flight), plus its order among
## rows with the same pair, packed in one int (_key), and maps that to a u16 net id.
##
## Delta: u16 n records (u16 id, 3 x s32 position, 3 x s16 velocity in 1/8 m/s); u16
## g, g gone ids. Full: the records each with a u16 age.

const DEFAULT_RANGE_M: float = 3000.0

var range_m: float = DEFAULT_RANGE_M
## Net id -> [Vector3i position, Vector3i velocity, int tick] as sent.
var model: Dictionary = {}
var _ids: Dictionary = {}
var _next_id: int = 0
var _tick: int = 0


func _init(ship: int, proj_range_m: float = DEFAULT_RANGE_M) -> void:
	super(StationViews.Section.PROJECTILES, ship)
	range_m = proj_range_m


func update(world: SimWorld) -> PackedByteArray:
	_tick = world.tick
	var p_units: int = NetCodec.period_units(world.kin.period)
	var kin: Kinematics = world.kin
	var proj: ProjectileTable = world.projectiles
	var at: PackedFloat64Array = kin.point_at(owner, Vector3.ZERO)
	var own: Vector3i = NetCodec.quant_pos(at[0], at[1], at[2], p_units)
	var r2: float = range_m * range_m
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.put_u16(0)
	var n: int = 0
	var seen: Dictionary = {}
	var ordinal: Dictionary = {}
	for k: int in proj.size():
		var pair: int = _key(proj.ship_ids[k], _tick + proj.ttl[k], 0)
		var nth: int = ordinal.get(pair, 0)
		ordinal[pair] = nth + 1
		if proj.site[k] != kin.site[owner]:
			continue
		var rel: Vector3 = proj.relative_start(k, kin, owner, 0.0)
		if rel.length_squared() > r2:
			continue
		var key: int = pair + nth
		var id: int = _ids.get(key, -1)
		if id >= 0:
			seen[id] = key
			continue
		id = _new_id()
		_ids[key] = id
		seen[id] = key
		var rel_u: Vector3i = Vector3i((rel * NetCodec.POS_Q).round())
		var p: Vector3i = NetCodec.wrap_units(own + rel_u, p_units)
		var v: Vector3i = NetCodec.quant_proj_vel(proj.vel[k])
		model[id] = [p, v, _tick]
		_put_rec(buf, id, p, v)
		n += 1
	var gone: PackedInt32Array = PackedInt32Array()
	for id: int in model.keys():
		if not seen.has(id):
			gone.append(id)
	for key: int in _ids.keys():
		if not seen.has(_ids[key]):
			_ids.erase(key)
	ContactsSection.put_gone(buf, gone, model)
	var end: int = buf.get_position()
	buf.seek(0)
	buf.put_u16(n)
	buf.seek(end)
	return buf.data_array


func full() -> PackedByteArray:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.put_u16(model.size())
	for id: int in model:
		var entry: Array = model[id]
		_put_rec(buf, id, entry[0], entry[1])
		buf.put_u16(_tick - int(entry[2]))
	return buf.data_array


## Client side: id -> [Vector3i position, Vector3i velocity, int tick].
static func apply(into: Dictionary, buf: StreamPeerBuffer, is_full: bool, tick: int) -> void:
	if is_full:
		into.clear()
	for i: int in range(buf.get_u16()):
		var id: int = buf.get_u16()
		var p: Vector3i = NetCodec.get3_32(buf)
		var v: Vector3i = NetCodec.get3_16(buf)
		var at: int = tick - buf.get_u16() if is_full else tick
		into[id] = [p, v, at]
	if not is_full:
		ContactsSection.get_gone(buf, into)


## Shooter (15 bits), expiry tick (32 bits) and order among same pairs (16 bits).
static func _key(shooter: int, expiry: int, nth: int) -> int:
	return shooter << 48 | (expiry & 0xFFFFFFFF) << 16 | nth


func _new_id() -> int:
	while model.has(_next_id):
		_next_id = (_next_id + 1) & 0xFFFF
	var id: int = _next_id
	_next_id = (_next_id + 1) & 0xFFFF
	return id


static func _put_rec(buf: StreamPeerBuffer, id: int, p: Vector3i, v: Vector3i) -> void:
	buf.put_u16(id)
	NetCodec.put3_32(buf, p)
	NetCodec.put3_16(buf, v)
