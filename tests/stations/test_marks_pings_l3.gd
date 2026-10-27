extends GdUnitTestSuite
## Marks and pings on every station (L3, T054): a real server and one ClientShell per
## crew station plus a viewer and the Captain. Marks placed from a station's common
## action and from Relay's map, and pings and their copies, reach every client's model
## and radar picture; marks are selectable everywhere; the ping limit, the 8-mark cap
## and Relay's replacement work end to end. Comms comes up as a placeholder
## with the top bar.

const PLAYER: int = NetHarness.PLAYER
const ENEMY: int = NetHarness.ENEMY
const ENTRIES: Array[String] = [
	"helm", "weapons", "engineering", "science", "relay", "comms", "viewer", "captain"
]

var _h: NetHarness
var _shells: Dictionary = {}
var _chimes: Dictionary = {}
var _toasts: Dictionary = {}


func before() -> void:
	I18n.apply("en")


func before_test() -> void:
	_h = NetHarness.new(self)


func after_test() -> void:
	for entry: String in _shells:
		(_shells[entry] as ClientShell).queue_free()
		var path: String = _settings_path(entry)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_shells.clear()
	await _h.free_all()


# FT: FT-STN-003, FT-SPA-012, FT-SPA-013, FT-SPA-015, FT-SPA-016, FT-SPA-017, FT-SPA-020
# FT: FT-SPA-022, FT-SPA-031, FT-RLY-003, FT-M1-017, FT-M1-005
func test_marks_and_pings_reach_every_station() -> void:
	var server: NetServer = _h.server()
	for entry: String in ENTRIES:
		_shells[entry] = await _shell(server, entry)
	_shell_of("helm").ctx.intents.start()
	assert_bool(await _all(func(s: ClientShell) -> bool: return s.screen != null)).is_true()
	var seen: Callable = func(s: ClientShell) -> bool: return ENEMY in s.ctx.interp.contact_ids()
	assert_bool(await _all(seen)).is_true()
	# Science and Comms have their panels, with the top bar (FT-M1-005).
	assert_object(_shell_of("science").screen.panels[0]).is_instanceof(SciencePanel)
	for entry: String in ["science", "comms"]:
		var screen: StationScreen = _shell_of(entry).screen
		if entry == "comms":
			assert_object(screen.panels[0]).is_instanceof(CommsPanel)
		assert_str(screen.top_bar._name.text).is_equal(_shell_of(entry).ctx.crew.ship_name())
	# Science marks its selected contact with the common action (hold R3).
	var science: ClientShell = _shell_of("science")
	science.ctx.crew.select("contact", ENEMY)
	science.screen.dispatch(_ev("mark", science.screen))
	var one: Callable = func(s: ClientShell) -> bool:
		return s.ctx.crew.marks.size() == 1 and s.ctx.crew.marks[0]["contact"] == ENEMY
	assert_bool(await _all(one)).is_true()
	# Relay drags a free mark onto its map.
	var relay: ClientShell = _shell_of("relay")
	var map: RelayPanel = relay.screen.panels[0]
	relay.screen.set_anchors_preset(Control.PRESET_TOP_LEFT)
	relay.screen.size = Vector2(1280, 720)
	await get_tree().process_frame
	_drag(map, Vector2(60, 60), Vector2(140, 90))
	var two: Callable = func(s: ClientShell) -> bool:
		return s.ctx.crew.marks.size() == 2 and s.ctx.crew.marks[1]["contact"] == -1
	assert_bool(await _all(two)).is_true()
	for entry: String in ENTRIES:
		var ctx: StationContext = _shell_of(entry).ctx
		assert_str(ctx.crew.marks[1]["name"]).is_equal("Bravo")
		assert_str(ctx.crew.marks[1]["by"]).is_equal("relay")
		# Every station draws both marks and can select them (FT-SPA-015).
		var marks: Array = ctx.picture().items.filter(
			func(it: Dictionary) -> bool: return it["kind"] == "mark"
		)
		assert_int(marks.size()).override_failure_message(entry).is_equal(2)
		ctx.crew.select("mark", 0)
		assert_bool(ctx.selection_local() is Vector3).override_failure_message(entry).is_true()
	# Comms pings mark Alpha: it pulses everywhere with one chime; Engineering's ping on
	# the same mark is a silent copy naming Engineering (FT-SPA-031).
	var comms: ClientShell = _shell_of("comms")
	comms.screen.dispatch(_ev("ping", comms.screen))
	var pulsing: Callable = func(s: ClientShell) -> bool:
		return s.ctx.crew.pulse("mark", 0, s.ctx.now_ms()) > 0.0
	assert_bool(await _all(pulsing)).is_true()
	var eng: ClientShell = _shell_of("engineering")
	eng.screen.dispatch(_ev("ping", eng.screen))
	var copied: Callable = func(s: ClientShell) -> bool:
		var live: Array[Dictionary] = s.ctx.crew.live_pings(s.ctx.now_ms())
		return not live.is_empty() and "engineering" in live[0]["copies"]
	assert_bool(await _all(copied)).is_true()
	for entry: String in ENTRIES:
		assert_int(_chimes[entry]).override_failure_message(entry).is_equal(1)
		var c: StationContext = _shell_of(entry).ctx
		assert_float(c.crew.pulse("mark", 0, c.now_ms() + CrewState.PING_MS)).is_equal(0.0)
	# A point ping from Relay's map shows on every radar picture.
	relay.ctx.crew.select("", -1)
	relay.screen.dispatch(_ev("ping", relay.screen))
	var point: Callable = func(s: ClientShell) -> bool:
		return s.ctx.picture().items.any(func(it: Dictionary) -> bool: return it["kind"] == "point")
	assert_bool(await _all(point)).is_true()
	# The ping limit (FT-SPA-017): Helm's fourth ping in a burst is refused with a toast.
	var helm: ClientShell = _shell_of("helm")
	helm.ctx.crew.select("contact", ENEMY)
	for k: int in 4:
		helm.screen.dispatch(_ev("ping", helm.screen))
	var limited: Callable = func(_s: ClientShell) -> bool:
		return "toast.rate_limited" in _toasts["helm"]
	assert_bool(await _all(limited)).is_true()
	# Eight marks: a crew station gets the toast; Relay replaces the selected mark.
	for k: int in 6:
		helm.ctx.intents.place_mark(-1, "", -1, Vector3(5000.0 + 900.0 * k, 4000.0, 0.0))
	var full: Callable = func(s: ClientShell) -> bool:
		return s.ctx.crew.marks.size() == CrewState.MAX_MARKS
	assert_bool(await _all(full)).is_true()
	science.screen.dispatch(_ev("mark", science.screen))
	assert_array(science.screen.toasts.texts()).contains([tr("toast.marks_full")])
	relay.ctx.crew.select("mark", 4)
	relay.screen.dispatch(_ev("mark", relay.screen))
	var replaced: Callable = func(s: ClientShell) -> bool:
		var m: Dictionary = s.ctx.crew.mark_in_slot(4)
		return s.ctx.crew.marks.size() == CrewState.MAX_MARKS and m.get("by", "") == "relay"
	assert_bool(await _all(replaced)).is_true()


