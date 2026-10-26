extends GdUnitTestSuite
## MapDef and the SiteTable (D229, D230): the M3 map is one 400 km wrapping cube with 5 to 8
## named sites, rejected when P or the spacing is wrong, and sites far enough apart that
## contacts never bleed from one to another.

const SHIPS_KEYS: Array[String] = ["corvette", "raider"]


func _ships() -> Array[ShipDef]:
	return [TestDefs.corvette(), TestDefs.raider()]


func _site(key: StringName, pos: Vector3, radius: float = 3000.0) -> SiteDef:
	var s: SiteDef = SiteDef.new()
	s.id = key
	s.name_key = "site.%s" % key
	s.pos = pos
	s.radius_m = radius
	return s


func _map(sites: Array[SiteDef], period: float = 400000.0) -> MapDef:
	var m: MapDef = MapDef.new()
	m.id = &"t"
	m.period_m = period
	m.sites = sites
	return m


# FT: FT-SIM-035, FT-MIS-024
# The content map: P = 400 km, 5 to 8 sites in all, Kestrel Yard site 0 at the origin,
# no errors against the M1 ships, every key unique.
func test_the_m3_map_is_valid() -> void:
	var m: MapDef = SiteFixture.map()
	assert_float(m.period_m).is_equal(400000.0)
	assert_array(m.errors(_ships())).is_empty()
	assert_int(m.all_sites().size()).is_between(5, 8)
	assert_str(String(m.sites[0].id)).is_equal("kestrel_yard")
	assert_vector(m.sites[0].pos).is_equal(Vector3.ZERO)
	assert_bool(m.sites[0].dockable).is_true()
	assert_int(m.known_at_start.size()).is_greater(0)


# FT: FT-SIM-035
# P rules: at least 4 x the longest sensor range (20 km), a multiple of 500 m, at most
# 2^20 cells.
func test_period_rules() -> void:
	var sites: Array[SiteDef] = [_site(&"a", Vector3.ZERO)]
	assert_array(_map(sites, 79500.0).errors(_ships())).is_not_empty()
	assert_array(_map(sites, 80000.0).errors(_ships())).is_empty()
	assert_array(_map(sites, 400250.0).errors(_ships())).is_not_empty()
	assert_array(_map(sites, 600_000_000.0).errors(_ships())).is_not_empty()
	assert_array(_map(sites, 0.0).errors(_ships())).is_not_empty()


# FT: FT-SIM-035
# MapDef.period_errors and SimWorld.period_errors both are PeriodRules.errors; kept equal here.
func test_period_rules_match_the_sim_world() -> void:
	for period: float in [0.0, NAN, 1500.0, 79500.0, 80000.0, 400000.0, 400250.0, 6.0e8]:
		var m: MapDef = _map([_site(&"a", Vector3.ZERO)], period)
		assert_array(m.period_errors(_ships())).is_equal(SimWorld.period_errors(period, _ships()))


# FT: FT-SIM-035, FT-MIS-024
# Spacing: two sites must be at least 2 x the longest sensor range plus both radii apart
# (46 km for two 3 km sites), by minimum image: 45.9 km errors, 46 km passes, and two sites
# 354 km apart in coordinates are 46 km apart across the seam.
func test_spacing_rule() -> void:
	var near: Array[SiteDef] = [_site(&"a", Vector3.ZERO), _site(&"b", Vector3(45900.0, 0, 0))]
	assert_array(_map(near).errors(_ships())).is_not_empty()
	var ok: Array[SiteDef] = [_site(&"a", Vector3.ZERO), _site(&"b", Vector3(46000.0, 0, 0))]
	assert_array(_map(ok).errors(_ships())).is_empty()
	var seam_bad: Array[SiteDef] = [
		_site(&"a", Vector3(177000.0, 0, 0)), _site(&"b", Vector3(-178000.0, 0, 0))
	]
	assert_array(_map(seam_bad).errors(_ships())).is_not_empty()
	var seam_ok: Array[SiteDef] = [
		_site(&"a", Vector3(177000.0, 0, 0)), _site(&"b", Vector3(-177000.0, 0, 0))
	]
	assert_array(_map(seam_ok).errors(_ships())).is_empty()
	var big: Array[SiteDef] = [
		_site(&"a", Vector3.ZERO, 8000.0), _site(&"b", Vector3(50000.0, 0, 0))
	]
	assert_array(_map(big).errors(_ships())).is_not_empty()


