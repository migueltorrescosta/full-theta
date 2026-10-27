extends GdUnitTestSuite
## The jump drive (FT-SIM-034, FT-HLM-016, D229): fast travel inside the one cube to a named
## site or a free mark, after a data-defined spool, arriving a data-defined stand-off short
## of the target and at rest relative to it, for a propellant cost; refused unless Helm
## faces the target. M3 map: site 0 Kestrel Yard at the origin, Vesper Beacon 134 km away.

const CORVETTE: int = 0


func _vesper(w: SimWorld) -> int:
	return SiteFixture.id_of(w, &"vesper_beacon")


# FT: FT-SIM-034, FT-MIS-026
# The jump spools for ShipDef.jump_spool_s (8 s, 480 ticks) and the ship stays where it
# is until then; it arrives the 480th step, jump_left counts down in between.
func test_spool_takes_the_data_defined_time() -> void:
	var w: SimWorld = SiteFixture.world()
	var vesper: int = _vesper(w)
	var ship: int = SiteFixture.corvette_facing(w, Vector3.ZERO, w.sites.point3(vesper))
	SiteFixture.jump_to_site(w, ship, vesper)
	var ticks: int = ceili(TestDefs.corvette().jump_spool_s * SimWorld.HZ)
	assert_int(ticks).is_equal(480)
	var at: int = SiteFixture.steps_until(w, &"jump_arrive", ship, 600)
	assert_int(at).is_equal(ticks)
	assert_int(w.helm.jump_left[ship]).is_equal(0)


# FT: FT-SIM-034
# Mid-spool the ship has not moved and reports the spool left; the spool event carries the
# target site and the site the ship leaves.
func test_spool_event_and_state() -> void:
	var w: SimWorld = SiteFixture.world()
	var vesper: int = _vesper(w)
	var ship: int = SiteFixture.corvette_facing(w, Vector3.ZERO, w.sites.point3(vesper))
	SiteFixture.jump_to_site(w, ship, vesper)
	w.step()
	var spool: Array[SimEvent] = SiteFixture.events_of(w, &"jump_spool")
	assert_int(spool.size()).is_equal(1)
	assert_float(spool[0].value).is_equal(float(vesper))
	assert_str(String(spool[0].tag)).is_equal("0")
	assert_int(w.helm.jump_left[ship]).is_equal(479)
	for i: int in 100:
		w.step()
	assert_float(w.kin.relative_to_point(ship, 0.0, 0.0, 0.0).length()).is_less(1.0)


# FT: FT-SIM-034, FT-MIS-026
# The ship arrives jump_standoff_m short of a site on the line from where it was, in the
# same cube, at rest, and the jump took jump_propellant_kg.
func test_arrives_at_the_standoff_from_a_site() -> void:
	var w: SimWorld = SiteFixture.world()
	var vesper: int = _vesper(w)
	var def: ShipDef = TestDefs.corvette()
	var ship: int = SiteFixture.corvette_facing(w, Vector3.ZERO, w.sites.point3(vesper))
	w.kin.vel[ship] = Vector3(3.0, 0.0, 0.0)
	var fuel: float = w.kin.propellant[ship]
	SiteFixture.jump_to_site(w, ship, vesper)
	var from: Vector3 = Vector3.ZERO
	var line: Vector3 = w.sites.point3(vesper) - from
	SiteFixture.steps_until(w, &"jump_arrive", ship, 600)
	var left: Vector3 = SiteTable.offset_to(w, ship, vesper)
	assert_float(left.length()).is_equal_approx(def.jump_standoff_m, 0.5)
	assert_float(left.normalized().dot(line.normalized())).is_greater(0.99999)
	assert_float(w.kin.vel[ship].length()).is_equal(0.0)
	# The jump's own propellant plus the little the assist burns holding the bow meanwhile.
	assert_float(fuel - w.kin.propellant[ship]).is_between(
		def.jump_propellant_kg, def.jump_propellant_kg + 5.0
	)
	assert_float(w.kin.propellant_used[ship]).is_greater_equal(def.jump_propellant_kg)
	assert_float(w.kin.period).is_equal(400000.0)
	assert_float(absf(w.kin.px[ship])).is_less(200000.0)
	var arrive: Array[SimEvent] = SiteFixture.events_of(w, &"jump_arrive")
	assert_int(arrive.size()).is_equal(1)
	assert_float(arrive[0].value).is_equal(float(vesper))
	assert_str(String(arrive[0].tag)).is_equal("0")
	# The standoff (2 km) is inside the site's radius (3 km): the ship is at the site.
	assert_int(SiteTable.at_site(w, ship)).is_equal(vesper)


# FT: FT-SIM-034
# A free mark works the same: the stand-off from the point, tag -1 (outside every site)
# when the jump starts in open space, value -1.
func test_arrives_at_the_standoff_from_a_mark() -> void:
	var w: SimWorld = SiteFixture.world()
	var start: Vector3 = Vector3(50000.0, 20000.0, 0.0)
	var mark: Vector3 = Vector3(50000.0, 20000.0, -60000.0)
	var ship: int = SiteFixture.corvette_facing(w, start, mark)
	SiteFixture.jump_to_mark(w, ship, mark)
	SiteFixture.steps_until(w, &"jump_arrive", ship, 600)
	var left: Vector3 = w.kin.relative_to_point(ship, mark.x, mark.y, mark.z)
	assert_float(left.length()).is_equal_approx(TestDefs.corvette().jump_standoff_m, 0.5)
	var arrive: Array[SimEvent] = SiteFixture.events_of(w, &"jump_arrive")
	assert_float(arrive[0].value).is_equal(-1.0)
	assert_str(String(arrive[0].tag)).is_equal("-1")


