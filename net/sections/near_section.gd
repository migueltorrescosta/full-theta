class_name NearSection
extends SnapshotSection
## Orientations of the contacts within range_m of one ship (Section.NEAR, promoted
## from S9Near), for the views that draw ship models. Positions come from the CONTACTS
## section; records come from the faction's OrientModel: a contact is sent when it
## enters the range or the shared model refreshes it.
##
## Delta: u16 n records (u16 id, u32 quaternion, 3 x s8 angular velocity, u16 age in
## ticks: a contact entering the range gets the shared model's record, which may be
## older than the snapshot); u16 g, g ids that left the range. Full: the records.

const DEFAULT_RANGE_M: float = 2000.0

var range_m: float = DEFAULT_RANGE_M
var orient: OrientModel
## Ids of the contacts the clients hold.
var members: Dictionary = {}
var _tick: int = 0


func _init(ship: int, model: OrientModel, near_range_m: float = DEFAULT_RANGE_M) -> void:
	super(StationViews.Section.NEAR, ship)
	orient = model
	range_m = near_range_m


## Ids in `known` within range of the owner ship (minimum image), as a set.
func in_range(world: SimWorld, known: PackedInt32Array) -> Dictionary:
	var out: Dictionary = {}
	var r2: float = range_m * range_m
	for id: int in known:
		if id != owner and world.kin.can_reach(owner, id):
			if world.kin.relative(owner, id).length_squared() <= r2:
				out[id] = true
	return out


## Call after the faction's OrientModel has been updated with now_in.
func update_members(world: SimWorld, now_in: Dictionary) -> PackedByteArray:
	_tick = world.tick
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.put_u16(0)
	var n: int = 0
	for id: int in now_in:
		if members.has(id) and not orient.refreshed.has(id):
			continue
		members[id] = true
		_put_rec(buf, id, orient.model[id])
		n += 1
	var gone: PackedInt32Array = PackedInt32Array()
	for id: int in members.keys():
		if not now_in.has(id):
			gone.append(id)
	ContactsSection.put_gone(buf, gone, members)
	var end: int = buf.get_position()
	buf.seek(0)
	buf.put_u16(n)
	buf.seek(end)
	return buf.data_array


func full() -> PackedByteArray:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.put_u16(members.size())
	for id: int in members:
		_put_rec(buf, id, orient.model[id])
	return buf.data_array


## The clients' model, for tests: id -> [bits, angular velocity, tick].
func client_model() -> Dictionary:
	var out: Dictionary = {}
	for id: int in members:
		out[id] = orient.model[id]
	return out


static func apply(into: Dictionary, buf: StreamPeerBuffer, is_full: bool, tick: int) -> void:
	if is_full:
		into.clear()
	for i: int in range(buf.get_u16()):
		var id: int = buf.get_u16()
		var bits: int = buf.get_u32()
		var w: Vector3i = NetCodec.get3_8(buf)
		into[id] = [bits, w, tick - buf.get_u16()]
	if not is_full:
		ContactsSection.get_gone(buf, into)


## One record from the model entry [bits, angular velocity, tick].
func _put_rec(buf: StreamPeerBuffer, id: int, entry: Array) -> void:
	buf.put_u16(id)
	buf.put_u32(entry[0])
	NetCodec.put3_8(buf, entry[1])
	buf.put_u16(_tick - int(entry[2]))
