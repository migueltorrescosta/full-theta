extends GdUnitTestSuite
## The sound effects (FT-AUD-020, D308): which station hears which sim event, the clips
## on their own Sfx bus, and the provenance of every shipped clip and track.

const MANIFEST: String = "res://content/provenance.json"


func before_test() -> void:
	GameSounds.sounds_dir = MainMenu.SFX_SOUNDS


func after_test() -> void:
	GameSounds.sounds_dir = ""


func _sounds() -> GameSounds:
	var g: GameSounds = auto_free(GameSounds.new())
	add_child(g)
	return g


# FT: FT-AUD-020
func test_events_route_to_the_stations_that_hear_them() -> void:
	assert_str(GameSounds.clip_for(&"fired", ["weapons"], true)).is_equal("fire")
	assert_str(GameSounds.clip_for(&"fired", ["helm", "engineering"], true)).is_equal("")
	assert_str(GameSounds.clip_for(&"fired", ["weapons"], false)).is_equal("")
	assert_str(GameSounds.clip_for(&"docked", ["helm"], true)).is_equal("dock")
	assert_str(GameSounds.clip_for(&"undocked", ["helm"], true)).is_equal("undock")
	assert_str(GameSounds.clip_for(&"docked", ["science"], true)).is_equal("")
	assert_str(GameSounds.clip_for(&"destroyed", [], false)).is_equal("explosion")
	assert_str(GameSounds.clip_for(&"jump_spool", ["relay"], true)).is_equal("jump_charge")
	assert_str(GameSounds.clip_for(&"jump_arrive", [], true)).is_equal("jump")
	assert_str(GameSounds.clip_for(&"hit", ["helm"], true)).is_equal("")


# FT: FT-AUD-020
func test_every_clip_is_loaded_on_the_sfx_bus_and_repeats_are_gapped() -> void:
	var g: GameSounds = _sounds()
	for c: StringName in GameSounds.CLIPS:
		var p: AudioStreamPlayer = g.player_of(c)
		assert_str(p.bus).is_equal(GameSounds.BUS)
		assert_object(p.stream).is_not_null()
	var index: int = AudioServer.get_bus_index(GameSounds.BUS)
	assert_str(String(AudioServer.get_bus_send(index))).is_equal("Master")
	assert_bool(g.play(&"fire", 1000)).is_true()
	assert_bool(g.play(&"fire", 1050)).is_false()
	assert_bool(g.play(&"fire", 1200)).is_true()
	assert_bool(g.play(&"nothing", 1200)).is_false()
	assert_array(g.played).is_equal([&"fire", &"fire"])


# FT: FT-AUD-020, FT-LIC-006
func test_every_clip_and_track_has_a_cc0_manifest_entry_with_its_hash() -> void:
	var entries: Array = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))["entries"]
	var files: Array[String] = []
	for c: StringName in GameSounds.CLIPS:
		files.append("assets/sounds/sfx/%s.ogg" % c)
	for t: String in MusicPlayer.TRACKS:
		files.append("assets/music/%s.ogg" % t)
	for f: String in files:
		var found: Dictionary = {}
		for e: Dictionary in entries:
			if e.get("path", "") == f:
				found = e
		assert_bool(found.is_empty()).is_false()
		assert_str(found["licence"]).is_equal("CC0-1.0")
		assert_bool(found["kind"] in ["sound", "music"]).is_true()
		assert_str(FileAccess.get_sha256("res://" + f)).is_equal(found["sha256"])
