extends GdUnitTestSuite
## Rebinding flags a binding another intent of the same station already has (D5, R25-10);
## the same capture again accepts it.

const PATH: String = "user://test_settings_same_station.cfg"


func before() -> void:
	I18n.apply("en")


func _k(code: Key) -> InputEventKey:
	var k: InputEventKey = InputEventKey.new()
	k.physical_keycode = code
	k.pressed = true
	return k


# FT: FT-STN-007
func test_same_station_finds_a_twin_but_not_other_stations_or_the_pointer_case() -> void:
	var b: Bindings = Bindings.new()
	assert_str(SettingsScreen.same_station(b, "ammo_next", "kbm", "1")).is_equal("mount_1")
	assert_str(SettingsScreen.same_station(b, "ammo_next", "kbm", "G")).is_equal("fire_guided")
	# "H" is Engineering's and Science's too, other stations: only one is in play.
	assert_str(SettingsScreen.same_station(b, "mount_2", "kbm", "1")).is_equal("mount_1")
	assert_str(SettingsScreen.same_station(b, "ammo_next", "kbm", "H")).is_empty()
	# Select and fire share the left button (D176); common and live intents are collisions.
	assert_str(SettingsScreen.same_station(b, "fire", "kbm", "LMB")).is_empty()
	assert_str(SettingsScreen.same_station(b, "select", "kbm", "T")).is_empty()
	assert_str(SettingsScreen.same_station(b, "ammo_next", "kbm", "Q")).is_empty()


# FT: FT-STN-007
func test_the_first_capture_warns_and_the_second_binds() -> void:
	var s: ClientSettings = ClientSettings.new(PATH)
	var screen: SettingsScreen = auto_free(SettingsScreen.new())
	screen.setup(s, true)
	add_child(screen)
	screen.start_capture("ammo_next", "kbm")
	screen._input(_k(KEY_G))
	assert_array(Array(s.bindings.bindings("ammo_next", "kbm"))).is_equal(["Q"])
	assert_str(screen.warning.text).is_equal(tr("settings.same_station") % tr("intent.fire_guided"))
	assert_array(screen.capturing).is_not_empty()
	screen._input(_k(KEY_G))
	assert_array(Array(s.bindings.bindings("ammo_next", "kbm"))).is_equal(["G"])
	assert_array(screen.capturing).is_empty()
