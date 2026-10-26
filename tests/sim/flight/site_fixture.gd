class_name SiteFixture
extends RefCounted
## Helpers for the jump, dock and map tests (#10 strand B): the M3 map's sites in a world,
## and Helm commands submitted the way a station sends them.

const SHIP_FACTION: int = 1

## Keep the loaded map referenced while a test runs (load() caches only what is held).
static var _map: MapDef = load("res://content/maps/m3_map.tres") as MapDef


static func map() -> MapDef:
	return _map


## A world with the M3 map's opening sites (site ids in MapDef.sites order), every faction
## knowing them.
static func world(known: int = SiteTable.ALL_FACTIONS) -> SimWorld:
	var m: MapDef = map()
	var w: SimWorld = SimWorld.new(1, "", m.period_m)
	for site: SiteDef in m.sites:
		w.add_site(site, known)
	return w


## The site id of a site key in a world.
static func id_of(w: SimWorld, key: StringName) -> int:
	return w.sites.id_of(key)


## A corvette at `at` with its bow on the point `toward` (by minimum image).
static func corvette_facing(w: SimWorld, at: Vector3, toward: Vector3) -> int:
	var id: int = w.spawn_ship(TestDefs.corvette(), SHIP_FACTION, at)
	face(w, id, toward)
	return id


static func face(w: SimWorld, id: int, toward: Vector3) -> void:
	var offset: Vector3 = w.kin.relative_to_point(id, toward.x, toward.y, toward.z)
	w.kin.rot[id] = Quaternion(Basis.looking_at(offset.normalized(), Vector3.UP))


static func jump_to_site(w: SimWorld, id: int, site: int) -> JumpCommand:
	var c: JumpCommand = JumpCommand.new()
	c.ship_id = id
	c.target_kind = HelmTable.JumpKind.SITE
	c.target_id = site
	w.submit(c)
	return c


static func jump_to_mark(w: SimWorld, id: int, p: Vector3) -> JumpCommand:
	var c: JumpCommand = JumpCommand.new()
	c.ship_id = id
	c.target_kind = HelmTable.JumpKind.MARK
	c.x = p.x
	c.y = p.y
	c.z = p.z
	w.submit(c)
	return c


static func dock(w: SimWorld, id: int, site: int) -> DockCommand:
	var c: DockCommand = DockCommand.new()
	c.ship_id = id
	c.site_id = site
	w.submit(c)
	return c


static func undock(w: SimWorld, id: int) -> UndockCommand:
	var c: UndockCommand = UndockCommand.new()
	c.ship_id = id
	w.submit(c)
	return c


## Steps until an event of `kind` for `ship` appears (at most `limit` ticks); returns the
## ticks stepped, or -1.
static func steps_until(w: SimWorld, kind: StringName, ship: int, limit: int) -> int:
	for i: int in limit:
		w.step()
		for e: SimEvent in w.events:
			if e.kind == kind and e.ship_id == ship:
				return i + 1
	return -1


static func events_of(w: SimWorld, kind: StringName) -> Array[SimEvent]:
	return w.events.filter(func(e: SimEvent) -> bool: return e.kind == kind)


static func input_throttle(w: SimWorld, id: int, throttle: float) -> void:
	var c: HelmInputCommand = HelmInputCommand.new()
	c.ship_id = id
	c.throttle = throttle
	w.submit(c)
