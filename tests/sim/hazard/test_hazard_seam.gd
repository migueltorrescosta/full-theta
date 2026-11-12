extends GdUnitTestSuite
## R16-11 / R09-7 (b): a plane front and the minimum-image seam. A ship half a map period
## from the hazard's centre sees its signed distance flip from about +P/2 to -P/2 as it
## crosses the antipodal plane; that must not count as the front reaching it.

const HALF: float = 200000.0


func _plane(speed: float) -> HazardDef:
	var h: HazardDef = HazardDef.new()
	h.id = &"plane"
	h.kind = HazardDef.Kind.FRONT
	h.shape = HazardDef.Shape.PLANE
	h.direction = Vector3(0.0, 0.0, 1.0)
	h.speed = speed
	h.hit_energy = 5e6
	return h


func _world(z: float, vel_z: float, h: HazardDef) -> SimWorld:
	var w: SimWorld = SimWorld.new(1, "seam")
	w.spawn_ship(TestDefs.corvette(), 1, CubePoint.make(0.0, 0.0, z))
	w.kin.vel[0] = Vector3(0.0, 0.0, vel_z)
	w.hazards = [h]
	return w


# FT: FT-RLY-001, FT-SIM-035
# The ship crosses the antipodal plane (z = P/2) at 100 m/s while the front, at 10 m/s,
# is still ~200 km away: no hit.
func test_ship_crossing_the_antipodal_plane_is_not_hit() -> void:
	var w: SimWorld = _world(HALF - 150.0, 100.0, _plane(10.0))
	var events: Array[SimEvent] = SimFixture.run(w, 3 * SimWorld.HZ)
	# It really went through the seam: z wrapped to the other side.
	assert_float(w.kin.pos_z[0]).is_less(0.0)
	assert_int(SimFixture.of_kind(events, &"hazard_hit").size()).is_equal(0)
	assert_float(w.damage.health[w.damage.hull_row(0)]).is_equal(TestDefs.corvette().hull_max)


# FT: FT-RLY-001
# Regression: a ship 150 km ahead is still hit exactly once when the front gets there.
func test_front_still_hits_a_far_ship_once() -> void:
	var w: SimWorld = _world(150000.0, 0.0, _plane(5000.0))
	var events: Array[SimEvent] = SimFixture.run(w, 32 * SimWorld.HZ)
	var hits: Array[SimEvent] = SimFixture.of_kind(events, &"hazard_hit")
	assert_int(hits.size()).is_equal(1)
	assert_int(hits[0].tick).is_between(29 * SimWorld.HZ, 31 * SimWorld.HZ)
	assert_float(TestDefs.corvette().hull_max - w.damage.health[w.damage.hull_row(0)]).is_equal(5e6)
