extends GdUnitTestSuite
## ClientShell against a real server over loopback (L3): Welcome and the Catalogue
## reach the lobby, a pick and Start bring up the station screen of the pick, events
## reach the CrewState model and snapshots the interpolator.

const SETTINGS: String = "user://test_client_shell.cfg"

var _h: NetHarness


func before_test() -> void:
	# The app applies a language at start (MainMenu); a shell built alone needs one.
	I18n.apply("en")
	_h = NetHarness.new(self)


func after_test() -> void:
	_h.free_all()
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func _until(cond: Callable, timeout_ms: int = NetHarness.TIMEOUT_MS) -> bool:
	var end: int = Time.get_ticks_msec() + timeout_ms
	while not cond.call():
		if Time.get_ticks_msec() >= end:
			return false
		await get_tree().process_frame
	return true


# FT: FT-M1-015, FT-NET-029
func test_shell_runs_lobby_to_station_with_the_dev_entry() -> void:
	var s: NetServer = _h.server(true)
	var c: NetClient = NetClient.new()
	c.name = "Ana"
	c.client_kind = "desktop"
	c.connect_to("ws://127.0.0.1:%d" % s.port())
	assert_bool(await _until(_welcomed.bind(c))).is_true()
	var shell: ClientShell = auto_free(ClientShell.new())
	shell.setup(c, ClientSettings.new(SETTINGS))
	add_child(shell)
	assert_bool(await _until(func() -> bool: return shell.lobby != null)).is_true()
	(
		assert_bool(await _until(func() -> bool: return not shell.ctx.crew.catalogue.is_empty()))
		. is_true()
	)
	assert_bool(shell.ctx.crew.dev_all).is_true()
	shell.ctx.intents.pick(NetHarness.PLAYER, StationViews.ALL)
	var picked: Callable = func() -> bool: return shell.ctx.crew.entry == StationViews.ALL
	assert_bool(await _until(picked)).is_true()
	(
		assert_bool(
			await _until(func() -> bool: return shell.ctx.crew.lobby.has(NetHarness.PLAYER))
		)
		. is_true()
	)
	shell.ctx.intents.start()
	assert_bool(await _until(func() -> bool: return shell.screen != null)).is_true()
	assert_int(shell.screen.panels.size()).is_equal(6)
	assert_bool(await _until(func() -> bool: return shell.ctx.interp.has_data())).is_true()
	assert_bool(await _until(func() -> bool: return shell.ctx.view.tick > 0)).is_true()
	assert_float(shell.ctx.interp.render_tick).is_less_equal(float(shell.ctx.view.tick))


func _welcomed(c: NetClient) -> bool:
	c.poll()
	return c.is_welcomed()


# FT: FT-STN-015, FT-JNT-006, FT-M1-018
# Over a real connection the lobby shows each entry's load tag from its StationDef in
# the Catalogue (the Viewer untagged), and each joint view's pair under its name (D186).
func test_lobby_shows_load_tags_and_joint_pairs_from_the_catalogue() -> void:
	var s: NetServer = _h.server()
	var c: NetClient = NetClient.new()
	c.name = "Ana"
	c.client_kind = "desktop"
	c.connect_to("ws://127.0.0.1:%d" % s.port())
	assert_bool(await _until(_welcomed.bind(c))).is_true()
	var shell: ClientShell = auto_free(ClientShell.new())
	shell.setup(c, ClientSettings.new(SETTINGS))
	add_child(shell)
	var rows: Callable = func() -> bool:
		return shell.lobby != null and shell.lobby.find_child("Entry_ops", true, false) != null
	assert_bool(await _until(rows)).is_true()
	var labels: Dictionary = {
		"tactical": "Tactical\nHelm + Weapons",
		"systems": "Systems\nEngineering + Science",
		"ops": "Ops\nRelay + Comms",
		"helm": "Helm",
	}
	var entries: Array = shell.ctx.crew.catalogue["entries"]
	assert_int(entries.size()).is_equal(11)
	for e: Dictionary in entries:
		var row: Node = shell.lobby.find_child("Entry_" + str(e["id"]), true, false)
		var tag: String = StationViews.def(e["id"]).load_tag
		var want: String = tr("load." + tag) if tag != "" else ""
		assert_str((row.get_node("LoadTag") as Label).text).is_equal(want)
		assert_object(row.get_node_or_null("Hint")).is_null()
		if labels.has(e["id"]):
			assert_str((row.get_node("Pick") as Button).text).is_equal(labels[e["id"]])
