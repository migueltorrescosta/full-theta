class_name SitePool
extends RefCounted
## Puts sites in a test world's spawnable pool the way a scenario's map does: a MapDef whose
## `spawnable` holds them, loaded with SiteTable.load_map (D229). A test then opens them with
## SiteTable.open, as the director would.


## One SiteDef: a dockable station gets a dock range of half its radius.
static func def(key: StringName, pos: Vector3, radius: float, kind: StringName = &"nav") -> SiteDef:
	var d: SiteDef = SiteDef.new()
	d.id = key
	d.name_key = "site.%s" % key
	d.kind = kind
	d.pos = pos
	d.radius_m = radius
	d.dockable = kind == &"station"
	d.dock_range_m = 0.5 * radius
	d.dock_max_speed = 10.0
	return d


## Loads a map of no opening sites and these spawnable ones into the world.
static func load_pool(w: SimWorld, defs: Array[SiteDef]) -> void:
	var m: MapDef = MapDef.new()
	m.id = &"test_pool"
	m.spawnable = defs
	w.sites.load_map(w, m)
