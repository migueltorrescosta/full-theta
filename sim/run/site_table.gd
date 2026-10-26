class_name SiteTable
extends SimTable
## STUB until strand B merges (#10): B's sim/run/site_table.gd replaces this file (on merge
## take B's). It has
## the columns of contracts.md section 2 plus the accessors strand A calls (listed in the
## strand A report): register, load_map, open, has_key, key_of, point, kind_of,
## dockable_of, closed_keys, nearest, at_site, offset_to. Take strand B's file on merge.

var key_ix: PackedInt32Array = PackedInt32Array()
var px: PackedFloat64Array = PackedFloat64Array()
var py: PackedFloat64Array = PackedFloat64Array()
var pz: PackedFloat64Array = PackedFloat64Array()
var radius: PackedFloat64Array = PackedFloat64Array()
var known_mask: PackedInt32Array = PackedInt32Array()
var opened_tick: PackedInt32Array = PackedInt32Array()
## key_ix indexes this.
var keys: Array[StringName] = []
## Site data by key (not state): pos, radius, kind, dockable.
var catalogue: Dictionary[StringName, Dictionary] = {}


func add_ship(_ship_id: int, _faction: int, _def: ShipDef) -> void:
	pass


func reset_ship(_ship_id: int, _def: ShipDef) -> void:
	pass


func columns() -> Array:
	return (
		super()
		+ [
			["key_ix", key_ix],
			["px", px],
			["py", py],
			["pz", pz],
			["radius", radius],
			["known_mask", known_mask],
			["opened_tick", opened_tick]
		]
	)


func register(key: StringName, pos: Vector3, site_radius: float, kind: StringName = &"nav") -> void:
	catalogue[key] = {"pos": pos, "radius": site_radius, "kind": kind}


func load_map(world: SimWorld, map: MapDef) -> void:
	for key: StringName in map.known_at_start:
		open(world, key)


func has_key(key: StringName) -> bool:
	return keys.has(key)


## The site id of the key (opening it when it is in the catalogue), or -1.
func open(world: SimWorld, key: StringName) -> int:
	var row: int = keys.find(key)
	if row >= 0:
		return row
	if not catalogue.has(key):
		return -1
	var d: Dictionary = catalogue[key]
	var pos: Vector3 = d["pos"]
	row = add_key(-1, -1)
	keys.append(key)
	key_ix.append(keys.size() - 1)
	px.append(pos.x)
	py.append(pos.y)
	pz.append(pos.z)
	radius.append(d["radius"])
	known_mask.append(0)
	opened_tick.append(world.tick)
	return row


func key_of(site: int) -> StringName:
	return keys[key_ix[site]]


func point(site: int) -> PackedFloat64Array:
	return PackedFloat64Array([px[site], py[site], pz[site]])


func kind_of(site: int) -> StringName:
	return catalogue[key_of(site)]["kind"]


func dockable_of(site: int) -> bool:
	return kind_of(site) == &"station"


## Catalogue keys not opened yet, sorted.
func closed_keys() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for key: StringName in catalogue:
		if not keys.has(key):
			out.append(key)
	out.sort()
	return out


static func nearest(world: SimWorld, ship: int) -> int:
	var best: int = -1
	var best_d: float = INF
	for s: int in world.sites.size():
		var d: float = offset_to(world, ship, s).length()
		if d < best_d:
			best_d = d
			best = s
	return best


static func at_site(world: SimWorld, ship: int) -> int:
	var s: int = nearest(world, ship)
	if s >= 0 and offset_to(world, ship, s).length() <= world.sites.radius[s]:
		return s
	return -1


static func offset_to(world: SimWorld, ship: int, site: int) -> Vector3:
	var p: PackedFloat64Array = world.sites.point(site)
	return world.kin.relative_to_point(ship, p[0], p[1], p[2])
