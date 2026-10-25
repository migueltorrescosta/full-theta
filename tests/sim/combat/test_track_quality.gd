extends GdUnitTestSuite
## D214: a track has a quality from its source, own sensors by range and noise and a probe by
## distance from the probe; guided ordnance turns harder on a better track.

const MISSILE: String = "res://content/weapons/m2_missile.tres"
const ME: int = 0
const FOE: int = 1


## [world]: the M1 corvette with a missile mount, the raider `range_m` ahead and `side_m` to
## the right, after a step so the corvette has detected it. Sensors 20 km.
func _world(range_m: float, side_m: float = 0.0, science: bool = true) -> SimWorld:
	var ship: ShipDef = TestDefs.corvette().duplicate()
	var mount: MountDef = ship.mounts[0].duplicate()
	mount.weapon = load(MISSILE) as WeaponDef
	var mounts: Array[MountDef] = [mount]
	ship.mounts = mounts
	var w: SimWorld = SimWorld.new(5)
	if science:
		w.science_def = ScienceFixture.science()
	w.spawn_ship(ship, 1, 0)
	w.spawn_ship(TestDefs.raider(), 2, 0, Vector3(side_m, 0.0, -range_m))
	w.step()
	w.drain_events()
	return w


# FT: FT-WPN-007, FT-WPN-008
# Own sensors: the closer the contact, the better the track; none for a contact that isn't
# tracked, always full for the faction's own ships.
func test_own_sensor_quality_falls_with_range() -> void:
	var near: float = GuidanceSystem.track_quality(_world(3000.0), 1, FOE)
	var mid: float = GuidanceSystem.track_quality(_world(12000.0), 1, FOE)
	var far: float = GuidanceSystem.track_quality(_world(19000.0), 1, FOE)
	assert_float(near).is_greater(mid)
	assert_float(mid).is_greater(far)
	assert_float(far).is_greater_equal(GuidanceSystem.MIN_QUALITY)
	assert_float(near).is_less_equal(1.0)
	assert_float(GuidanceSystem.track_quality(_world(50000.0), 1, FOE)).is_equal(0.0)
	assert_float(GuidanceSystem.track_quality(_world(3000.0), 1, ME)).is_equal(1.0)
	# The scan noise cuts it: the same range with active sensors (less noise) is better.
	var quiet: SimWorld = _world(12000.0)
	quiet.science.active[ME] = 1
	assert_float(GuidanceSystem.track_quality(quiet, 1, FOE)).is_greater(mid)


# FT: FT-WPN-007, FT-RLY-004
# A probe tracks a contact beyond the sensors by the distance from the probe: a probe on it
# is a near-perfect track, one at the edge of its bubble a poor one.
func test_probe_quality_falls_with_distance_from_the_probe() -> void:
	var qualities: Array[float] = []
	for probe_z: float in [-29900.0, -26000.0, -22500.0]:
		var w: SimWorld = _world(30000.0)
		var row: int = w.probes.launch(
			ME, 1, 0, 0, Vector3(0.0, 0.0, probe_z), Vector3(0.0, 0.0, probe_z)
		)
		w.probes.deployed[row] = 1
		qualities.append(GuidanceSystem.track_quality(w, 1, FOE))
	assert_float(qualities[0]).is_greater(0.95)
	assert_float(qualities[0]).is_greater(qualities[1])
	assert_float(qualities[1]).is_greater(qualities[2])
	assert_float(qualities[2]).is_greater(0.0)


# FT: FT-WPN-007, FT-SIM-013
# The same missile turns less on a worse track: with the sensors hurt (a shorter reach) the
# contact is the same distance away but the quality, and so the turn, is lower.
func test_a_better_track_steers_harder() -> void:
	var turned: Array[float] = []
	for health: float in [1.0, 0.25]:
		var w: SimWorld = _world(3000.0, 600.0)
		var row: int = w.damage.find_subsystem(ME, &"sensors")
		w.damage.health[row] *= health
		var fire: FireGuidedCommand = FireGuidedCommand.new()
		fire.ship_id = ME
		fire.target = FOE
		w.submit(fire)
		SimFixture.run(w, 20)
		assert_int(w.projectiles.size()).is_equal(1)
		turned.append(w.projectiles.vel[0].x)
		assert_bool(fire.accepted).is_true()
	assert_float(turned[0]).is_greater(turned[1] * 1.1)
	assert_float(turned[1]).is_greater(0.0)


# FT: FT-WPN-007
# Weapons' track feed (FEEDS) carries the same quality, and whether a deployed probe
# covers the contact.
func test_the_track_feed_shows_the_quality() -> void:
	var w: SimWorld = _world(12000.0)
	var feed: Dictionary = FeedsView.block(w, ME)
	assert_int(feed["tracks"].size()).is_equal(1)
	assert_int(feed["tracks"][0]["contact"]).is_equal(FOE)
	assert_float(feed["tracks"][0]["quality"]).is_equal(GuidanceSystem.track_quality(w, 1, FOE))
	assert_bool(feed["tracks"][0]["probe"]).is_false()
	var row: int = w.probes.launch(ME, 1, 0, 0, Vector3(0.0, 0.0, -11000.0), Vector3.ZERO)
	w.probes.deployed[row] = 1
	var probed: Dictionary = FeedsView.block(w, ME)["tracks"][0]
	assert_bool(probed["probe"]).is_true()
	assert_float(probed["quality"]).is_greater(feed["tracks"][0]["quality"])