# FT: FT-MIS-024
# Unknown keys in known_at_start and legs, a duplicate id and a site with no radius are
# errors too.
func test_key_errors() -> void:
	var sites: Array[SiteDef] = [_site(&"a", Vector3.ZERO), _site(&"b", Vector3(100000.0, 0, 0))]
	var m: MapDef = _map(sites)
	m.known_at_start = [&"a", &"zzz"]
	m.legs = [{"from": &"a", "to": &"nowhere", "debris": &"m1_dust_cloud", "count": 1}]
	var errors: Array[String] = m.errors(_ships())
	assert_int(errors.size()).is_equal(2)
	var dup: Array[SiteDef] = [_site(&"a", Vector3.ZERO), _site(&"a", Vector3(100000.0, 0, 0))]
	assert_array(_map(dup).errors(_ships())).is_not_empty()
	var flat: Array[SiteDef] = [_site(&"a", Vector3.ZERO, 0.0)]
	assert_array(_map(flat).errors(_ships())).is_not_empty()


# FT: FT-SIM-035, FT-MIS-024
# No contacts bleed between two sites at the minimum spacing (46 km, radii 3 km): ships at
# the nearest edges of the two sites are 40 km apart, beyond both ships' sensors (20 km and
# 15 km), while a ship 5 km from the first is seen. The same across the seam.
func test_no_contact_bleed_at_the_minimum_spacing() -> void:
	for seam: bool in [false, true]:
		var a: Vector3 = Vector3(177000.0, 0, 0) if seam else Vector3.ZERO
		var b: Vector3 = Vector3(-177000.0, 0, 0) if seam else Vector3(46000.0, 0, 0)
		var m: MapDef = _map([_site(&"a", a), _site(&"b", b)])
		assert_array(m.errors(_ships())).is_empty()
		var w: SimWorld = SimWorld.new(1, "", m.period_m)
		w.add_site(m.sites[0])
		w.add_site(m.sites[1])
		var toward: Vector3 = Vector3.RIGHT
		var blue: int = w.spawn_ship(TestDefs.corvette(), 1, a + toward * 3000.0)
		var red: int = w.spawn_ship(TestDefs.raider(), 2, b - toward * 3000.0)
		var near_other: int = w.spawn_ship(TestDefs.raider(), 3, a + toward * 8000.0)
		w.step()
		assert_float(w.kin.relative(blue, red).length()).is_equal_approx(40000.0, 1e-3)
		assert_bool(KnowledgeSystem.is_detected(w, 1, red)).is_false()
		assert_bool(KnowledgeSystem.is_detected(w, 2, blue)).is_false()
		assert_bool(KnowledgeSystem.is_detected(w, 1, near_other)).is_true()
		assert_int(SiteTable.at_site(w, blue)).is_equal(0)
		assert_int(SiteTable.at_site(w, red)).is_equal(1)


# FT: FT-SPA-027, FT-SIM-035
# SiteTable: nearest picks by minimum image, at_site only inside the radius, offset_to is
# the minimum image to the point, and the table is hashed.
func test_site_table_lookups() -> void:
	var w: SimWorld = SiteFixture.world()
	var m: MapDef = SiteFixture.map()
	assert_int(w.sites.size()).is_equal(m.sites.size())
	var yard: int = w.spawn_ship(TestDefs.corvette(), 1, Vector3(2900.0, 0, 0))
	assert_int(SiteTable.nearest(w, yard)).is_equal(0)
	assert_int(SiteTable.at_site(w, yard)).is_equal(0)
	w.kin.place(yard, 3100.0, 0.0, 0.0)
	assert_int(SiteTable.nearest(w, yard)).is_equal(0)
	assert_int(SiteTable.at_site(w, yard)).is_equal(-1)
	assert_float(SiteTable.offset_to(w, yard, 0).x).is_equal(-3100.0)
	# Near Hollow Gate's far side of the seam: x = +150 km, so a ship at -200 km + 40 km
	# is closest to... Vesper (120, 40, -60) is 134 km from the origin; place a ship by it.
	var vesper: int = SiteFixture.id_of(w, &"vesper_beacon")
	w.kin.place(yard, 121000.0, 40000.0, -60000.0)
	assert_int(SiteTable.nearest(w, yard)).is_equal(vesper)
	assert_int(SiteTable.at_site(w, yard)).is_equal(vesper)
	assert_bool(SiteTable.offset_to(w, yard, 99).is_finite()).is_false()
	var before: String = w.state_hash()
	w.sites.pos_x[0] = 10.0
	assert_str(w.state_hash()).is_not_equal(before)


