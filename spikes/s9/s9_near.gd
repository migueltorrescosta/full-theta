class_name S9Near
extends RefCounted
## Near section of one ship: orientation and angular velocity of the contacts
## within `range_m`, for the views that draw ship models (Helm cockpit,
## Weapons turret, main screen). Positions come from the faction's S9Radar
## section. Records come from the faction's S9Orient model: a contact is sent
## when it enters the range or the shared model refreshes it.
##
## Client model: id -> [int packed quaternion, Vector3i angular velocity, tick],
## equal to the S9Orient model restricted to the members.

const KIND: int = 3

var ship: int = 0
var range_m: float = 2000.0
## Ids of the contacts the clients hold.
var members: Dictionary = {}
var records_sent: int = 0


func _init(own_ship: int, near_range_m: float = 2000.0) -> void:
	ship = own_ship
	range_m = near_range_m


## Contacts in `known` within range of this ship, as a set.
func in_range(world: S9World, known: PackedInt32Array) -> Dictionary:
	var out: Dictionary = {}
	var positions: PackedVector3Array = world.ship_positions()
	var own: Vector3 = positions[ship]
	var site: int = world.ship_site(ship)
	var r2: float = range_m * range_m
	for id: int in known:
		if id != ship and own.distance_squared_to(positions[id]) <= r2:
			if world.ship_site(id) == site:
				out[id] = true
	return out


## Delta: u16 n, n records (u16 id, u32 quaternion, 3 x s8 angular velocity),
## u16 g, g ids that left the range.
func update(now_in: Dictionary, orient: S9Orient) -> PackedByteArray:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.put_u16(0)
	var n: int = 0
	for id: int in now_in:
		if members.has(id) and not orient.refreshed.has(id):
			continue
		members[id] = true
		var entry: Array = orient.model[id]
		_put_rec(buf, id, entry[0], entry[1])
		n += 1
	var gone: PackedInt32Array = PackedInt32Array()
	if members.size() > now_in.size():
		for id: int in members.keys():
			if not now_in.has(id):
				gone.append(id)
	S9Radar.put_gone(buf, gone, members)
	records_sent += n
	buf.seek(0)
	buf.put_u16(n)
	return buf.data_array


func full(orient: S9Orient, tick: int) -> PackedByteArray:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.put_u16(members.size())
	for id: int in members:
		var entry: Array = orient.model[id]
		_put_rec(buf, id, entry[0], entry[1])
		buf.put_u16(tick - int(entry[2]))
	return buf.data_array


## The clients' model, for tests.
func client_model(orient: S9Orient) -> Dictionary:
	var out: Dictionary = {}
	for id: int in members:
		out[id] = orient.model[id]
	return out


static func apply(into: Dictionary, buf: StreamPeerBuffer, is_full: bool, tick: int) -> void:
	if is_full:
		into.clear()
	var n: int = buf.get_u16()
	for i: int in range(n):
		var id: int = buf.get_u16()
		var bits: int = buf.get_u32()
		var w: Vector3i = Vector3i(buf.get_8(), buf.get_8(), buf.get_8())
		var at: int = tick - buf.get_u16() if is_full else tick
		into[id] = [bits, w, at]
	if not is_full:
		S9Radar.get_gone(buf, into)


static func _put_rec(buf: StreamPeerBuffer, id: int, bits: int, w: Vector3i) -> void:
	buf.put_u16(id)
	buf.put_u32(bits)
	buf.put_8(w.x)
	buf.put_8(w.y)
	buf.put_8(w.z)
