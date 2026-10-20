class_name S9Radar
extends RefCounted
## Contact section: position and velocity of every ship a faction knows, for
## the disc radar, the Relay map and the callsign rail (one per faction, shared
## by every view of that faction, FT-NET-010). Each contact is dead reckoned
## from its last sent state; the server sends a contact again only when the
## extrapolated position is off by more than the tolerance, with the position
## as a residual against the extrapolation.
##
## The model is what every client in the stream holds:
## id -> [Vector3i position, Vector3i velocity, int tick of that state].
## Deltas chain on the previous snapshot (TCP keeps order; a client that
## misses one gets a full snapshot instead, FT-NET-037).

const KIND: int = 2
## Ticks after which a contact is refreshed anyway (10 s), which keeps the
## integer prediction inside int32 (S9Codec.predict).
const MAX_AGE: int = 600

var tol_units: int = 8
var model: Dictionary = {}
var records_sent: int = 0


func _init(pos_tol_m: float = 0.5) -> void:
	tol_units = maxi(1, roundi(pos_tol_m * S9Codec.POS_Q))


## Advances the model to `tick` for the contacts in `known` (ascending ship
## ids) and returns the delta: u16 n, n records (S9Codec.put_kin), u16 g, g ids.
func update(world: S9World, known: PackedInt32Array, tick: int) -> PackedByteArray:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.put_u16(0)
	var n: int = 0
	var seen: Dictionary = {}
	for id: int in known:
		seen[id] = true
		var p: Vector3i = S9Codec.quant_pos(world.ship_pos(id))
		var v: Vector3i = S9Codec.quant_vel(world.ship_vel(id))
		var entry: Array = model.get(id, [])
		if entry.is_empty():
			S9Codec.put_kin(buf, id, p, v, p, v, true)
		else:
			var old_v: Vector3i = entry[1]
			var dt: int = tick - int(entry[2])
			var pred: Vector3i = S9Codec.predict(entry[0], old_v, dt)
			if S9Codec.max_abs(p - pred) <= tol_units and dt < MAX_AGE:
				continue
			S9Codec.put_kin(buf, id, p, v, pred, old_v, false)
		model[id] = [p, v, tick]
		n += 1
	var gone: PackedInt32Array = PackedInt32Array()
	if model.size() > seen.size():
		for id: int in model.keys():
			if not seen.has(id):
				gone.append(id)
	put_gone(buf, gone, model)
	records_sent += n
	buf.seek(0)
	buf.put_u16(n)
	return buf.data_array


## The model as a full section: u16 n, n absolute records each with a u16 age.
func full(tick: int) -> PackedByteArray:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.put_u16(model.size())
	for id: int in model:
		var entry: Array = model[id]
		S9Codec.put_kin(buf, id, entry[0], entry[1], entry[0], entry[1], true)
		buf.put_u16(tick - int(entry[2]))
	return buf.data_array


## Client side: applies a section to a model of the same shape.
static func apply(into: Dictionary, buf: StreamPeerBuffer, is_full: bool, tick: int) -> void:
	if is_full:
		into.clear()
	var n: int = buf.get_u16()
	for i: int in range(n):
		var rec: Array = S9Codec.get_kin(buf, into, tick)
		var at: int = tick - buf.get_u16() if is_full else tick
		into[rec[0]] = [rec[1], rec[2], at]
	if not is_full:
		get_gone(buf, into)


static func put_gone(buf: StreamPeerBuffer, gone: PackedInt32Array, from: Dictionary) -> void:
	buf.put_u16(gone.size())
	for id: int in gone:
		buf.put_u16(id)
		from.erase(id)


static func get_gone(buf: StreamPeerBuffer, from: Dictionary) -> void:
	var g: int = buf.get_u16()
	for i: int in range(g):
		from.erase(buf.get_u16())