# FT: FT-SPA-027
# open() takes a site from the spawnable pool once and knows it only to the factions
# given; a key outside the pool is -1.
func test_open_a_spawnable_site() -> void:
	var w: SimWorld = SiteFixture.world()
	var m: MapDef = SiteFixture.map()
	w.sites.pool = m.spawnable.duplicate()
	var key: StringName = m.spawnable[0].id
	assert_bool(w.sites.closed_keys().has(key)).is_true()
	w.tick = 120
	var id: int = w.sites.open(w, key)
	assert_int(id).is_equal(m.sites.size())
	assert_int(w.sites.open(w, key)).is_equal(id)
	assert_int(w.sites.opened_tick[id]).is_equal(120)
	assert_bool(w.sites.is_known(id, 1)).is_true()
	assert_bool(w.sites.has_key(key)).is_true()
	assert_str(String(w.sites.key_of(id))).is_equal(String(key))
	assert_bool(w.sites.closed_keys().has(key)).is_false()
	assert_int(w.sites.open(w, &"nope")).is_equal(-1)
	assert_str(String(w.sites.kind_of(0))).is_equal("station")
	assert_bool(w.sites.dockable_of(0)).is_true()
	assert_float(w.sites.point(0)[0]).is_equal(0.0)


# FT: FT-MIS-024, FT-SPA-027
# load_map opens every site of the map in order (Kestrel Yard first), known to every faction
# only for known_at_start, and keeps the spawnable pool closed.
func test_load_map_opens_the_sites() -> void:
	var w: SimWorld = SimWorld.new(1)
	var m: MapDef = SiteFixture.map()
	w.sites.load_map(w, m)
	assert_int(w.sites.size()).is_equal(m.sites.size())
	assert_str(String(w.sites.key_of(0))).is_equal("kestrel_yard")
	for i: int in m.sites.size():
		assert_bool(w.sites.is_known(i, 1)).is_equal(m.known_at_start.has(m.sites[i].id))
	assert_int(w.sites.closed_keys().size()).is_equal(m.spawnable.size())


# FT: FT-HLM-016, FT-SPA-015
# Selecting a site: Helm's target is the site, assist sees an offset to its point, a site
# the faction doesn't know is refused, and selecting a ship afterwards clears the site.
func test_select_a_site() -> void:
	var w: SimWorld = SiteFixture.world()
	var vesper: int = SiteFixture.id_of(w, &"vesper_beacon")
	var ship: int = w.spawn_ship(TestDefs.corvette(), 1)
	var c: SelectTargetCommand = SelectTargetCommand.new()
	c.ship_id = ship
	c.site_id = vesper
	w.submit(c)
	w.step()
	assert_bool(c.accepted).is_true()
	assert_int(w.helm.target_kind[ship]).is_equal(HelmTable.Target.SITE)
	assert_int(w.helm.target_site[ship]).is_equal(vesper)
	assert_bool(AssistSystem.has_target(w, ship)).is_true()
	assert_vector(AssistSystem.target_offset(w, ship)).is_equal_approx(
		w.sites.point3(vesper), Vector3.ONE * 0.01
	)
	var hidden: SelectTargetCommand = SelectTargetCommand.new()
	hidden.ship_id = ship
	hidden.site_id = 50
	w.submit(hidden)
	w.step()
	assert_bool(hidden.accepted).is_false()
	var none: SelectTargetCommand = SelectTargetCommand.new()
	none.ship_id = ship
	w.submit(none)
	w.step()
	assert_int(w.helm.target_kind[ship]).is_equal(HelmTable.Target.NONE)
	assert_int(w.helm.target_site[ship]).is_equal(-1)
