class_name SnapshotBuilder
extends RefCounted
## Builds the per-view snapshots (FT-NET-008, FT-NET-040; promoted from S9Builder) on
## the net thread, from a SimCopy. Once per snapshot it advances every section the
## current view keys need (one per owner: a ship, or a faction for CONTACTS), then
## assembles each view key's message on first request, chunks it once and shares the
## chunks among the clients holding that key. Sections no key needs are dropped; a
## section created later starts from an empty model, and the clients that need it get
## a full snapshot anyway (join, pick change).
##
## Message: u8 type (NetProtocol.Type.SNAPSHOT), u8 flags (bit 0 full), u32 seq, u32
## tick, u8 n, then n sections of u8 kind, length, payload. The length is a u16, or
## 0xFFFF then a u32 for a section of 0xFFFF bytes or more, so no section is ever too
## long to send. A delta omits the sections with nothing to say (unchanged blocks).

const HEADER_BYTES: int = 11
const FLAG_FULL: int = 1
## Section length escape: a u32 length follows.
const LONG_SECTION: int = 0xFFFF

var seq: int = 0
var tick: int = 0
var chunk_size: int = NetChunker.DEFAULT_CHUNK_SIZE
var pos_tol_m: float = 0.5
var rot_tol_deg: float = 1.0
var near_range_m: float = NearSection.DEFAULT_RANGE_M
var proj_range_m: float = ProjectilesSection.DEFAULT_RANGE_M
## Counters since the last take_counts(): snapshot builds, section updates, view-key
## messages assembled (delta and full).
var counts: Dictionary = {}

var _world: SimWorld
## "kind:owner" -> SnapshotSection.
var _sections: Dictionary = {}
## Faction -> OrientModel.
var _orient: Dictionary = {}
## "kind:owner" -> delta bytes of this snapshot.
var _deltas: Dictionary = {}
## "view_key|full" -> chunks of this snapshot.
var _cache: Dictionary = {}
## Ship -> ownership table posted by the main thread (OwnershipSection).
var _ownership: Dictionary = {}
## Faction -> the ship ids it knows (ContactsSection.known), computed once per build.
var _known: Dictionary = {}


func _init() -> void:
	take_counts()


## Advances every section the view keys need to the copied world's tick. Keys naming a
## ship the world doesn't have are skipped.
func build(world: SimWorld, snapshot_seq: int, view_keys: Array) -> void:
	_world = world
	seq = snapshot_seq
	tick = world.tick
	_deltas.clear()
	_cache.clear()
	_known.clear()
	var needed: Dictionary = {}
	var near_ships: Dictionary = {}
	for view_key: String in view_keys:
		var k: Array = StationViews.parse_key(view_key)
		var ship: int = k[0]
		if ship < 0 or ship >= world.ship_count():
			continue
		for kind: int in StationViews.sections_of(k[1]):
			needed[_skey(kind, _owner(kind, ship))] = [kind, _owner(kind, ship)]
			if kind == StationViews.Section.NEAR:
				near_ships[ship] = true
	for skey: String in _sections.keys():
		if not needed.has(skey):
			_sections.erase(skey)
	for skey: String in needed:
		if not _sections.has(skey):
			_sections[skey] = _make(needed[skey][0], needed[skey][1])
	# Near sets first: one orientation model per faction serves all its ships.
	var near_sets: Dictionary = {}
	var unions: Dictionary = {}
	for ship: int in near_ships:
		var f: int = world.faction_of(ship)
		var section: NearSection = _sections[_skey(StationViews.Section.NEAR, ship)]
		near_sets[ship] = section.in_range(world, _known_of(f))
		(unions.get_or_add(f, {}) as Dictionary).merge(near_sets[ship])
	for f: int in unions:
		_orient_of(f).update(world, unions[f])
	for skey: String in _sections:
		var section: SnapshotSection = _sections[skey]
		if section is OwnershipSection:
			(section as OwnershipSection).data = _ownership.get(section.owner, {})
		elif section is ContactsSection:
			(section as ContactsSection).ids = _known_of(section.owner)
		if section is NearSection:
			_deltas[skey] = (section as NearSection).update_members(world, near_sets[section.owner])
		else:
			_deltas[skey] = section.update(world)
	counts["builds"] += 1
	counts["section_updates"] += _sections.size()


