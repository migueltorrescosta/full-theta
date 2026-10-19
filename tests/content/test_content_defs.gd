extends GdUnitTestSuite
## The shipped definitions under res://content: they validate clean, the M1 ship, weapon
## and enemy exist, and every numeric field documents its SI unit.

const DEFS: String = "res://content/defs/"
## A unit in parentheses opening a field's doc comment, e.g. "(kg m^2)" or "(m/s".
const UNIT: String = "\\((kg|m|N|J|W|s|rad|K|count|dimensionless|1/s)\\b"
const NUMERIC: PackedStringArray = ["float", "int", "Vector3", "PackedVector2Array"]


# FT: FT-DAT-001, FT-DAT-002
func test_shipped_content_validates_clean() -> void:
	var errors: PackedStringArray = (load("res://tools/check_defs.gd") as GDScript).call(
		"check_root", "res://content"
	)
	assert_array(Array(errors)).is_empty()


# FT: FT-DAT-001, FT-SIM-002
func test_m1_ship_weapon_and_enemy_exist() -> void:
	var lib: DefLibrary = DefLibrary.new()
	assert_array(Array(lib.load_failures)).is_empty()
	var ship: ShipDef = lib.ship(&"m1_corvette")
	assert_object(ship).is_not_null()
	assert_float(ship.mass).is_equal(5.0e4)
	assert_vector(ship.inertia).is_equal(Vector3(2.0e6, 2.4e6, 1.2e6))
	assert_float(ship.max_thrust_neg.z).is_equal(1.0e6)
	assert_float(ship.max_thrust_pos.z).is_equal(5.0e5)
	assert_vector(ship.max_torque).is_equal(Vector3(3.0e6, 3.6e6, 3.0e6))
	assert_int(ship.subsystems.size()).is_equal(SubsystemDef.Kind.size())
	assert_int(ship.mounts.size()).is_greater_equal(1)
	var weapon: WeaponDef = lib.weapon(&"m1_cannon")
	assert_object(weapon).is_not_null()
	assert_object(ship.mounts[0].weapon).is_same(weapon)
	var enemy: EnemyDef = lib.enemy(&"m1_raider")
	assert_object(enemy).is_not_null()
	assert_object(enemy.ship).is_same(lib.ship(&"m1_raider"))


# FT: FT-DAT-013, FT-SIM-033
func test_every_numeric_field_documents_its_si_unit() -> void:
	var unit: RegEx = RegEx.create_from_string(UNIT)
	var export: RegEx = RegEx.create_from_string("^@export var (\\w+): (\\w+)")
	var missing: Array[String] = []
	var fields: int = 0
	for f: String in DirAccess.get_files_at(DEFS):
		if not f.ends_with("_def.gd"):
			continue
		var doc: String = ""
		for line: String in FileAccess.get_file_as_string(DEFS + f).split("\n"):
			var m: RegExMatch = export.search(line)
			if line.begins_with("##"):
				doc += line
			elif m != null:
				fields += 1
				if m.get_string(2) in NUMERIC and unit.search(doc) == null:
					missing.append("%s: %s" % [f, m.get_string(1)])
				doc = ""
			else:
				doc = ""
	assert_int(fields).is_greater(50)
	assert_array(missing).is_empty()
