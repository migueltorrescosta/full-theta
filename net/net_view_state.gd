class_name NetViewState
extends RefCounted
## Client-side state of one view, rebuilt from snapshot messages (SnapshotBuilder):
## full snapshots replace it, deltas must follow the previous snapshot. Clients render
## this and never simulate (FT-ARC-005). Integer models stay as the codec left them so
## dead reckoning matches the server bit for bit; the helpers convert to metres.

## Site period in position units (from Welcome.period), for wrap-aware decoding.
var p_units: int = 0
var seq: int = -1
var tick: int = 0
var full_count: int = 0
## KinSection.read() of the own ship, or {}.
var kin: Dictionary = {}
## Section kind -> decoded block (StationViews.BLOCKS fields).
var blocks: Dictionary = {}
## {"model": id -> [pos, vel, tick], "info": id -> [flags, callsign]}.
var contacts: Dictionary = {}
## The named sites the faction knows (SitesSection.read), in site id order.
var sites: Array[Dictionary] = []
## id -> [packed quaternion, angular velocity, tick].
var near: Dictionary = {}
## id -> [pos, vel, tick].
var projectiles: Dictionary = {}
## OWNERSHIP of this view: {"claims": {item: [session, name]}, "writers": {control:
## [session, name]}}.
var ownership: Dictionary = {}
## Sections present in the last full snapshot.
var kinds: Array[int] = []
## Deltas that couldn't be applied (no base, a gap, a corrupt record).
var rejected: int = 0
## A snapshot couldn't be applied: deltas are refused until the next full snapshot,
## which NetClient asks for (Ack snap -1).
var need_full: bool = false


func _init(period_units: int = 0) -> void:
	p_units = period_units


## Applies one snapshot message; false if it couldn't be applied: the view then needs
## a full snapshot (need_full) and refuses deltas until one arrives.
func apply(data: PackedByteArray) -> bool:
	if data.size() < SnapshotBuilder.HEADER_BYTES or data[0] != NetProtocol.Type.SNAPSHOT:
		return _reject()
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.data_array = data
	buf.seek(1)
	var is_full: bool = buf.get_u8() & SnapshotBuilder.FLAG_FULL != 0
	var new_seq: int = buf.get_u32()
	if not is_full and (need_full or seq < 0 or new_seq != seq + 1):
		return _reject()
	var new_tick: int = buf.get_u32()
	var n: int = buf.get_u8()
	if is_full:
		kin = {}
		blocks = {}
		contacts = {}
		sites = []
		near = {}
		projectiles = {}
		ownership = {}
		kinds = []
		full_count += 1
	for i: int in range(n):
		var kind: int = buf.get_u8()
		var size: int = SnapshotBuilder.get_length(buf)
		var start: int = buf.get_position()
		if start + size > data.size():
			return _reject()
		if not _apply_section(kind, buf, data.slice(start, start + size), is_full, new_tick):
			return _reject()
		if is_full:
			kinds.append(kind)
		buf.seek(start + size)
	seq = new_seq
	tick = new_tick
	need_full = false
	return true


## Name of the player holding a claim item of this view's stations ("" if free).
func claimer(item: String) -> String:
	var claims: Dictionary = ownership.get("claims", {})
	return claims[item][1] if claims.has(item) else ""


## Name of the last writer of a ship-wide control of this view's stations ("" if none).
func last_writer(control: String) -> String:
	var writers: Dictionary = ownership.get("writers", {})
	return writers[control][1] if writers.has(control) else ""


## Own ship position (m, wrapped), or ZERO before the first snapshot.
func own_position() -> Vector3:
	return NetCodec.pos_of(kin.get("pos", Vector3i.ZERO))


## A contact's dead-reckoned position (m) at the current tick, or ZERO if unknown.
func contact_position(id: int) -> Vector3:
	var model: Dictionary = contacts.get("model", {})
	if not model.has(id):
		return Vector3.ZERO
	var e: Array = model[id]
	return NetCodec.pos_of(NetCodec.predict(e[0], e[1], tick - int(e[2]), p_units))


## Callsign of a contact ("" if unknown).
func callsign(id: int) -> String:
	var info: Dictionary = contacts.get("info", {})
	return info[id][1] if info.has(id) else ""


func _reject() -> bool:
	rejected += 1
	need_full = true
	return false


func _apply_section(
	kind: int, buf: StreamPeerBuffer, part: PackedByteArray, is_full: bool, at: int
) -> bool:
	match kind:
		StationViews.Section.KIN:
			kin = KinSection.read(buf)
		StationViews.Section.CONTACTS:
			return ContactsSection.apply(contacts, buf, is_full, at, p_units)
		StationViews.Section.SITES:
			sites = SitesSection.read(buf)
		StationViews.Section.NEAR:
			NearSection.apply(near, buf, is_full, at)
		StationViews.Section.PROJECTILES:
			ProjectilesSection.apply(projectiles, buf, is_full, at)
		StationViews.Section.OWNERSHIP:
			ownership = OwnershipSection.read(part)
			return not ownership.is_empty()
		_:
			if not StationViews.BLOCKS.has(kind):
				return false
			blocks[kind] = NetBlock.decode(StationViews.BLOCKS[kind], part)
	return true
