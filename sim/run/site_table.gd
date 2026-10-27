class_name SiteTable
extends SimTable
## The named sites of the world (D229, D230, FT-SPA-027, FT-MIS-026): one row per site that
## is open, a point with a radius in the one cube. The site id is the row. Rows are keyed
## by ship id -1 and the site's faction, so the table is hashed like the others
## (FT-ARC-012). Which sites exist comes from the MapDef (SimWorld.add_site); the director
## opens more from the map's spawnable pool (open(), OpenSiteCommand).
## Positions are 64-bit like ships' (D104). Helpers take a ship id and use the minimum
## image, so "at a site" and "the nearest site" need no stored space id.

## Mask for "every faction knows it".
const ALL_FACTIONS: int = 0x7FFFFFFF

## Site ids by row (SiteDef.id) and the matching I18n name keys (the name every station of
## every ship uses for the site as a callout layer, FT-SPA-027): data like defs, so not
## hashed. Copied with the table (SimCopy).
var keys: Array[StringName] = []
var name_keys: Array[String] = []
## The sites the director may still open, read-only like defs.
var pool: Array[SiteDef] = []

var pos_x: PackedFloat64Array = PackedFloat64Array()
var pos_y: PackedFloat64Array = PackedFloat64Array()
var pos_z: PackedFloat64Array = PackedFloat64Array()
var radius: PackedFloat64Array = PackedFloat64Array()
## One bit per faction that knows the site (factions 0 to 30).
var known_mask: PackedInt32Array = PackedInt32Array()
## Tick the site opened on.
var opened_tick: PackedInt32Array = PackedInt32Array()
## Index into SiteDef.KINDS.
var kind_ix: PackedByteArray = PackedByteArray()
var dockable: PackedByteArray = PackedByteArray()
var dock_range: PackedFloat64Array = PackedFloat64Array()
var dock_max_speed: PackedFloat64Array = PackedFloat64Array()


## Adds a site (its point wrapped onto the cube of `period`) and returns its site id.
func add_site(def: SiteDef, period: float, known: int, tick: int = 0) -> int:
	var id: int = add_key(-1, def.faction)
	keys.append(def.id)
	name_keys.append(def.name_key)
	pos_x.append(_wrap(def.pos.x, period))
	pos_y.append(_wrap(def.pos.y, period))
	pos_z.append(_wrap(def.pos.z, period))
	radius.append(def.radius_m)
	known_mask.append(known)
	opened_tick.append(tick)
	kind_ix.append(maxi(0, SiteDef.KINDS.find(def.kind)))
	dockable.append(1 if def.dockable else 0)
	dock_range.append(def.dock_range_m)
	dock_max_speed.append(def.dock_max_speed)
	return id


## Opens the map's sites (all of MapDef.sites, in order, so site 0 comes first; the ones in
## known_at_start known to every faction, the rest to none until revealed) and keeps its
## spawnable pool for open() (D229, FT-MIS-027).
func load_map(world: SimWorld, map: MapDef) -> void:
	for def: SiteDef in map.sites:
		var known: int = ALL_FACTIONS if map.known_at_start.has(def.id) else 0
		world.add_site(def, known)
	pool.append_array(map.spawnable)


func has_key(key: StringName) -> bool:
	return keys.has(key)


## The site id of a site key, or -1.
func id_of(key: StringName) -> int:
	return keys.find(key)


## The site id of the key, opening it from the pool when it is closed (known to every
## faction: the director opened it for the run); -1 for a key in neither.
func open(world: SimWorld, key: StringName) -> int:
	var existing: int = keys.find(key)
	if existing >= 0:
		return existing
	for def: SiteDef in pool:
		if def.id == key:
			return world.add_site(def, ALL_FACTIONS)
	return -1


func key_of(site: int) -> StringName:
	return keys[site]


## The I18n key of the site's name, or "" for an unknown site id.
func name_key_of(site: int) -> String:
	return name_keys[site] if site >= 0 and site < name_keys.size() else ""


func kind_of(site: int) -> StringName:
	return SiteDef.KINDS[kind_ix[site]]


func dockable_of(site: int) -> bool:
	return dockable[site] == 1


## Pool keys not opened yet, sorted.
func closed_keys() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for def: SiteDef in pool:
		if not keys.has(def.id):
			out.append(def.id)
	out.sort()
	return out


func is_known(site: int, faction: int) -> bool:
	return site >= 0 and site < size() and (known_mask[site] >> faction) & 1 == 1


## Lets a faction know the site.
func reveal(site: int, faction: int) -> void:
	if site >= 0 and site < size():
		known_mask[site] |= 1 << faction


## The site's point in the cube (m, 64-bit [x, y, z]).
func point(site: int) -> PackedFloat64Array:
	return PackedFloat64Array([pos_x[site], pos_y[site], pos_z[site]])


## The same as a Vector3 (float32).
func point3(site: int) -> Vector3:
	return Vector3(pos_x[site], pos_y[site], pos_z[site])


## The nearest site to a ship by minimum image (lowest id on a tie), or -1 with no sites.
static func nearest(world: SimWorld, ship: int) -> int:
	var sites: SiteTable = world.sites
	var best: int = -1
	var best_d: float = INF
	for s: int in sites.size():
		var d: float = (
			world
			. kin
			. relative_to_point(ship, sites.pos_x[s], sites.pos_y[s], sites.pos_z[s])
			. length()
		)
		if d < best_d:
			best_d = d
			best = s
	return best


## The site the ship is within the radius of (the nearest one), else -1.
static func at_site(world: SimWorld, ship: int) -> int:
	var s: int = nearest(world, ship)
	if s < 0:
		return -1
	var sites: SiteTable = world.sites
	var d: float = (
		world.kin.relative_to_point(ship, sites.pos_x[s], sites.pos_y[s], sites.pos_z[s]).length()
	)
	return s if d <= sites.radius[s] else -1


## Offset from the ship to the site's point (m, world axes) by minimum image; Vector3.INF
## for an unknown site id.
static func offset_to(world: SimWorld, ship: int, site: int) -> Vector3:
	var sites: SiteTable = world.sites
	if site < 0 or site >= sites.size():
		return Vector3.INF
	return world.kin.relative_to_point(
		ship, sites.pos_x[site], sites.pos_y[site], sites.pos_z[site]
	)


func columns() -> Array:
	return (
		super()
		+ [
			["pos_x", pos_x],
			["pos_y", pos_y],
			["pos_z", pos_z],
			["radius", radius],
			["known_mask", known_mask],
			["opened_tick", opened_tick],
			["kind_ix", kind_ix],
			["dockable", dockable],
			["dock_range", dock_range],
			["dock_max_speed", dock_max_speed],
		]
	)


static func _wrap(v: float, period: float) -> float:
	return fposmod(v + 0.5 * period, period) - 0.5 * period
