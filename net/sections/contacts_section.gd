class_name ContactsSection
extends SnapshotSection
## Contacts of one faction (Section.CONTACTS), shared by every view of its ships: the
## disc radar, the Relay map and the callsign rail (FT-NET-010: only this faction's
## knowledge). Lists the ships the faction detects (KnowledgeSystem.contacts) and its
## own live ships. Positions are dead reckoned (NetCodec.predict): a contact is sent
## again only when the extrapolation is off by more than the tolerance, as a
## minimum-image residual, so crossing a site seam (D124) costs a residual too. A
## contact's info (callsign, identified, own faction) is sent when it changes.
##
## Delta: u16 n kinematic records (NetCodec.put_kin); u16 i info records (u16 id, u8
## flags: bit 0 identified, bit 1 own faction; u8 length + UTF-8 callsign); u16 g, g
## gone ids. Full: u16 n absolute records each with a u16 age in ticks; u16 i info
## records. One site per world (M1), so no site field (provisional: see
## docs/protocol.md, Rates and limits).

const FLAG_IDENTIFIED: int = 1
const FLAG_OWN: int = 2

var tol_units: int = 8
## id -> [Vector3i position, Vector3i velocity, int tick]: what every client holds.
var model: Dictionary = {}
## id -> [int flags, String callsign].
var info: Dictionary = {}
## The ship ids the faction knows at this snapshot (known(); SnapshotBuilder sets them
## before update(), once per faction).
var ids: PackedInt32Array = PackedInt32Array()
var _tick: int = 0
var _p_units: int = 0


func _init(faction: int, pos_tol_m: float = 0.5) -> void:
	super(StationViews.Section.CONTACTS, faction)
	tol_units = maxi(1, roundi(pos_tol_m * NetCodec.POS_Q))


## The ship ids the faction sees, ascending: detected contacts and its own live ships.
static func known(world: SimWorld, faction: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for id: int in world.ship_count():
		if not world.kin.is_alive(id):
			continue
		if world.faction_of(id) == faction or KnowledgeSystem.is_detected(world, faction, id):
			out.append(id)
	return out


func update(world: SimWorld) -> PackedByteArray:
	_tick = world.tick
	_p_units = NetCodec.period_units(world.kin.period)
	var kin: Kinematics = world.kin
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.put_u16(0)
	var n: int = 0
	var seen: Dictionary = {}
	for id: int in ids:
		seen[id] = true
		var at: PackedFloat64Array = kin.point_at(id, Vector3.ZERO)
		var p: Vector3i = NetCodec.quant_pos(at[0], at[1], at[2], _p_units)
		var v: Vector3i = NetCodec.quant_vel(kin.vel[id])
		var entry: Array = model.get(id, [])
		if entry.is_empty():
			NetCodec.put_kin(buf, id, p, v, p, v, true, _p_units)
		else:
			var dt: int = _tick - int(entry[2])
			var pred: Vector3i = NetCodec.predict(entry[0], entry[1], dt, _p_units)
			if (
				NetCodec.max_abs(NetCodec.diff(p, pred, _p_units)) <= tol_units
				and dt < NetCodec.MAX_AGE
			):
				continue
			NetCodec.put_kin(buf, id, p, v, pred, entry[1], false, _p_units)
		model[id] = [p, v, _tick]
		n += 1
	var info_pos: int = buf.get_position()
	buf.put_u16(0)
	var ni: int = 0
	for id: int in ids:
		var flags: int = FLAG_OWN if world.faction_of(id) == owner else 0
		if KnowledgeSystem.is_identified(world, owner, id):
			flags |= FLAG_IDENTIFIED
		var now: Array = [flags, KnowledgeSystem.callsign(world, owner, id)]
		if info.get(id, []) == now:
			continue
		info[id] = now
		_put_info(buf, id, now)
		ni += 1
	var gone: PackedInt32Array = PackedInt32Array()
	for id: int in model.keys():
		if not seen.has(id):
			gone.append(id)
	put_gone(buf, gone, model)
	for id: int in gone:
		info.erase(id)
	var end: int = buf.get_position()
	buf.seek(0)
	buf.put_u16(n)
	buf.seek(info_pos)
	buf.put_u16(ni)
	buf.seek(end)
	return buf.data_array


func full() -> PackedByteArray:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.put_u16(model.size())
	for id: int in model:
		var entry: Array = model[id]
		NetCodec.put_kin(buf, id, entry[0], entry[1], entry[0], entry[1], true, _p_units)
		buf.put_u16(_tick - int(entry[2]))
	buf.put_u16(info.size())
	for id: int in info:
		_put_info(buf, id, info[id])
	return buf.data_array


## Client side: applies a section to {"model": {...}, "info": {...}} of the same
## shapes; false on a corrupt stream (a residual for an unknown id).
static func apply(
	into: Dictionary, buf: StreamPeerBuffer, is_full: bool, tick: int, p_units: int
) -> bool:
	var m: Dictionary = into.get_or_add("model", {})
	var inf: Dictionary = into.get_or_add("info", {})
	if is_full:
		m.clear()
		inf.clear()
	for i: int in range(buf.get_u16()):
		var rec: Array = NetCodec.get_kin(buf, m, tick, p_units)
		if rec.is_empty():
			return false
		var at: int = tick - buf.get_u16() if is_full else tick
		m[rec[0]] = [rec[1], rec[2], at]
	for i: int in range(buf.get_u16()):
		var id: int = buf.get_u16()
		var flags: int = buf.get_u8()
		inf[id] = [flags, buf.get_data(buf.get_u8())[1].get_string_from_utf8()]
	if not is_full:
		for id: int in get_gone(buf, m):
			inf.erase(id)
	return true


static func put_gone(buf: StreamPeerBuffer, gone: PackedInt32Array, from: Dictionary) -> void:
	buf.put_u16(gone.size())
	for id: int in gone:
		buf.put_u16(id)
		from.erase(id)


## Reads a gone list, erases the ids from `from` and returns them.
static func get_gone(buf: StreamPeerBuffer, from: Dictionary) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for i: int in range(buf.get_u16()):
		var id: int = buf.get_u16()
		from.erase(id)
		out.append(id)
	return out


static func _put_info(buf: StreamPeerBuffer, id: int, value: Array) -> void:
	var name: PackedByteArray = (value[1] as String).to_utf8_buffer().slice(0, 255)
	buf.put_u16(id)
	buf.put_u8(value[0])
	buf.put_u8(name.size())
	buf.put_data(name)