## The chunks of a view key's message at the current snapshot, built once and shared.
func chunks(view_key: String, is_full: bool) -> Array[PackedByteArray]:
	var ck: String = "%s|%d" % [view_key, 1 if is_full else 0]
	if _cache.has(ck):
		return _cache[ck]
	var out: Array[PackedByteArray] = NetChunker.split(
		NetChunker.STREAM_SNAPSHOT, seq, message(view_key, is_full), chunk_size
	)
	_cache[ck] = out
	counts["full_messages" if is_full else "delta_messages"] += 1
	return out


## A view key's message at the current snapshot (not cached; chunks() caches).
func message(view_key: String, is_full: bool) -> PackedByteArray:
	var k: Array = StationViews.parse_key(view_key)
	var ship: int = k[0]
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.put_u8(NetProtocol.Type.SNAPSHOT)
	buf.put_u8(FLAG_FULL if is_full else 0)
	buf.put_u32(seq)
	buf.put_u32(tick)
	buf.put_u8(0)
	var n: int = 0
	for kind: int in StationViews.sections_of(k[1]):
		var skey: String = _skey(kind, _owner(kind, ship))
		if not _sections.has(skey):
			continue
		var part: PackedByteArray = (
			(_sections[skey] as SnapshotSection).full() if is_full else _deltas[skey]
		)
		if kind == StationViews.Section.OWNERSHIP and (is_full or not part.is_empty()):
			part = (_sections[skey] as OwnershipSection).for_entry(k[1])
		if part.is_empty() and not is_full:
			continue
		buf.put_u8(kind)
		put_length(buf, part.size())
		buf.put_data(part)
		n += 1
	var out: PackedByteArray = buf.data_array
	out[HEADER_BYTES - 1] = n
	return out


## Sets a ship's claims and last writers (net thread, from NetTransport).
func set_ownership(ship: int, table: Dictionary) -> void:
	_ownership[ship] = table


func take_counts() -> Dictionary:
	var out: Dictionary = counts
	counts = {"builds": 0, "section_updates": 0, "delta_messages": 0, "full_messages": 0}
	return out


## The section of a kind and owner, or null (tests).
func section(kind: int, owner: int) -> SnapshotSection:
	return _sections.get(_skey(kind, owner))


## Writes a section length (u16, or LONG_SECTION then a u32).
static func put_length(buf: StreamPeerBuffer, size: int) -> void:
	if size < LONG_SECTION:
		buf.put_u16(size)
	else:
		buf.put_u16(LONG_SECTION)
		buf.put_u32(size)


## Reads a section length written by put_length().
static func get_length(buf: StreamPeerBuffer) -> int:
	var size: int = buf.get_u16()
	return buf.get_u32() if size == LONG_SECTION else size


## [seq, full, tick] of a snapshot message without decoding its sections.
static func peek(data: PackedByteArray) -> Array:
	return [data.decode_u32(2), data[1] & FLAG_FULL == FLAG_FULL, data.decode_u32(6)]


func _owner(kind: int, ship: int) -> int:
	return _world.faction_of(ship) if kind == StationViews.Section.CONTACTS else ship


func _make(kind: int, owner: int) -> SnapshotSection:
	match kind:
		StationViews.Section.KIN:
			return KinSection.new(kind, owner)
		StationViews.Section.CONTACTS:
			return ContactsSection.new(owner, pos_tol_m)
		StationViews.Section.NEAR:
			return NearSection.new(owner, _orient_of(_world.faction_of(owner)), near_range_m)
		StationViews.Section.PROJECTILES:
			return ProjectilesSection.new(owner, proj_range_m)
		StationViews.Section.OWNERSHIP:
			return OwnershipSection.new(kind, owner)
	return BlockSection.new(kind, owner)


func _known_of(faction: int) -> PackedInt32Array:
	if not _known.has(faction):
		_known[faction] = ContactsSection.known(_world, faction)
	return _known[faction]


func _orient_of(faction: int) -> OrientModel:
	if not _orient.has(faction):
		_orient[faction] = OrientModel.new(rot_tol_deg)
	return _orient[faction]


static func _skey(kind: int, owner: int) -> String:
	return "%d:%d" % [kind, owner]
