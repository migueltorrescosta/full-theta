extends GdUnitTestSuite
## L3 tests of the SITES snapshot section (#10 strand B, D229, D225): the named sites a
## faction knows reach every view, sent whole and only when the list changes, at most 32
## rows, and the position is a cube offset quantised by NetCodec.

const PLAYER: int = NetHarness.PLAYER
const ENEMY: int = NetHarness.ENEMY

var h: NetHarness


func before_test() -> void:
	h = NetHarness.new(self)


func after_test() -> void:
	await h.free_all()


func _site(key: String, pos: Vector3, dockable: bool = false) -> SiteDef:
	var s: SiteDef = SiteDef.new()
	s.id = StringName(key)
	s.name_key = "site.%s" % key
	s.kind = &"nav"
	s.pos = pos
	s.radius_m = 3000.0
	s.dockable = dockable
	s.dock_range_m = 1500.0
	s.dock_max_speed = 10.0
	return s


# FT: FT-SPA-027, FT-SPA-015
# Every station and view gets the SITES section, and a joined client holds Kestrel Yard
# (site 0, the origin, dockable) as the M1 world names it.
func test_every_view_lists_the_sites_section() -> void:
	for entry: String in StationViews.catalogue_ids(true):
		assert_array(StationViews.def(entry).sections).contains([StationViews.Section.SITES])
	var server: NetServer = h.server()
	var viewer: NetClient = await h.joined(server, "viewer", "viewer")
	assert_bool(await h.until(func() -> bool: return not viewer.view.sites.is_empty())).is_true()
	var yard: Dictionary = viewer.view.sites[0]
	assert_int(yard["id"]).is_equal(0)
	assert_str(yard["name_key"]).is_equal("site.kestrel_yard")
	assert_str(String(yard["kind"])).is_equal("station")
	assert_bool(yard["dockable"]).is_true()
	assert_float(yard["radius"]).is_equal(3000.0)
	assert_vector(yard["pos"]).is_equal(Vector3.ZERO)
	assert_array(viewer.view.kinds).contains([StationViews.Section.SITES])


# FT: FT-SPA-027
# A site opened mid-run reaches the client as a delta with its quantised cube offset (1/16
# m), one only the other faction knows does not, until it is revealed to this one.
func test_a_new_site_reaches_the_client_and_hidden_ones_do_not() -> void:
	var server: NetServer = h.server()
	var crew: Array[NetClient] = await h.crew3(server)
	var helm: NetClient = crew[0]
	assert_bool(await h.until(func() -> bool: return helm.view.sites.size() == 1)).is_true()
	for c: NetClient in crew:
		c.set_ready(true)
	assert_bool(await h.until(func() -> bool: return server.world.tick > 3)).is_true()
	var w: SimWorld = server.world
	var at: Vector3 = Vector3(120000.0, -40000.5, 60000.03)
	w.add_site(_site("vesper", at, true), 1 << w.faction_of(PLAYER))
	var secret: int = w.add_site(_site("secret", Vector3(-100000, 0, 0)), 1 << w.faction_of(ENEMY))
	assert_bool(await h.until(func() -> bool: return helm.view.sites.size() == 2)).is_true()
	var row: Dictionary = helm.view.sites[1]
	assert_str(row["name_key"]).is_equal("site.vesper")
	assert_vector(row["pos"]).is_equal_approx(at, Vector3.ONE * (0.5 / NetCodec.POS_Q))
	assert_bool(row["dockable"]).is_true()
	w.sites.reveal(secret, w.faction_of(PLAYER))
	assert_bool(await h.until(func() -> bool: return helm.view.sites.size() == 3)).is_true()
	assert_int(helm.view.rejected).is_equal(0)


# FT: FT-SPA-027
# D225: the section costs nothing while the list is unchanged (an empty delta), and holds
# at most 32 rows however many sites are open.
func test_sent_only_on_change_and_capped_at_32_rows() -> void:
	var w: SimWorld = SimWorld.new(1)
	for i: int in 3:
		w.add_site(_site("s%d" % i, Vector3(60000.0 * i, 0, 0)))
	var section: SitesSection = SitesSection.new(1)
	var first: PackedByteArray = section.update(w)
	assert_int(first.size()).is_greater(1)
	assert_int(first[0]).is_equal(3)
	assert_array(section.update(w)).is_empty()
	assert_array(section.full()).is_equal(first)
	for i: int in 40:
		w.add_site(_site("t%d" % i, Vector3(0, 0, 5000.0 * i)))
	var many: PackedByteArray = section.update(w)
	assert_int(many[0]).is_equal(SitesSection.MAX_ROWS)
	assert_int(SitesSection.read(_buffer(many)).size()).is_equal(SitesSection.MAX_ROWS)
	assert_array(section.update(w)).is_empty()
	# Rows are small: 16 bytes plus the key, so 32 rows stay near 800 bytes.
	assert_int(many.size()).is_less(1000)


func _buffer(data: PackedByteArray) -> StreamPeerBuffer:
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.data_array = data
	return b
