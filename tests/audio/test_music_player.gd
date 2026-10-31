extends GdUnitTestSuite
## The ambient music's ducking and level (FT-AUD-021, D3xx): the bus level drops while a
## voice line plays and recovers after it, and the setting scales it. No audio output
## is needed: the player's level is a pure function of its state.


func _player() -> MusicPlayer:
	var p: MusicPlayer = auto_free(MusicPlayer.new())
	add_child(p)
	return p


# FT: FT-AUD-021
func test_the_music_bus_ducks_while_a_voice_plays_and_recovers_after() -> void:
	var p: MusicPlayer = _player()
	p.volume = 1.0
	var full: float = p.bus_db()
	assert_float(full).is_equal_approx(MusicPlayer.FULL_DB, 0.001)
	p.voice_active = true
	p.advance(MusicPlayer.ATTACK_S)
	assert_float(p.bus_db()).is_equal_approx(full + MusicPlayer.DUCK_DB, 0.001)
	var index: int = AudioServer.get_bus_index(MusicPlayer.BUS)
	assert_float(AudioServer.get_bus_volume_db(index)).is_equal_approx(
		full + MusicPlayer.DUCK_DB, 0.001
	)
	# It stays down through the hold, then rises over the release time.
	p.voice_active = false
	p.advance(MusicPlayer.HOLD_S * 0.5)
	assert_float(p.bus_db()).is_equal_approx(full + MusicPlayer.DUCK_DB, 0.001)
	p.advance(MusicPlayer.HOLD_S * 0.5)
	assert_float(p.bus_db()).is_greater(full + MusicPlayer.DUCK_DB)
	assert_float(p.bus_db()).is_less(full)
	p.advance(MusicPlayer.RELEASE_S)
	assert_float(p.bus_db()).is_equal_approx(full, 0.001)


# FT: FT-AUD-021
func test_a_gap_between_two_voice_lines_does_not_let_the_music_back_up() -> void:
	var p: MusicPlayer = _player()
	p.volume = 1.0
	p.voice_active = true
	p.advance(1.0)
	p.voice_active = false
	p.advance(MusicPlayer.HOLD_S * 0.8)
	p.voice_active = true
	p.advance(0.1)
	assert_float(p.duck).is_equal(1.0)


# FT: FT-AUD-021
func test_the_volume_scales_the_level_and_zero_mutes_the_bus() -> void:
	var p: MusicPlayer = _player()
	p.volume = 0.5
	p.advance(0.0)
	assert_float(p.bus_db()).is_equal_approx(MusicPlayer.FULL_DB - 6.0206, 0.01)
	var index: int = AudioServer.get_bus_index(MusicPlayer.BUS)
	assert_bool(AudioServer.is_bus_mute(index)).is_false()
	p.volume = 0.0
	p.advance(0.0)
	assert_float(p.bus_db()).is_equal(MusicPlayer.SILENT_DB)
	assert_bool(AudioServer.is_bus_mute(index)).is_true()
	p.volume = 0.5
	p.advance(0.0)
	assert_bool(AudioServer.is_bus_mute(index)).is_false()


# FT: FT-AUD-021
func test_the_music_bus_sends_to_master_and_every_track_is_a_shipped_ogg() -> void:
	_player()
	var index: int = AudioServer.get_bus_index(MusicPlayer.BUS)
	assert_int(index).is_greater_equal(0)
	assert_str(String(AudioServer.get_bus_send(index))).is_equal("Master")
	for t: String in MusicPlayer.TRACKS:
		var stream: AudioStream = load(MainMenu.MUSIC_TRACKS.path_join(t + ".ogg")) as AudioStream
		assert_object(stream).is_not_null()
		assert_float(stream.get_length()).is_greater(60.0)


# FT: FT-AUD-021
func test_the_tracks_play_in_turn_while_a_run_is_on() -> void:
	MusicPlayer.music_dir = MainMenu.MUSIC_TRACKS
	var p: MusicPlayer = _player()
	assert_bool(p.is_playing()).is_false()
	p.set_playing(true)
	assert_bool(p.get_node("Track").playing).is_true()
	p._next()
	assert_str(p.current_track()).is_equal(MusicPlayer.TRACKS[1])
	p.set_playing(false)
	assert_bool(p.get_node("Track").playing).is_false()
	MusicPlayer.music_dir = ""
