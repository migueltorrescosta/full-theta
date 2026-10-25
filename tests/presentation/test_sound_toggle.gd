extends GdUnitTestSuite
## The top bar's sound on/off toggle (D200, FT-AUD-017).


func after_test() -> void:
	AudioServer.set_bus_mute(0, false)


# FT: FT-AUD-017
func test_the_toggle_mutes_and_unmutes_the_master_bus_and_names_its_state() -> void:
	var toggle: SoundToggle = auto_free(SoundToggle.new())
	assert_bool(toggle.is_on()).is_true()
	assert_str(toggle.text).is_equal(tr("topbar.sound_on"))
	toggle.button_pressed = false
	assert_bool(AudioServer.is_bus_mute(0)).is_true()
	assert_bool(toggle.is_on()).is_false()
	assert_str(toggle.text).is_equal(tr("topbar.sound_off"))
	toggle.button_pressed = true
	assert_bool(AudioServer.is_bus_mute(0)).is_false()


# FT: FT-AUD-017
func test_a_new_toggle_starts_in_the_buses_state() -> void:
	AudioServer.set_bus_mute(0, true)
	var toggle: SoundToggle = auto_free(SoundToggle.new())
	assert_bool(toggle.button_pressed).is_false()


# FT: FT-AUD-017
func test_the_top_bar_carries_the_toggle() -> void:
	var bar: TopBar = auto_free(TopBar.new())
	assert_object(bar.sound).is_not_null()
	assert_bool(bar.sound.get_parent() != null).is_true()
