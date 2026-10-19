extends GdUnitTestSuite
## StationAlerts and AlertTones (T056): sim events, pings and alert-level changes show
## (toast, edge flash) and sound (AlertTones.played, the audio spy) on the stations they
## affect, through the same CrewState.handle_event path the client shell feeds.

const SHIP: int = StationFixture.SHIP


func before_test() -> void:
	I18n.apply("en")
	AlertTones.sounds_dir = MainMenu.ALERT_SOUNDS


func _screen(entry: String) -> StationScreen:
	var ctx: StationContext = StationFixture.context(entry)
	var s: StationScreen = auto_free(StationScreen.new())
	s.panel_factory = func(_st: String) -> StationPanel: return StationPanel.new()
	s.setup(ctx)
	add_child(s)
	return s


func _event(s: StationScreen, type: String, payload: Dictionary) -> void:
	var p: Dictionary = {
		"ship": SHIP, "faction": 0, "other": -1, "value": 0.0, "vector": Vector3.ZERO, "tag": ""
	}
	p.merge(payload, true)
	s.ctx.crew.handle_event({"type": type, "payload": p}, s.ctx.now_ms())


func _advance(s: StationScreen, ms: int) -> void:
	StationFixture.clock(s.ctx).ms += ms


func _played(s: StationScreen) -> Array[StringName]:
	return s.alerts.tones.played


func _flashing(s: StationScreen) -> bool:
	return s.flash.strength(s.ctx.now_ms()) > 0.0


# FT: FT-STN-004, FT-SIM-032, FT-M1-011
func test_a_hit_shows_and_sounds_on_every_station_with_its_direction() -> void:
	for entry: String in ["helm", "weapons", "engineering", "relay", "captain", "viewer"]:
		var s: StationScreen = _screen(entry)
		# Starboard, level: 3 o'clock (ship frame, -Z is the bow).
		_event(s, "hit", {"vector": Vector3(20.0, 0.0, 0.0)})
		assert_array(_played(s)).is_equal([&"hit"])
		assert_bool(_flashing(s)).is_true()
		assert_object(s.flash.color).is_equal(Palette.color("danger"))
		assert_array(s.toasts.texts()).is_equal(["Hit, 3 level"])


# FT: FT-STN-004, FT-M1-011
func test_a_burst_of_hits_keeps_one_toast_and_spaces_the_thumps() -> void:
	var s: StationScreen = _screen("helm")
	_event(s, "hit", {"vector": Vector3(0.0, 0.0, -20.0)})
	_advance(s, 50)
	_event(s, "hit", {"vector": Vector3(0.0, 0.0, -20.0)})
	_advance(s, AlertTones.GAP_MS[&"hit"])
	_event(s, "hit", {"vector": Vector3(0.0, 0.0, -20.0)})
	assert_array(_played(s)).is_equal([&"hit", &"hit"])
	assert_array(s.toasts.texts()).is_equal(["Hit, 12 level"])


# FT: FT-STN-004, FT-SIM-032
func test_low_shields_reach_helm_and_engineering_only() -> void:
	for entry: String in ["helm", "engineering", "tactical"]:
		var s: StationScreen = _screen(entry)
		_event(s, "shield_low", {"value": 0.38})
		assert_array(_played(s)).is_equal([&"shield_low"])
		assert_array(s.toasts.texts()).is_equal(["Shields 38 %"])
		assert_object(s.flash.color).is_equal(Palette.color("warn"))
	for entry: String in ["weapons", "relay", "viewer"]:
		var s: StationScreen = _screen(entry)
		_event(s, "shield_low", {"value": 0.38})
		assert_array(_played(s)).is_empty()
		assert_array(s.toasts.texts()).is_empty()
		assert_bool(_flashing(s)).is_false()


