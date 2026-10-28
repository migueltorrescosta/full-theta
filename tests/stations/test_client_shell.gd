extends GdUnitTestSuite
## ClientShell with a scripted client: voice wiring (audio/README.md "Client"), the
## session language, events to the model, and lobby vs station screen.


## A welcomed client that hands out queued events and never touches a socket.
class FakeClient:
	extends NetClient
	var queued: Array[Dictionary] = []
	var said_bye: bool = false
	var frames: Array = []

	func report_frame(ms: int, what: String) -> void:
		frames.append([ms, what])

	func poll() -> void:
		pass

	func bye(_reason: String = "") -> void:
		said_bye = true

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
	assert_bool(await _until(func() -> bool: return s.screen != null)).is_true()
	assert_array(s.screen.stations).is_equal(["engineering", "science"])


# FT: FT-NET-003
# The lobby's Main menu button leaves the session: the client says Bye and the shell
# emits `left`, which the menu answers by stopping the host's server.
func test_lobby_main_menu_button_leaves() -> void:
	var s: ClientShell = _shell("en")
	var left: Array[bool] = []
	s.left.connect(func() -> void: left.append(true))
	(s.lobby.find_child("MainMenu", true, false) as Button).pressed.emit()
	assert_array(left).has_size(1)
	assert_bool((s.ctx.client as FakeClient).said_bye).is_true()


## A shell on the station screen of "systems" (ship 0, started); `fresh` makes it the
## first visit.
func _on_station(fresh: bool) -> ClientShell:
	var s: ClientShell = _shell("en")
	if fresh:
		s.ctx.settings.reset_tooltips()
	else:
		s.ctx.settings.mark_tooltip_seen("engineering")
		s.ctx.settings.mark_tooltip_seen("science")
	var c: FakeClient = s.ctx.client as FakeClient
	c.queued.append({"type": "picked", "payload": {"ship": 0, "entry": "systems", "reason": ""}})
	c.queued.append({"type": "started", "payload": {"ship": 0, "tick": 10}})
	await _until(func() -> bool: return s.screen != null)
	return s


## Waits up to 5 s of frames for `cond`.
func _until(cond: Callable) -> bool:
	var end: int = Time.get_ticks_msec() + 5000
	while not cond.call():
		if Time.get_ticks_msec() >= end:
			return false
		await get_tree().process_frame
	return true


## Picks `entry` on ship 0 (started) and waits for its screen; "" goes to the lobby.
func _pick(s: ClientShell, entry: String) -> void:
	var c: FakeClient = s.ctx.client as FakeClient
	c.queued.append({"type": "picked", "payload": {"ship": 0, "entry": entry, "reason": ""}})
	if entry == "":
		await _until(func() -> bool: return s.lobby != null)
	else:
		await _until(func() -> bool: return s.screen != null and s.ctx.crew.entry == entry)


func _labels(menu: SettingsScreen) -> Array[String]:
	var out: Array[String] = []
	for l: Node in menu.find_children("*", "Label", true, false):
		out.append((l as Label).text)
	return out


# FT: FT-STN-011
# Escape (the menu intent) opens the one menu on Game at first, Escape again closes it,
# and it comes back on the tab last used.
func test_escape_opens_the_menu() -> void:
	var s: ClientShell = await _on_station(false)
	var menu: SettingsScreen = s.settings_screen
	assert_bool(menu.visible).is_false()
	s.screen.dispatch({"id": "menu", "target": "screen", "pressed": true})
	assert_bool(menu.visible).is_true()
	assert_str(menu.current_tab_name()).is_equal(SettingsScreen.TAB_GAME)
	assert_bool(s.screen.blocked()).is_true()
	menu.open(SettingsScreen.TAB_TIPS)
	menu.close()
	s.screen.dispatch({"id": "menu", "target": "screen", "pressed": true})
	assert_str(menu.current_tab_name()).is_equal(SettingsScreen.TAB_TIPS)
	menu.close()
	assert_bool(s.screen.blocked()).is_false()


# FT: FT-STN-011
# `?` opens the same menu on Controls, from any tab, and a second press closes it.
func test_help_key_opens_the_controls_tab() -> void:
	var s: ClientShell = await _on_station(false)
	var menu: SettingsScreen = s.settings_screen
	menu.open(SettingsScreen.TAB_SETTINGS)
	s.screen.dispatch({"id": "overlay", "target": "screen", "pressed": true})
	assert_bool(menu.visible).is_true()
	assert_str(menu.current_tab_name()).is_equal(SettingsScreen.TAB_CONTROLS)
	assert_array(menu.controls.rows()).is_not_empty()
	s.screen.dispatch({"id": "overlay", "target": "screen", "pressed": true})
	assert_bool(menu.visible).is_false()


# FT: FT-STN-012
# The first visit opens the menu on Controls by itself, headed by the seat's role, and
# the screen takes no game input meanwhile.
func test_first_visit_opens_controls_with_the_role_heading() -> void:
	var s: ClientShell = await _on_station(true)
	var menu: SettingsScreen = s.settings_screen
	assert_bool(menu.visible).is_true()
	assert_str(menu.current_tab_name()).is_equal(SettingsScreen.TAB_CONTROLS)
	assert_array(_labels(menu)).contains([tr("role.systems")])
	assert_bool(s.screen.blocked()).is_true()


