extends GdUnitTestSuite
## D229, D230: a scenario's map is one wrapping cube and positions are plain 64-bit
## offsets in it, with no space id.

const CORVETTE_FACTION: int = 1
const RAIDER_FACTION: int = 2


# FT: FT-SIM-035
# Kinematics keeps three 64-bit position columns and no site column, and the default
# period is 400 km.
func test_kinematics_has_no_site_column() -> void:
	var names: Array[String] = []
	for col: Array in Kinematics.new().columns():
		names.append(col[0])
	assert_array(names).contains(["px", "py", "pz"])
	assert_array(names).not_contains(["site"])
	assert_float(Kinematics.DEFAULT_PERIOD).is_equal(400000.0)
	assert_float(SimWorld.new(1).kin.period).is_equal(400000.0)


# FT: FT-SIM-035, FT-SIM-034
# Two ships 300 km apart in the 400 km cube are 100 km apart by minimum image: they sense
# each other (the corvette's sensors reach 20 km) only once they are closer than that
# through the seam, and relative() takes the short way round.
func test_ships_interact_by_minimum_image() -> void:
	var w: SimWorld = SimWorld.new(1)
	var blue: int = w.spawn_ship(TestDefs.corvette(), CORVETTE_FACTION, Vector3(-150000.0, 0, 0))
	var red: int = w.spawn_ship(TestDefs.raider(), RAIDER_FACTION, Vector3(150000.0, 0, 0))
	assert_float(w.kin.relative(blue, red).x).is_equal(-100000.0)
	assert_bool(w.kin.can_reach(blue, red)).is_true()
	w.step()
	assert_bool(KnowledgeSystem.is_detected(w, CORVETTE_FACTION, red)).is_false()
	# 12 km apart through the seam: far in coordinates (300 km), close by minimum image.
	w.kin.place(blue, -194000.0, 0.0, 0.0)
	w.kin.place(red, 194000.0, 0.0, 0.0)
	assert_float(w.kin.relative(blue, red).length()).is_equal_approx(12000.0, 1e-3)
	w.step()
	assert_bool(KnowledgeSystem.is_detected(w, CORVETTE_FACTION, red)).is_true()
	assert_int(w.kin.nearest(blue, PackedInt32Array([red]))).is_equal(red)
