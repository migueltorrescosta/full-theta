extends GdUnitTestSuite
## S3 spike: the toy Engineering model behind the web panel (pips within the
## reactor cap, heat; FT-ENG-002 in spirit, real model in T033).


func test_pips_clamp_to_range_and_cap() -> void:
	var m: S3EngineeringModel = S3EngineeringModel.new()
	assert_int(m.used()).is_equal(10)
	assert_int(m.set_pips(0, 9)).is_equal(4)
	assert_int(m.set_pips(1, 4)).is_equal(2)
	assert_int(m.used()).is_equal(S3EngineeringModel.REACTOR_CAP)
	assert_int(m.set_pips(2, -3)).is_equal(0)
	assert_int(m.set_pips(9, 1)).is_equal(-1)


func test_heat_rises_above_nominal_and_falls_below() -> void:
	var m: S3EngineeringModel = S3EngineeringModel.new()
	m.set_pips(0, 4)
	m.set_pips(1, 0)
	for i: int in range(60):
		m.step(1.0 / 60.0)
	assert_float(m.heat[0]).is_greater(0.2)
	assert_float(m.heat[1]).is_less(0.2)


func test_station_sim_puts_pips_and_heat_in_snapshots() -> void:
	var sim: S3StationSim = S3StationSim.new(2, 2, 4, 1)
	assert_dict(sim.seat_for(3)).is_equal({"ship": 1, "station": "engineering"})
	sim.set_pips(1, 0, 3)
	sim.step(1.0 / 60.0)
	var ship: Dictionary = sim.state()[1]
	assert_int((ship["pips"] as PackedInt32Array)[0]).is_equal(3)
	assert_int((ship["heat"] as PackedFloat32Array).size()).is_equal(5)