# FT: FT-SIM-034, FT-SIM-035
# The jump follows the minimum image across the cube's seam: from near the +X face to a
# mark just past the -X face it is a short hop, and the ship ends inside [-P/2, P/2).
func test_jump_across_the_seam() -> void:
	var w: SimWorld = SiteFixture.world()
	var start: Vector3 = Vector3(199000.0, 0.0, 0.0)
	var mark: Vector3 = Vector3(-196000.0, 0.0, 0.0)
	var ship: int = SiteFixture.corvette_facing(w, start, mark)
	assert_float(w.kin.relative_to_point(ship, mark.x, mark.y, mark.z).x).is_equal(5000.0)
	SiteFixture.jump_to_mark(w, ship, mark)
	SiteFixture.steps_until(w, &"jump_arrive", ship, 600)
	var left: Vector3 = w.kin.relative_to_point(ship, mark.x, mark.y, mark.z)
	assert_float(left.length()).is_equal_approx(TestDefs.corvette().jump_standoff_m, 0.5)
	assert_float(w.kin.px[ship]).is_between(-200000.0, 200000.0)


# FT: FT-SIM-034
# A target already inside the stand-off leaves the ship where it is (it only stops).
func test_jump_to_a_nearby_target_does_not_back_off() -> void:
	var w: SimWorld = SiteFixture.world()
	var mark: Vector3 = Vector3(0.0, 0.0, -1200.0)
	var ship: int = SiteFixture.corvette_facing(w, Vector3.ZERO, mark)
	SiteFixture.jump_to_mark(w, ship, mark)
	SiteFixture.steps_until(w, &"jump_arrive", ship, 600)
	assert_float(w.kin.relative_to_point(ship, 0.0, 0.0, 0.0).length()).is_less(1e-6)


# FT: FT-HLM-016, FT-SIM-034
# Refused unless Helm faces the target within ShipDef.jump_face_tolerance_rad (0.1 rad): a
# bow 20 degrees off is refused with no propellant taken and no spool; 3 degrees off goes.
func test_refused_unless_faced() -> void:
	var w: SimWorld = SiteFixture.world()
	var vesper: int = _vesper(w)
	var ship: int = SiteFixture.corvette_facing(w, Vector3.ZERO, w.sites.point3(vesper))
	var fuel: float = w.kin.propellant[ship]
	var aim: Quaternion = w.kin.rot[ship]
	w.kin.rot[ship] = aim * Quaternion(Vector3.UP, deg_to_rad(20.0))
	var c: JumpCommand = SiteFixture.jump_to_site(w, ship, vesper)
	w.step()
	assert_bool(c.accepted).is_false()
	assert_int(w.helm.jump_left[ship]).is_equal(0)
	assert_float(w.kin.propellant[ship]).is_equal(fuel)
	assert_int(SiteFixture.events_of(w, &"jump_spool").size()).is_equal(0)
	w.kin.rot[ship] = aim * Quaternion(Vector3.UP, deg_to_rad(3.0))
	var ok: JumpCommand = SiteFixture.jump_to_site(w, ship, vesper)
	w.step()
	assert_bool(ok.accepted).is_true()


# FT: FT-SIM-034
# Other refusals: a ship with no jump drive (the raider), a site the faction doesn't know,
# an unknown site id, a non-finite mark, too little propellant, a second jump while one
# spools.
func test_refusals() -> void:
	var w: SimWorld = SiteFixture.world()
	var vesper: int = _vesper(w)
	var ship: int = SiteFixture.corvette_facing(w, Vector3.ZERO, w.sites.point3(vesper))
	var raider: int = w.spawn_ship(TestDefs.raider(), 2, Vector3(0, 0, 3000))
	SiteFixture.face(w, raider, w.sites.point3(vesper))
	var no_drive: JumpCommand = SiteFixture.jump_to_site(w, raider, vesper)
	var unknown_id: JumpCommand = SiteFixture.jump_to_site(w, ship, 99)
	var nan_mark: JumpCommand = SiteFixture.jump_to_mark(w, ship, Vector3(NAN, 0, 0))
	w.sites.known_mask[vesper] = 0
	var hidden: JumpCommand = SiteFixture.jump_to_site(w, ship, vesper)
	w.step()
	for c: JumpCommand in [no_drive, unknown_id, nan_mark, hidden]:
		assert_bool(c.accepted).is_false()
	w.sites.reveal(vesper, SiteFixture.SHIP_FACTION)
	w.kin.propellant[ship] = 100.0
	var dry: JumpCommand = SiteFixture.jump_to_site(w, ship, vesper)
	w.step()
	assert_bool(dry.accepted).is_false()
	w.kin.propellant[ship] = 5000.0
	var first: JumpCommand = SiteFixture.jump_to_site(w, ship, vesper)
	var second: JumpCommand = SiteFixture.jump_to_site(w, ship, vesper)
	w.step()
	assert_bool(first.accepted).is_true()
	assert_bool(second.accepted).is_false()


# FT: FT-SIM-034
# Commands round-trip through the command log codec (replays reproduce a jump).
func test_commands_round_trip_the_log_codec() -> void:
	var c: JumpCommand = JumpCommand.new()
	c.ship_id = 0
	c.target_kind = HelmTable.JumpKind.MARK
	c.x = 12.5
	var back: JumpCommand = SimCommands.from_dict(c.to_dict()) as JumpCommand
	assert_object(back).is_not_null()
	assert_int(back.target_kind).is_equal(HelmTable.JumpKind.MARK)
	assert_float(back.x).is_equal(12.5)
	assert_object(SimCommands.make(&"helm_dock")).is_not_null()
	assert_object(SimCommands.make(&"helm_undock")).is_not_null()
