extends GdUnitTestSuite
## ClientShell with a scripted client: voice wiring (audio/README.md "Client"), the
## session language, events to the model, and lobby vs station screen.


## A welcomed client that hands out queued events and never touches a socket.
class FakeClient:
	extends NetClient
	var queued: Array[Dictionary] = []

	func poll() -> void:
		pass

	func take_events() -> Array[Dictionary]:
		var out: Array[Dictionary] = queued
		queued = []
		return out


func after_test() -> void:
	I18n.apply("en")
	get_tree().root.content_scale_factor = 1.0


func _shell(lang: String) -> ClientShell:
	var c: FakeClient = FakeClient.new()
	c.state = NetClient.State.WELCOMED
	c.welcome = {"session": 7, "ship": 0, "entry": "", "host": false, "dev_all": false}
	c.welcome["lang"] = lang
	c.catalogue = StationFixture.catalogue()
	var s: ClientShell = auto_free(ClientShell.new())
	s.setup(c, ClientSettings.new("user://test_client_shell_unit.cfg"))
	add_child(s)
	return s


# FT: FT-AUD-013, FT-AUD-010, FT-AUD-004
func test_voice_lines_reach_the_player_and_language_applies() -> void:
	var s: ClientShell = _shell("it")
	assert_str(TranslationServer.get_locale()).is_equal("it")
	assert_str(s.voice.local_lines.lang).is_equal("it")
	var c: FakeClient = s.ctx.client as FakeClient
	var line: Dictionary = {
		"clip": 1,
		"line": "",
		"text": "Contatto a ore 4.",
		"role": "computer",
		"priority": 1,
		"max_age_ms": 4000,
		"coalesce": "",
		"resume": false,
		"audio": false,
		"local": false,
	}
	c.queued.append({"seq": 1, "tick": 0, "type": VoiceService.EVENT_VOICE_LINE, "payload": line})
	c.queued.append({"seq": 2, "tick": 0, "type": "alert", "payload": {"ship": 0, "level": 1}})
	await get_tree().process_frame
	assert_int(s.ctx.crew.alert).is_equal(1)
	assert_int(s.voice.subtitles.active(Time.get_ticks_msec()).size()).is_equal(1)
	assert_str(s._subtitles.text).contains("Contatto a ore 4.")
	# D153: the computer bus carries the filter chain and sends to Voice.
	var bus: int = AudioServer.get_bus_index(VoiceBuses.COMPUTER)
	assert_int(bus).is_greater_equal(0)
	assert_str(AudioServer.get_bus_send(bus)).is_equal(VoiceBuses.VOICE)
	assert_int(AudioServer.get_bus_effect_count(bus)).is_equal(4)


func test_lobby_until_started_then_the_station_screen() -> void:
	var s: ClientShell = _shell("en")
	assert_object(s.lobby).is_not_null()
	var c: FakeClient = s.ctx.client as FakeClient
	c.queued.append({"type": "picked", "payload": {"ship": 0, "entry": "systems", "reason": ""}})
	await get_tree().process_frame
	assert_object(s.lobby).is_not_null()
	c.queued.append({"type": "started", "payload": {"ship": 0, "tick": 10}})
	await get_tree().process_frame
	assert_object(s.screen).is_not_null()
	assert_array(s.screen.stations).is_equal(["engineering", "science"])
