extends GdUnitTestSuite
## D208 on the wire: the RELAY block lists the sim hazards the faction knows (HazardView),
## to Relay always and to another station through the hazard-countdown toggle, with the
## forecast Engineering's countdown reads.

const ME: int = 0

var world: SimWorld


func before_test() -> void:
	world = SimWorld.new(3)
	world.spawn_ship(TestDefs.corvette(), 1, 0)
	var wave: HazardDef = load("res://content/hazards/p11_radiation_wave.tres") as HazardDef
	var cloud: HazardDef = load("res://content/hazards/p4_dust_cloud.tres") as HazardDef
	world.hazards = [wave, cloud]
	world.step()


func _hazards(entry: String, code: String) -> Array:
	var b: SnapshotBuilder = SnapshotBuilder.new()
	var key: String = StationViews.key(ME, entry, code)
	b.build(SimCopy.of(world), 1, [key])
	var view: NetViewState = NetViewState.new(NetCodec.period_units(world.kin.period))
	assert_bool(view.apply(b.message(key, true))).is_true()
	return view.blocks[StationViews.Section.RELAY]["hazards"]


# FT: FT-RLY-001, FT-PAIR-015
# Only the hazards the faction knows are listed: the dust cloud (its surface is 2 km out,
# the sensors reach 5 km) and not the wave (12 km out, 1 km sensors) until a probe covers it.
func test_the_block_lists_known_hazards_with_their_geometry() -> void:
	var rows: Array = _hazards("relay", "easy")
	assert_int(rows.size()).is_equal(1)
	assert_int(rows[0]["id"]).is_equal(1)
	assert_int(rows[0]["shape"]).is_equal(HazardView.ZONE)
	assert_vector(rows[0]["pos"]).is_equal(Vector3(0.0, 0.0, -4000.0))
	assert_float(rows[0]["radius"]).is_equal(2000.0)
	# At rest, it is not coming.
	assert_float(rows[0]["eta"]).is_equal(-1.0)
	var launch: LaunchProbeCommand = LaunchProbeCommand.new()
	launch.ship_id = ME
	launch.z = -6000.0
	world.submit(launch)
	SimFixture.run(world, 13 * SimWorld.HZ)
	rows = _hazards("relay", "easy")
	assert_int(rows.size()).is_equal(2)
	var wave: Dictionary = rows[0]
	assert_int(wave["shape"]).is_equal(HazardView.PLANE)
	assert_vector(wave["dir"]).is_equal(Vector3(0.0, 0.0, 1.0))
	# The wave is at 200 m/s from 12 km: the block's forecast is the time left.
	var left: float = 60.0 - world.tick * SimWorld.DT
	assert_float(wave["eta"]).is_equal_approx(left, 0.05)
	# Its nearest point is on the ship's line, where the surface is now.
	var z: float = -12000.0 + 200.0 * world.tick * SimWorld.DT
	assert_float((wave["pos"] as Vector3).z).is_equal_approx(z, 0.5)


# FT: FT-PAIR-007, FT-PAIR-020
# Relay's hazards reach another station through the countdown toggle only: Engineering has
# them on Easy and Normal and not on Hard; Relay keeps them on Hard; a Helm + Relay view
# holds the source.
func test_other_stations_get_the_hazards_by_toggle() -> void:
	assert_int(_hazards("engineering", "easy").size()).is_equal(1)
	assert_int(_hazards("engineering", "normal").size()).is_equal(1)
	assert_array(_hazards("engineering", "hard")).is_empty()
	assert_int(_hazards("relay", "hard").size()).is_equal(1)
	assert_int(_hazards("nav", "hard").size()).is_equal(1)


# FT: FT-ENG-008
# The countdown takes the soonest forecast; a row with no forecast is none.
func test_countdown_takes_the_soonest_forecast() -> void:
	assert_float(HazardEta.forecast([{"eta": -1.0}, {"eta": 30.0}, {"eta": 12.5}])).is_equal(12.5)
	assert_float(HazardEta.forecast([{"eta": -1.0}])).is_equal(-1.0)
	assert_float(HazardEta.forecast([])).is_equal(-1.0)
	assert_float(HazardEta.sooner(-1.0, 4.0)).is_equal(4.0)
	assert_float(HazardEta.sooner(9.0, -1.0)).is_equal(9.0)
	assert_float(HazardEta.sooner(9.0, 4.0)).is_equal(4.0)
