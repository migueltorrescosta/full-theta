extends GdUnitTestSuite
## L3 tests of the SITES snapshot section (D229, D225): the named sites a
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
	s.radius = 3000.0
	s.dockable = dockable
	s.dock_range = 1500.0
	s.dock_max_speed = 10.0
	return s


# FT: FT-SPA-027, FT-SPA-015
# Every station and view gets the SITES section, and a joined client holds Kestrel Yard
# (site 0, the origin, dockable) as the M1 world names it.
func test_every_view_lists_the_sites_section() -> void:
	for seat: String in StationCatalogue.catalogue_ids(true):
		assert_array(StationCatalogue.def(seat).sections).contains([StationCatalogue.Section.SITES])
	var server: NetServer = h.server()
	var viewer: NetClient = await h.joined(server, "viewer", "viewer")
	assert_bool(await h.until(func() -> bool: return not viewer.snap.sites.is_empty())).is_true()
	var yard: Dictionary = viewer.snap.sites[0]
	assert_int(yard["id"]).is_equal(0)
	assert_str(yard["name_key"]).is_equal("site.kestrel_yard")
	assert_str(String(yard["kind"])).is_equal("station")
	assert_bool(yard["dockable"]).is_true()
	assert_float(yard["radius"]).is_equal(3000.0)
	assert_vector(yard["pos"]).is_equal(Vector3.ZERO)
	assert_array(viewer.snap.kinds).contains([StationCatalogue.Section.SITES])


# FT: FT-SPA-027
# A site opened mid-run reaches the client as a delta with its quantised cube offset (1/16
# m), one only the other faction knows does not, until it is revealed to this one.
func test_a_new_site_reaches_the_client_and_hidden_ones_do_not() -> void:
	var server: NetServer = h.server()
	var crew: Array[NetClient] = await h.crew3(server)
	var helm: NetClient = crew[0]
	assert_bool(await h.until(func() -> bool: return helm.snap.sites.size() == 1)).is_true()
	h.all_ready(server)
	crew[0].start()
	assert_bool(await h.until(func() -> bool: return server.world.tick > 3)).is_true()
	var w: SimWorld = server.world
	var at: Vector3 = Vector3(120000.0, -40000.5, 60000.03)
	w.add_site(_site("vesper", at, true), 1 << w.faction_of(PLAYER))
	var secret: int = w.add_site(_site("secret", Vector3(-100000, 0, 0)), 1 << w.faction_of(ENEMY))
	assert_bool(await h.until(func() -> bool: return helm.snap.sites.size() == 2)).is_true()
	var row: Dictionary = helm.snap.sites[1]
	assert_str(row["name_key"]).is_equal("site.vesper")
	assert_vector(row["pos"]).is_equal_approx(at, Vector3.ONE * (0.5 / NetCodec.POS_Q))
	assert_bool(row["dockable"]).is_true()
	w.sites.reveal(secret, w.faction_of(PLAYER))
	assert_bool(await h.until(func() -> bool: return helm.snap.sites.size() == 3)).is_true()
	assert_int(helm.snap.rejected).is_equal(0)


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
	assert_int(SnapshotReader.read_sites(_buffer(many)).size()).is_equal(SitesSection.MAX_ROWS)
	assert_array(section.update(w)).is_empty()
	# Rows are small: 16 bytes plus the key, so 32 rows stay near 800 bytes.
	assert_int(many.size()).is_less(1000)


func _buffer(data: PackedByteArray) -> StreamPeerBuffer:
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.data_array = data
	return b


# FT: FT-RLY-012
# gp-16: a site of the faction's pending encounter is marked pending only from
# site_marker_delay after the encounter opened, for that faction, and no longer once it
# starts; the flag survives the wire (SitesSection to SnapshotReader).
func test_a_pending_site_is_flagged_after_the_delay_until_it_starts() -> void:
	var server: NetServer = h.server()
	var w: SimWorld = server.world
	var faction: int = w.faction_of(PLAYER)
	var site: int = w.add_site(_site("vesper", Vector3(50000, 0, 0)), 1 << faction)
	var def: RelayMapDef = load("res://content/relay/relay_map.tres") as RelayMapDef
	var delay: int = SimRate.ticks(def.site_marker_delay)
	var row: int = w.encounters.add_encounter(PLAYER, faction, 0, site, 1, 0, w.tick - delay + 1)
	var section: SitesSection = SitesSection.new(faction)
	assert_bool(_pending_on_wire(section.update(w), site)).is_false()
	w.encounters.open_tick[row] = w.tick - delay
	assert_bool(_pending_on_wire(section.update(w), site)).is_true()
	assert_bool(SitesSection.pending_sites(w, w.faction_of(ENEMY)).has(site)).is_false()
	w.encounters.result[row] = EncounterTable.Result.ACTIVE
	assert_bool(_pending_on_wire(section.update(w), site)).is_false()


## Whether the decoded SITES bytes flag `site` pending.
func _pending_on_wire(bytes: PackedByteArray, site: int) -> bool:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.data_array = bytes
	for r: Dictionary in SnapshotReader.read_sites(buf):
		if r["id"] == site:
			return r["pending"]
	return false
