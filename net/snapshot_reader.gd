class_name SnapshotReader
extends RefCounted
## The client's side of the snapshot format (F4, R14-1): the message header and the decoders
## of the sections that are not NetBlock blocks. SnapshotWriter and the sections in
## net/sections/ write what this reads; they are the server's, and the clients name only this
## class, so a client never compiles the server's builders or the sim (D103). The format is
## SnapshotWriter's: u8 type, u8 flags (bit 0 full), u32 seq, u32 tick, u8 n, then n sections
## of u8 kind, length (u16, or LONG_SECTION then a u32), payload.

const HEADER_BYTES: int = 11
const FLAG_FULL: int = 1
## Section length escape: a u32 length follows.
const LONG_SECTION: int = 0xFFFF
## Info flags of a contact (CONTACTS): identified, of the reader's own faction.
const FLAG_IDENTIFIED: int = 1
const FLAG_OWN: int = 2


## Reads a section length written by SnapshotWriter.put_length().
static func get_length(buf: StreamPeerBuffer) -> int:
	var size: int = buf.get_u16()
	return buf.get_u32() if size == LONG_SECTION else size


## [seq, full, tick] of a snapshot message without decoding its sections.
static func peek(data: PackedByteArray) -> Array:
	return [data.decode_u32(2), data[1] & FLAG_FULL == FLAG_FULL, data.decode_u32(6)]


## KIN: {"pos" (Vector3i units), "vel" (Vector3i), "rot" (Quaternion), "ang" (Vector3i)}.
static func read_kin(buf: StreamPeerBuffer) -> Dictionary:
	return {
		"pos": NetCodec.get3_32(buf),
		"vel": NetCodec.get3_16(buf),
		"rot": NetCodec.unpack_quat(buf.get_u32()),
		"ang": NetCodec.get3_8(buf),
	}


## CONTACTS: applies a section to {"model": {...}, "info": {...}} (ContactsSection's shapes);
## false on a corrupt stream (a residual for an unknown id).
static func apply_contacts(
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


## Reads a gone list, erases the ids from `from` and returns them.
static func get_gone(buf: StreamPeerBuffer, from: Dictionary) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for i: int in range(buf.get_u16()):
		var id: int = buf.get_u16()
		from.erase(id)
		out.append(id)
	return out


## SITES: [{"id", "name_key", "kind" (StringName), "dockable", "radius" (m), "pos" (Vector3,
## m in the cube)}].
static func read_sites(buf: StreamPeerBuffer) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in range(buf.get_u8()):
		var id: int = buf.get_u16()
		var kind: int = buf.get_u8()
		var dockable: bool = buf.get_u8() != 0
		var radius: float = buf.get_float()
		var pos: Vector3 = NetCodec.pos_of(NetCodec.get3_32(buf))
		var name_key: String = buf.get_data(buf.get_u8())[1].get_string_from_utf8()
		var row: Dictionary = {
			"id": id,
			"name_key": name_key,
			"kind": SiteDef.KINDS[clampi(kind, 0, SiteDef.KINDS.size() - 1)],
			"dockable": dockable,
			"radius": radius,
			"pos": pos,
		}
		out.append(row)
	return out


## NEAR: id -> [orientation bits, angular velocity, tick].
static func apply_near(into: Dictionary, buf: StreamPeerBuffer, is_full: bool, tick: int) -> void:
	if is_full:
		into.clear()
	for i: int in range(buf.get_u16()):
		var id: int = buf.get_u16()
		var bits: int = buf.get_u32()
		var w: Vector3i = NetCodec.get3_8(buf)
		into[id] = [bits, w, tick - buf.get_u16()]
	if not is_full:
		get_gone(buf, into)


## PROJECTILES: id -> [Vector3i position, Vector3i velocity, int tick].
static func apply_projectiles(
	into: Dictionary, buf: StreamPeerBuffer, is_full: bool, tick: int
) -> void:
	if is_full:
		into.clear()
	for i: int in range(buf.get_u16()):
		var id: int = buf.get_u16()
		var p: Vector3i = NetCodec.get3_32(buf)
		var v: Vector3i = NetCodec.get3_16(buf)
		var at: int = tick - buf.get_u16() if is_full else tick
		into[id] = [p, v, at]
	if not is_full:
		get_gone(buf, into)


## OWNERSHIP: the decoded table, or {} if malformed.
static func read_ownership(part: PackedByteArray) -> Dictionary:
	var v: Variant = bytes_to_var(part)
	if not v is Dictionary:
		return {}
	var d: Dictionary = v
	if not (d.get("claims") is Dictionary and d.get("writers") is Dictionary):
		return {}
	return d