# FT: FT-STN-011, FT-AUD-013
# A language switch retranslates the open menu, tab and all.
func test_language_switch_retranslates_the_open_menu() -> void:
	var s: ClientShell = await _on_station(false)
	var menu: SettingsScreen = s.settings_screen
	menu.open(SettingsScreen.TAB_SETTINGS)
	assert_array(_labels(menu)).contains(["UI scale"])
	I18n.apply("it")
	assert_bool(menu.visible).is_true()
	assert_str(menu.current_tab_name()).is_equal(SettingsScreen.TAB_SETTINGS)
	assert_array(_labels(menu)).contains([tr("settings.ui_scale")])
	assert_array(_labels(menu)).not_contains(["UI scale"])
	var controls: int = menu.tabs.get_node(SettingsScreen.TAB_CONTROLS).get_index()
	assert_str(menu.tabs.get_tab_title(controls)).is_equal(tr("overlay.title"))


# A first visit shows the loading overlay with the station's name for a frame, then
# builds; a later visit of the same pick shows the kept screen at once, as it was left
# (#28, owner L-Keep).
func test_visited_screens_are_kept_and_shown_again() -> void:
	var s: ClientShell = _shell("en")
	var c: FakeClient = s.ctx.client as FakeClient
	c.queued.append({"type": "picked", "payload": {"ship": 0, "entry": "helm", "reason": ""}})
	c.queued.append({"type": "started", "payload": {"ship": 0, "tick": 10}})
	assert_bool(await _until(func() -> bool: return s._loading.visible)).is_true()
	assert_object(s.screen).is_null()
	assert_str(s._loading_name.text).is_equal(tr("station.helm"))
	assert_bool(await _until(func() -> bool: return s.screen != null)).is_true()
	assert_bool(s._loading.visible).is_false()
	var helm: StationScreen = s.screen
	await _pick(s, "")
	assert_bool(helm.visible).is_false()
	assert_int(helm.process_mode).is_equal(Node.PROCESS_MODE_DISABLED)
	await _pick(s, "systems")
	var systems: StationScreen = s.screen
	await _pick(s, "helm")
	assert_object(s.screen).is_same(helm)
	assert_bool(helm.visible and helm.is_processing()).is_true()
	assert_bool(systems.visible).is_false()
	assert_array(s.ctx.matcher._stations).is_equal(["helm"])


# Past MAX_SCREENS the least recently shown screen is freed; a run reset frees them all.
func test_kept_screens_are_bounded_and_go_on_reset() -> void:
	var s: ClientShell = _shell("en")
	var c: FakeClient = s.ctx.client as FakeClient
	c.queued.append({"type": "started", "payload": {"ship": 0, "tick": 10}})
	var first: StationScreen = null
	for entry: String in ["helm", "weapons", "relay", "comms", "science"]:
		await _pick(s, entry)
		if entry == "helm":
			first = s.screen
	assert_int(s._screens.size()).is_equal(ClientShell.MAX_SCREENS)
	await get_tree().process_frame
	assert_bool(is_instance_valid(first)).is_false()
	s.ctx.crew.reset_run()
	assert_int(s._screens.size()).is_equal(0)


# FT: FT-NET-025
# A resume of the same session with the same pick keeps the screen; a new session drops
# the kept screens and builds again (#28, load fix 3).
func test_resume_with_the_same_pick_keeps_the_screen() -> void:
	var s: ClientShell = await _on_station(false)
	var kept: StationScreen = s.screen
	var c: FakeClient = s.ctx.client as FakeClient
	var w: Dictionary = c.welcome.duplicate()
	w["entry"] = "systems"
	w["resumed"] = true
	c.welcome = w
	await get_tree().process_frame
	await get_tree().process_frame
	assert_object(s.screen).is_same(kept)
	var fresh: Dictionary = w.duplicate()
	fresh["session"] = 8
	c.welcome = fresh
	(
		assert_bool(await _until(func() -> bool: return s.screen != null and s.screen != kept))
		. is_true()
	)


# A hidden screen's alerts stop listening, so it never sounds a tone; they listen again
# when it shows.
func test_hidden_screen_sounds_no_tone() -> void:
	var s: ClientShell = _shell("en")
	var c: FakeClient = s.ctx.client as FakeClient
	c.queued.append({"type": "started", "payload": {"ship": 0, "tick": 10}})
	await _pick(s, "helm")
	var helm: StationScreen = s.screen
	await _pick(s, "weapons")
	s.ctx.crew.pinged.emit({})
	assert_array(helm.alerts.tones.played).is_empty()
	assert_array(s.screen.alerts.tones.played).is_equal([&"ping"])
	await _pick(s, "helm")
	s.ctx.crew.pinged.emit({})
	assert_array(helm.alerts.tones.played).is_equal([&"ping"])


# The lobby loads the pick's panel scripts; a frame over 500 ms is reported with what
# ran in it (#28, load fixes 7 and 10).
func test_lobby_preloads_the_pick_and_long_frames_are_reported() -> void:
	var s: ClientShell = _shell("en")
	var c: FakeClient = s.ctx.client as FakeClient
	c.queued.append({"type": "picked", "payload": {"ship": 0, "entry": "tactical", "reason": ""}})
	var loaded: Callable = func() -> bool: return s._scripts.has(StationRegistry.PANELS["weapons"])
	assert_bool(await _until(loaded)).is_true()
	assert_bool(s._scripts.has(StationRegistry.PANELS["helm"])).is_true()
	s._doing = ""
	s._frame_us = Time.get_ticks_usec() - 700_000
	s._note("build station:0:tactical")
	s._check_frame()
	assert_int(c.frames.size()).is_equal(1)
	assert_int(c.frames[0][0]).is_greater_equal(700)
	assert_str(c.frames[0][1]).is_equal("build station:0:tactical on lobby")
	s._check_frame()
	assert_int(c.frames.size()).is_equal(1)
