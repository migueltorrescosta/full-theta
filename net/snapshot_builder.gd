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

## The header and length escape, as the clients read them (SnapshotReader).

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
## When true, build() adds its time per part to part_us (the load probe, D161): index 0
## the near sets and orientation models, then one per StationViews.Section kind
## (NetTransport.SNAP_FIELDS names them).
var time_parts: bool = false
var part_us: PackedInt64Array = PackedInt64Array()

var _world: SimWorld
## "kind:owner" -> SnapshotSection.
var _sections: Dictionary = {}
## Faction -> OrientModel.
var _orient: Dictionary = {}
## "kind:owner" -> delta bytes of this snapshot.
var _deltas: Dictionary = {}
## View key -> its chunks of this snapshot, delta and full.
var _cache_delta: Dictionary = {}
var _cache_full: Dictionary = {}
## View key -> [[kind, owner, skey]] of its sections, derived once per key (the strings
## and filter signatures cost more than the sections' own work); dropped when the ship
## count changes.
var _lists: Dictionary = {}
var _lists_ships: int = -1
## Ship -> ownership table posted by the main thread (OwnershipSection).
var _ownership: Dictionary = {}
## Faction -> the ship ids it knows (ContactsSection.known), computed once per build.
var _known: Dictionary = {}
## Ship -> the ship's open request chips posted by the main thread (ChipsSection).
var _chips: Dictionary = {}
## View key -> ViewFilter (its toggle code and entry fixed by the key).
var _filters: Dictionary = {}


func _init() -> void:
	take_counts()
	part_us.resize(int(StationViews.Section.values().max()) + 1)


## Advances every section the view keys need to the copied world's tick. Keys naming a
## ship the world doesn't have are skipped.
func build(world: SimWorld, snapshot_seq: int, view_keys: Array) -> void:
	_world = world
	seq = snapshot_seq
	tick = world.tick
	_deltas.clear()
	_cache_delta.clear()
	_cache_full.clear()
	_known.clear()
	if world.ship_count() != _lists_ships:
		_lists.clear()
		_lists_ships = world.ship_count()
	var needed: Dictionary = {}
	var near_ships: Dictionary = {}
	for view_key: String in view_keys:
		var k: Array = StationViews.parse_key(view_key)
		var ship: int = k[0]
		if ship < 0 or ship >= world.ship_count():
			continue
		var filter: ViewFilter = _filter_of(view_key)
		for item: Array in _list_of(view_key):
			needed[item[2]] = [item[0], item[1], filter]
			if item[0] == StationViews.Section.NEAR:
				near_ships[ship] = true
	for skey: String in _sections.keys():
		if not needed.has(skey):
			_sections.erase(skey)
	for skey: String in needed:
		if not _sections.has(skey):
			_sections[skey] = _make(needed[skey][0], needed[skey][1], needed[skey][2])
	# Near sets first: one orientation model per faction serves all its ships.
	var near_sets: Dictionary = {}
	var unions: Dictionary = {}
	var t0: int = Time.get_ticks_usec() if time_parts else 0
	for ship: int in near_ships:
		var f: int = world.faction_of(ship)
		var section: NearSection = _sections[_skey(StationViews.Section.NEAR, ship)]
		near_sets[ship] = section.in_range(world, _known_of(f))
		(unions.get_or_add(f, {}) as Dictionary).merge(near_sets[ship])
	for f: int in unions:
		_orient_of(f).update(world, unions[f])
	if time_parts:
		var t1: int = Time.get_ticks_usec()
		part_us[0] += t1 - t0
		t0 = t1
	for skey: String in _sections:
		var section: SnapshotSection = _sections[skey]
		if section is OwnershipSection:
			(section as OwnershipSection).data = _ownership.get(section.owner, {})
		elif section is ContactsSection:
			(section as ContactsSection).ids = _known_of(section.owner)
		elif section is ChipsSection:
			(section as ChipsSection).rows = _chips.get(section.owner, [])
		elif section is CommsSection:  # the claims name each conversation's claimer
			(section as CommsSection).claims = _ownership.get(section.owner, {}).get("claims", {})
		if section is NearSection:
			_deltas[skey] = (section as NearSection).update_members(world, near_sets[section.owner])
		else:
			_deltas[skey] = section.update(world)
		if time_parts:
			var t1: int = Time.get_ticks_usec()
			part_us[section.kind] += t1 - t0
			t0 = t1
	counts["builds"] += 1
	counts["section_updates"] += _sections.size()


## The chunks of a view key's message at the current snapshot, built once and shared.
func chunks(view_key: String, is_full: bool) -> Array[PackedByteArray]:
	var cache: Dictionary = _cache_full if is_full else _cache_delta
	if cache.has(view_key):
		return cache[view_key]
	var out: Array[PackedByteArray] = NetChunker.split(
		NetChunker.STREAM_SNAPSHOT, seq, message(view_key, is_full), chunk_size
	)
	cache[view_key] = out
	counts["full_messages" if is_full else "delta_messages"] += 1
	return out


