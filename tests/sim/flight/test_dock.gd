extends GdUnitTestSuite
## Docking (FT-HLM-013, D229): a dockable site docks a ship within dock_range_m of its
## point and at or under dock_max_speed; a docked ship is held at the point until it
## undocks. M3 map: Kestrel Yard (site 0, origin) and Anchorage Nine are stations, Vesper
## Beacon is not dockable.

const YARD_RANGE: float = 1500.0
const YARD_SPEED: float = 10.0


# FT: FT-HLM-013
# Within range and under the speed limit the ship docks, is held at the site's point at
# rest, and the dock event names the site.
func test_dock_holds_the_ship_at_the_point() -> void:
	var w: SimWorld = SiteFixture.world()
	var ship: int = SiteFixture.corvette_facing(w, Vector3(1000.0, 0.0, 0.0), Vector3(0, 0, -9))
	w.kin.vel[ship] = Vector3(5.0, 0.0, 0.0)
	var c: DockCommand = SiteFixture.dock(w, ship, 0)
	w.step()
	assert_bool(c.accepted).is_true()
	assert_int(w.helm.docked_site[ship]).is_equal(0)
	assert_int(SiteFixture.events_of(w, &"docked").size()).is_equal(1)
	# Even with thrust commanded, a docked ship stays put.
	SiteFixture.input_throttle(w, ship, 1.0)
	for i: int in 120:
		w.step()
	assert_float(w.kin.relative_to_point(ship, 0.0, 0.0, 0.0).length()).is_less(1e-6)
	assert_float(w.kin.vel[ship].length()).is_equal(0.0)


# FT: FT-HLM-013
# Too far, too fast, a site that can't be docked at, an unknown site, a site the faction
# doesn't know and an already docked ship are all refused.
func test_dock_refusals() -> void:
	var w: SimWorld = SiteFixture.world()
	var vesper: int = SiteFixture.id_of(w, &"vesper_beacon")
	var far: int = SiteFixture.corvette_facing(w, Vector3(YARD_RANGE + 50.0, 0, 0), Vector3.ZERO)
	var fast: int = SiteFixture.corvette_facing(w, Vector3(0, 100.0, 0), Vector3(0, 0, -9))
	w.kin.vel[fast] = Vector3(YARD_SPEED + 1.0, 0.0, 0.0)
	var at_vesper: int = SiteFixture.corvette_facing(w, w.sites.point3(vesper), Vector3(0, 0, -9))
	var cmds: Array[DockCommand] = [
		SiteFixture.dock(w, far, 0),
		SiteFixture.dock(w, fast, 0),
		SiteFixture.dock(w, at_vesper, vesper),
		SiteFixture.dock(w, fast, 77),
	]
	w.step()
	for c: DockCommand in cmds:
		assert_bool(c.accepted).is_false()
	w.sites.known_mask[0] = 0
	var hidden: DockCommand = SiteFixture.dock(w, fast, 0)
	w.kin.vel[fast] = Vector3.ZERO
	w.step()
	assert_bool(hidden.accepted).is_false()
	w.sites.reveal(0, SiteFixture.SHIP_FACTION)
	var ok: DockCommand = SiteFixture.dock(w, fast, 0)
	var again: DockCommand = SiteFixture.dock(w, fast, 0)
	w.step()
	assert_bool(ok.accepted).is_true()
	assert_bool(again.accepted).is_false()


# FT: FT-HLM-013
# Undock frees the ship (it stays at the point, at rest); undocking when free is refused.
# A docked ship can't jump, and a spooling ship can't dock.
func test_undock_and_the_jump_dock_exclusion() -> void:
	var w: SimWorld = SiteFixture.world()
	var vesper: int = SiteFixture.id_of(w, &"vesper_beacon")
	var ship: int = SiteFixture.corvette_facing(w, Vector3(100.0, 0, 0), w.sites.point3(vesper))
	var loose: UndockCommand = SiteFixture.undock(w, ship)
	SiteFixture.dock(w, ship, 0)
	w.step()
	assert_bool(loose.accepted).is_false()
	assert_int(w.helm.docked_site[ship]).is_equal(0)
	SiteFixture.face(w, ship, w.sites.point3(vesper))
	var jump: JumpCommand = SiteFixture.jump_to_site(w, ship, vesper)
	w.step()
	assert_bool(jump.accepted).is_false()
	var off: UndockCommand = SiteFixture.undock(w, ship)
	w.step()
	assert_bool(off.accepted).is_true()
	assert_int(w.helm.docked_site[ship]).is_equal(-1)
	assert_int(SiteFixture.events_of(w, &"undocked").size()).is_equal(1)
	SiteFixture.face(w, ship, w.sites.point3(vesper))
	var go: JumpCommand = SiteFixture.jump_to_site(w, ship, vesper)
	var dock_now: DockCommand = SiteFixture.dock(w, ship, 0)
	w.step()
	assert_bool(go.accepted).is_true()
	assert_bool(dock_now.accepted).is_false()
