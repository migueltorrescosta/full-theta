class_name S9Builder
extends RefCounted
## Builds the snapshots of every view of the player ships (FT-NET-040): once per
## snapshot it advances each section (own and Engineering blocks, near and
## projectile sections per ship, one contact and one orientation model per
## faction), then assembles each view key's message on first request and
## shares it among the clients holding that key.
##
## Player ships are ids 0..ships-1 of the S9World; ship i is in faction
## i % factions. A faction knows every ship within `sensor_range_m` of one of
## its player ships (a stand-in for the sensor model, FT-NET-010).

var ships: int = 6
var factions: int = 1
var sensor_range_m: float = 20000.0
var proj_range_m: float = 1000.0
var seq: int = 0
var tick: int = 0
var sent_us: int = 0
## Counters since the last take_counts(): snapshot builds, section encodes,
## view-key messages assembled (delta and full), and build time per phase.
var counts: Dictionary = {}

var _world: S9World
var _own: Array[S9Own] = []
var _near: Array[S9Near] = []
var _proj: Array[S9Proj] = []
var _radar: Array[S9Radar] = []
var _orient: Array[S9Orient] = []
var _deltas: Dictionary = {}
var _cache: Dictionary = {}


func _init(world: S9World, opts: Dictionary = {}) -> void:
	_world = world
	ships = opts.get("ships", ships)
	factions = opts.get("factions", factions)
	sensor_range_m = opts.get("sensor_range", sensor_range_m)
	proj_range_m = opts.get("proj_range", proj_range_m)
	for s: int in range(ships):
		_own.append(S9Own.new(s))
		_near.append(S9Near.new(s, opts.get("near_range", 2000.0)))
		_proj.append(S9Proj.new(s, proj_range_m))
	for f: int in range(factions):
		_radar.append(S9Radar.new(opts.get("pos_tol", 0.5)))
		_orient.append(S9Orient.new(opts.get("rot_tol_deg", 1.0)))
	take_counts()


func faction_of(ship: int) -> int:
	return ship % factions


## Records hits on player ships from the world's last tick (status stand-in).
func note_tick_events() -> void:
	var ev: PackedInt32Array = _world.events
	for i: int in range(0, ev.size(), 4):
		if ev[i + 1] == S6WorldPacked.EV_HIT and ev[i + 3] < ships:
			_own[ev[i + 3]].hits += 1


## Advances every section to the world's current tick.
func build(snapshot_seq: int, now_us: int) -> void:
	seq = snapshot_seq
	tick = _world.tick
	sent_us = now_us
	_deltas.clear()
	_cache.clear()
	var t0: int = Time.get_ticks_usec()
	var known: Array[PackedInt32Array] = _known_lists()
	var near_sets: Array[Dictionary] = []
	var unions: Array[Dictionary] = []
	for f: int in range(factions):
		unions.append({})
	for s: int in range(ships):
		var set_s: Dictionary = _near[s].in_range(_world, known[faction_of(s)])
		near_sets.append(set_s)
		unions[faction_of(s)].merge(set_s)
	var player_ids: PackedInt32Array = PackedInt32Array(range(ships))
	var proj_lists: Array[PackedInt32Array] = S9Proj.near_lists(_world, player_ids, proj_range_m)
	var t1: int = Time.get_ticks_usec()
	for f: int in range(factions):
		_deltas[_skey(S9Radar.KIND, f)] = _radar[f].update(_world, known[f], tick)
	var t2: int = Time.get_ticks_usec()
	for f: int in range(factions):
		_orient[f].update(_world, unions[f], tick)
	for s: int in range(ships):
		_deltas[_skey(S9Near.KIND, s)] = _near[s].update(near_sets[s], _orient[faction_of(s)])
	var t3: int = Time.get_ticks_usec()
	for s: int in range(ships):
		var own: Array[PackedByteArray] = _own[s].update(_world, tick)
		_deltas[_skey(S9Own.KIND_OWN, s)] = own[0]
		_deltas[_skey(S9Own.KIND_ENG, s)] = own[1]
		_deltas[_skey(S9Proj.KIND, s)] = _proj[s].update(_world, proj_lists[s], tick)
	var t4: int = Time.get_ticks_usec()
	counts["builds"] += 1
	counts["section_encodes"] += _deltas.size()
	counts["us_filter"] += t1 - t0
	counts["us_radar"] += t2 - t1
	counts["us_near"] += t3 - t2
	counts["us_own_proj"] += t4 - t3


## The message for a view key at the current snapshot, assembled once.
func message(ship: int, entry: String, toggles: String, is_full: bool) -> PackedByteArray:
	var k: String = "%s|%d" % [S9Views.key(ship, entry, toggles), 1 if is_full else 0]
	if _cache.has(k):
		return _cache[k]
	var t0: int = Time.get_ticks_usec()
	var kinds: Array = S9Views.SECTIONS[entry]
	var parts: Array[PackedByteArray] = []
	for kind: int in kinds:
		parts.append(_part(kind, ship, is_full))
	var bytes: PackedByteArray = S9Views.message(seq, tick, sent_us, is_full, kinds, parts)
	_cache[k] = bytes
	counts["full_messages" if is_full else "delta_messages"] += 1
	counts["us_messages"] += Time.get_ticks_usec() - t0
	return bytes


func take_counts() -> Dictionary:
	var out: Dictionary = counts
	counts = {
		"builds": 0,
		"section_encodes": 0,
		"delta_messages": 0,
		"full_messages": 0,
		"us_filter": 0,
		"us_radar": 0,
		"us_near": 0,
		"us_own_proj": 0,
		"us_messages": 0,
	}
	return out


func radar_model(faction: int) -> Dictionary:
	return _radar[faction].model


func near_model(ship: int) -> Dictionary:
	return _near[ship].client_model(_orient[faction_of(ship)])


func proj_model(ship: int) -> Dictionary:
	return _proj[ship].model


func _part(kind: int, ship: int, is_full: bool) -> PackedByteArray:
	if not is_full:
		var owner: int = faction_of(ship) if kind == S9Radar.KIND else ship
		return _deltas[_skey(kind, owner)]
	match kind:
		S9Own.KIND_OWN:
			return _own[ship].full_own()
		S9Own.KIND_ENG:
			return _own[ship].full_eng()
		S9Radar.KIND:
			return _radar[faction_of(ship)].full(tick)
		S9Near.KIND:
			return _near[ship].full(_orient[faction_of(ship)], tick)
	return _proj[ship].full(tick)


## Ships each faction knows, ascending ids, same site as one of its ships.
func _known_lists() -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	var r2: float = sensor_range_m * sensor_range_m
	var positions: PackedVector3Array = _world.ship_positions()
	var n: int = _world.ship_count()
	for f: int in range(factions):
		var ids: PackedInt32Array = PackedInt32Array()
		for id: int in range(n):
			var p: Vector3 = positions[id]
			var site: int = _world.ship_site(id)
			for s: int in range(f, ships, factions):
				if site == _world.ship_site(s) and p.distance_squared_to(positions[s]) <= r2:
					ids.append(id)
					break
		out.append(ids)
	return out


static func _skey(kind: int, owner: int) -> int:
	return kind * 1000 + owner
