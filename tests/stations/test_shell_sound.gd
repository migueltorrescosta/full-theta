extends GdUnitTestSuite
## ShellSound (#12, D312): sim events, refusals and button presses sound the right
## effects for the screen's stations, and the music follows the run and the setting.


func before_test() -> void:
	GameSounds.sounds_dir = MainMenu.SFX_SOUNDS
	MusicPlayer.music_dir = ""


func after_test() -> void:
	GameSounds.sounds_dir = ""


func _sound(stations: Array) -> ShellSound:
	var ctx: StationContext = StationFixture.context("weapons")
	var s: ShellSound = auto_free(ShellSound.new())
	add_child(s)
	s.setup(ctx)
	s.stations_of = func() -> Array: return stations
	return s


func _event(s: ShellSound, kind: StringName, ship: int) -> void:
	s.ctx.crew.handle_event(
		{"type": String(kind), "payload": {"ship": ship, "faction": 0, "other": -1}}, 0
	)


# FT: FT-AUD-023
func test_weapons_hears_its_own_shots_and_a_refusal_sounds_the_error_clip() -> void:
	var s: ShellSound = _sound(["weapons"])
	_event(s, &"fired", StationFixture.SHIP)
	_event(s, &"fired", StationFixture.SHIP + 1)
	_event(s, &"destroyed", StationFixture.SHIP + 1)
	assert_array(s.sfx.played).is_equal([&"fire", &"explosion"])
	s.on_toast("toast.takeover", {})
	assert_int(s.sfx.played.size()).is_equal(2)
	s.on_toast("toast.claimed", {})
	assert_str(s.sfx.played[-1]).is_equal("ui_error")


# FT: FT-AUD-023
func test_a_screen_without_weapons_does_not_hear_the_shots() -> void:
	var s: ShellSound = _sound(["helm"])
	_event(s, &"fired", StationFixture.SHIP)
	assert_array(s.sfx.played).is_empty()


# FT: FT-AUD-023
func test_a_button_added_later_taps_once() -> void:
	var s: ShellSound = _sound(["helm"])
	var b: Button = auto_free(Button.new())
	add_child(b)
	b.pressed.emit()
	assert_array(s.sfx.played).is_equal([&"ui_tap"])


# FT: FT-AUD-024
func test_the_music_follows_the_setting_the_run_and_the_voice() -> void:
	var s: ShellSound = _sound(["helm"])
	s.ctx.settings.music_volume = 0.2
	s.voice_playing = func() -> bool: return true
	s._process(0.0)
	assert_float(s.music.volume).is_equal(0.2)
	assert_bool(s.music.voice_active).is_true()
	assert_bool(s.music.is_playing()).is_true()
	s.ctx.crew.ship_outcome[s.ctx.crew.ship] = {}
	s._process(0.0)
	assert_bool(s.music.is_playing()).is_false()