func _shell(server: NetServer, entry: String) -> ClientShell:
	var c: NetClient = NetClient.new()
	c.name = entry
	c.client_kind = "desktop"
	c.connect_to("ws://127.0.0.1:%d" % server.port())
	var welcomed: Callable = func() -> bool:
		c.poll()
		return c.is_welcomed()
	assert_bool(await _until(welcomed)).is_true()
	var settings: ClientSettings = ClientSettings.new(_settings_path(entry))
	for s: String in StationViews.CREW + ["viewer", "captain"]:
		settings.mark_tooltip_seen(s)
	var shell: ClientShell = ClientShell.new()
	shell.setup(c, settings)
	add_child(shell)
	_chimes[entry] = 0
	_toasts[entry] = []
	shell.ctx.crew.pinged.connect(func(_p: Dictionary) -> void: _chimes[entry] += 1)
	shell.ctx.crew.toast.connect(
		func(key: String, _a: Dictionary) -> void: (_toasts[entry] as Array).append(key)
	)
	var listed: Callable = func() -> bool: return not shell.ctx.crew.catalogue.is_empty()
	assert_bool(await _until(listed)).is_true()
	shell.ctx.intents.pick(PLAYER, entry)
	assert_bool(await _until(func() -> bool: return shell.ctx.crew.entry == entry)).is_true()
	return shell


func _shell_of(entry: String) -> ClientShell:
	return _shells[entry]


func _settings_path(entry: String) -> String:
	return "user://test_marks_pings_l3_%s.cfg" % entry


## The controller's common actions act under the reticle or the selection.
func _ev(id: String, s: StationScreen) -> Dictionary:
	var dev: String = IntentTable.PAD
	return {
		"id": id,
		"group": IntentTable.row(id)["group"],
		"target": IntentTable.target(id, dev, s.focused_station(), s.stations),
		"kind": IntentTable.row(id)["kind"],
		"pressed": true,
		"value": 1.0,
		"device": dev,
	}


func _drag(p: RelayPanel, from: Vector2, to: Vector2) -> void:
	var down: InputEventMouseButton = InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = from
	p._gui_input(down)
	var mm: InputEventMouseMotion = InputEventMouseMotion.new()
	mm.relative = to - from
	p._gui_input(mm)
	var up: InputEventMouseButton = down.duplicate()
	up.pressed = false
	up.position = to
	p._gui_input(up)


## Waits until cond holds for every shell.
func _all(cond: Callable) -> bool:
	return await _until(
		func() -> bool:
			return _shells.values().all(func(s: ClientShell) -> bool: return cond.call(s))
	)


func _until(cond: Callable, timeout_ms: int = NetHarness.TIMEOUT_MS) -> bool:
	var end: int = Time.get_ticks_msec() + timeout_ms
	while not cond.call():
		if Time.get_ticks_msec() >= end:
			return false
		await get_tree().process_frame
	return true