# FT: FT-STN-004, FT-SIM-032
func test_a_fault_sounds_on_engineering_and_shows_on_the_station_that_needs_it() -> void:
	var eng: StationScreen = _screen("engineering")
	_event(eng, "fault", {"value": 120.0, "tag": "weapons"})
	assert_array(_played(eng)).is_equal([&"fault"])
	assert_array(eng.toasts.texts()).is_equal(["Weapons fault"])
	# Weapons depends on its mounts: it sees the fault; the tone is Engineering's.
	var weapons: StationScreen = _screen("weapons")
	_event(weapons, "fault", {"value": 120.0, "tag": "weapons"})
	assert_array(_played(weapons)).is_empty()
	assert_array(weapons.toasts.texts()).is_equal(["Weapons fault"])
	assert_bool(_flashing(weapons)).is_true()
	var helm: StationScreen = _screen("helm")
	_event(helm, "fault", {"value": 120.0, "tag": "weapons"})
	assert_array(helm.toasts.texts()).is_empty()
	_event(helm, "fault", {"value": 120.0, "tag": "thrusters"})
	assert_array(helm.toasts.texts()).is_equal(["Thrusters fault"])
	assert_array(_played(helm)).is_empty()


# FT: FT-STN-004, FT-M1-011
func test_proximity_warns_helm_once_while_it_repeats() -> void:
	var s: StationScreen = _screen("helm")
	for i: int in 4:
		_event(s, "proximity", {"other": 3, "value": 4.0})
		_advance(s, 500)
	assert_array(_played(s)).is_equal([&"proximity"])
	assert_array(s.toasts.texts()).is_equal(["Collision course"])
	assert_bool(_flashing(s)).is_true()
	var w: StationScreen = _screen("weapons")
	_event(w, "proximity", {"other": 3, "value": 4.0})
	assert_array(_played(w)).is_empty()


# FT: FT-SIM-032
func test_other_ships_events_and_quiet_kinds_do_nothing() -> void:
	var s: StationScreen = _screen("engineering")
	_event(s, "hit", {"ship": 2, "vector": Vector3.FORWARD})
	_event(s, "fault", {"ship": 2, "tag": "reactor"})
	_event(s, "fired", {})
	assert_array(_played(s)).is_empty()
	assert_array(s.toasts.texts()).is_empty()
	assert_bool(_flashing(s)).is_false()


# FT: FT-SPA-016, FT-STN-008
func test_pings_chime_and_alert_changes_sound_their_level() -> void:
	var s: StationScreen = _screen("weapons")
	var ping: Dictionary = {"ship": SHIP, "kind": "contact", "id": 2, "by": "Bea", "copy": ""}
	s.ctx.crew.handle_event({"type": "ping", "payload": ping}, s.ctx.now_ms())
	# A copy (another station pinged the same item) is silent.
	ping["copy"] = "Bea"
	ping["by"] = "Cris"
	s.ctx.crew.handle_event({"type": "ping", "payload": ping}, s.ctx.now_ms())
	assert_array(_played(s)).is_equal([&"ping"])
	# The state sent after a pick has no setter: no tone.
	var alert: Dictionary = {"ship": SHIP, "level": CrewState.ALERT_YELLOW, "by": ""}
	s.ctx.crew.handle_event({"type": "alert", "payload": alert}, s.ctx.now_ms())
	alert = {"ship": SHIP, "level": CrewState.ALERT_RED, "by": "Ana"}
	s.ctx.crew.handle_event({"type": "alert", "payload": alert}, s.ctx.now_ms())
	alert = {"ship": SHIP, "level": CrewState.ALERT_NORMAL, "by": "Bea"}
	s.ctx.crew.handle_event({"type": "alert", "payload": alert}, s.ctx.now_ms())
	assert_array(_played(s)).is_equal([&"ping", &"alert_red", &"alert_normal"])
	assert_object(s.flash.color).is_equal(Palette.color("alert_normal"))


# FT: FT-AUD-009
func test_tones_play_on_their_own_bus_that_voice_never_blocks() -> void:
	VoiceBuses.ensure()
	var s: StationScreen = _screen("helm")
	var bus: int = AudioServer.get_bus_index(AlertTones.BUS)
	assert_int(bus).is_greater_equal(0)
	assert_str(AudioServer.get_bus_send(bus)).is_equal("Master")
	assert_int(AudioServer.get_bus_effect_count(bus)).is_equal(0)
	for t: StringName in AlertTones.TONES:
		var p: AudioStreamPlayer = s.alerts.tones.player_of(t)
		assert_str(p.bus).is_equal(AlertTones.BUS)
		assert_object(p.stream).is_not_null()
		# Short tones: under a second each.
		assert_float(p.stream.get_length()).is_less(1.0)
	_event(s, "hit", {"vector": Vector3.FORWARD})
	assert_bool(s.alerts.tones.player_of(&"hit").playing).is_true()