## A view key's message at the current snapshot (not cached; chunks() caches).
func message(view_key: String, is_full: bool) -> PackedByteArray:
	var k: Array = StationViews.parse_key(view_key)
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.put_u8(NetProtocol.Type.SNAPSHOT)
	buf.put_u8(SnapshotReader.FLAG_FULL if is_full else 0)
	buf.put_u32(seq)
	buf.put_u32(tick)
	buf.put_u8(0)
	var n: int = 0
	for item: Array in _list_of(view_key):
		var kind: int = item[0]
		var skey: String = item[2]
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
	out[SnapshotReader.HEADER_BYTES - 1] = n
	return out


## Sets a ship's claims and last writers (net thread, from NetTransport).
func set_ownership(ship: int, table: Dictionary) -> void:
	_ownership[ship] = table


## Sets a ship's open request chips (net thread, from NetTransport): the rows of
## ChipsSection, {id, chip, arg, from, to, sent, expires} with from and to the station
## indices of StationViews.CREW.
func set_chips(ship: int, rows: Array) -> void:
	_chips[ship] = rows


func take_counts() -> Dictionary:
	var out: Dictionary = counts
	counts = {"builds": 0, "section_updates": 0, "delta_messages": 0, "full_messages": 0}
	return out


## The section of a kind and owner, or null (tests). `signature` names the filtered
## variant (ViewFilter.signature) of a section in StationViews.FILTERED.
func section(kind: int, owner: int, signature: String = "") -> SnapshotSection:
	return _sections.get(_skey(kind, owner, signature))


## Writes a section length (u16, or SnapshotReader.LONG_SECTION then a u32).
static func put_length(buf: StreamPeerBuffer, size: int) -> void:
	if size < SnapshotReader.LONG_SECTION:
		buf.put_u16(size)
	else:
		buf.put_u16(SnapshotReader.LONG_SECTION)
		buf.put_u32(size)


## The sections of a view key as [kind, owner, section key], cached per key.
func _list_of(view_key: String) -> Array:
	if _lists.has(view_key):
		return _lists[view_key]
	var k: Array = StationViews.parse_key(view_key)
	var filter: ViewFilter = _filter_of(view_key)
	var out: Array = []
	for kind: int in StationViews.sections_of(k[1]):
		var owner: int = _owner(kind, k[0])
		out.append([kind, owner, _skey(kind, owner, _signature(kind, filter))])
	_lists[view_key] = out
	return out


func _owner(kind: int, ship: int) -> int:
	if kind == StationViews.Section.SITES:
		return _world.faction_of(ship)
	return _world.faction_of(ship) if kind == StationViews.Section.CONTACTS else ship


func _make(kind: int, owner: int, filter: ViewFilter) -> SnapshotSection:
	var section: SnapshotSection
	match kind:
		StationViews.Section.KIN:
			section = KinSection.new(kind, owner)
		StationViews.Section.CONTACTS:
			section = ContactsSection.new(owner, pos_tol_m)
		StationViews.Section.NEAR:
			section = NearSection.new(owner, _orient_of(_world.faction_of(owner)), near_range_m)
		StationViews.Section.PROJECTILES:
			section = ProjectilesSection.new(owner, proj_range_m)
		StationViews.Section.OWNERSHIP:
			section = OwnershipSection.new(kind, owner)
		StationViews.Section.CHIPS:
			section = ChipsSection.new(kind, owner, filter)
		StationViews.Section.COMMS:
			section = CommsSection.new(kind, owner, filter)
		StationViews.Section.SITES:
			section = SitesSection.new(owner)
		_:
			section = BlockSection.new(kind, owner, filter)
	return section


func _known_of(faction: int) -> PackedInt32Array:
	if not _known.has(faction):
		_known[faction] = ContactsSection.known(_world, faction)
	return _known[faction]


func _orient_of(faction: int) -> OrientModel:
	if not _orient.has(faction):
		_orient[faction] = OrientModel.new(rot_tol_deg)
	return _orient[faction]


## The filter of a view key (an unreadable toggle code gets the default set).
func _filter_of(view_key: String) -> ViewFilter:
	if not _filters.has(view_key):
		var k: Array = StationViews.parse_key(view_key)
		var f: ViewFilter = ViewFilter.of(k[1], k[2])
		_filters[view_key] = f if f != null else ViewFilter.of(k[1], StationViews.DEFAULT_TOGGLES)
	return _filters[view_key]


static func _signature(kind: int, filter: ViewFilter) -> String:
	return filter.signature(kind) if StationViews.FILTERED.has(kind) else ""


static func _skey(kind: int, owner: int, signature: String = "") -> String:
	return "%d:%d" % [kind, owner] if signature == "" else "%d:%d:%s" % [kind, owner, signature]
