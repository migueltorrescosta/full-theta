extends GdUnitTestSuite
## The definition load gate (tools/check_defs.gd) on the fixtures in fixtures/: each
## error line names the file and the field.

const GATE: String = "res://tools/check_defs.gd"
const FIXTURES: String = "res://tests/content/fixtures/"
const DIR: String = "tests/content/fixtures/"


func _check(sub: String) -> Array[String]:
	var errors: Array[String] = []
	errors.assign((load(GATE) as GDScript).call("check_root", FIXTURES + sub))
	errors.sort()
	return errors


func _expect(sub: String, lines: Array[String]) -> void:
	var expected: Array[String] = []
	for line: String in lines:
		expected.append(DIR + sub + "/" + line)
	expected.sort()
	assert_array(_check(sub)).is_equal(expected)


# FT: FT-DAT-001, FT-DAT-002
func test_good_fixtures_pass() -> void:
	assert_array(_check("good")).is_empty()


# FT: FT-DAT-002
func test_wrong_types_name_file_and_field() -> void:
	_expect(
		"bad_type",
		[
			"enemy_wrong_class.tres: ship: expected ShipDef, got WeaponDef",
			"ship_mixed_types.tres: inertia: expected Vector3, got float 2000000.0",
			"ship_mixed_types.tres: mounts: element expected MountDef, got SubsystemDef",
			'ship_mixed_types.tres: sub_engines.health_max: expected float, got String "20 MJ"',
			'weapon_string_damage.tres: damage: expected float, got String "heavy"',
		]
	)


# FT: FT-DAT-002, FT-SIM-002
func test_out_of_range_values_name_file_and_field() -> void:
	_expect(
		"bad_range",
		[
			(
				"enemy_out_of_range.tres: engage_range_max: must be > engage_range_min (800.0), "
				+ "got 500.0"
			),
			"enemy_out_of_range.tres: retreat_hull_fraction: must be in (0, 1), got 1.0",
			"ship_out_of_range.tres: mass: must be > 0, got -1.0",
			(
				"ship_out_of_range.tres: mounts[0].subsystem_id: no subsystem with id "
				+ "no_such_subsystem"
			),
			"ship_out_of_range.tres: shields.low_alert_fraction: must be in (0.0, 1.0], got 1.5",
			"ship_out_of_range.tres: sub_engines.effectiveness: y must be in [0, 1] at point 1",
			"weapon_out_of_range.tres: ammo_capacity: must be >= 0 or -1 (unlimited), got -3",
			"weapon_out_of_range.tres: cooldown: must be > 0, got -0.5",
		]
	)


# FT: FT-DAT-002
func test_missing_references_name_file_and_field() -> void:
	_expect(
		"missing_ref",
		[
			(
				"enemy_missing_file.tres: ship: missing reference "
				+ "res://tests/content/fixtures/missing_ref/no_such_ship.tres"
			),
			"enemy_null_ship.tres: ship: required reference is missing",
			"ship_without_assist.tres: assist: required reference is missing",
		]
	)


# FT: FT-DAT-002
func test_gate_exits_1_on_errors_and_0_when_clean() -> void:
	var project: String = ProjectSettings.globalize_path("res://")
	var base: PackedStringArray = ["--headless", "--path", project, "-s", GATE, "--"]
	var out: Array = []
	var code: int = OS.execute(
		OS.get_executable_path(), base + PackedStringArray([FIXTURES + "bad_type"]), out
	)
	assert_int(code).is_equal(1)
	assert_str(out[0]).contains(DIR + "bad_type/weapon_string_damage.tres: damage: expected")
	code = OS.execute(OS.get_executable_path(), base + PackedStringArray([FIXTURES + "good"]), out)
	assert_int(code).is_equal(0)
