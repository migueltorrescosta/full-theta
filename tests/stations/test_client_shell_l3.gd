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
# Over a real connection the lobby shows the six stations as grid cells bordered by their
# StationDef load tag in the Catalogue, Captain and Viewer below, and maps each pair of
# stations to its joint view in the Catalogue (D216).
func test_lobby_grid_follows_the_catalogue_load_tags_and_joint_views() -> void:
	var s: NetServer = _h.server()
	var c: NetClient = NetClient.new()
	c.name = "Ana"
	c.client_kind = "desktop"
	c.connect_to("ws://127.0.0.1:%d" % s.port())
	assert_bool(await _until(_welcomed.bind(c))).is_true()
	var shell: ClientShell = auto_free(ClientShell.new())
	shell.setup(c, ClientSettings.new(SETTINGS))
	add_child(shell)
	var cells: Callable = func() -> bool:
		return shell.lobby != null and shell.lobby.find_child("Entry_comms", true, false) != null
	assert_bool(await _until(cells)).is_true()
	assert_int(shell.ctx.crew.catalogue["entries"].size()).is_equal(23)
	for id: String in LobbyScreen.GRID_STATIONS:
		var cell: Button = shell.lobby.find_child("Entry_" + id, true, false)
		var tag: String = StationViews.def(id).load_tag
		assert_str(cell.theme_type_variation).is_equal("LoadCell_" + tag)
	for id: String in ["captain", "viewer", "all"]:
		assert_object(shell.lobby.find_child("Entry_" + id, true, false)).is_not_null()
	assert_str(shell.lobby.entry_for(["helm", "weapons"] as Array[String])).is_equal("tactical")
	assert_str(shell.lobby.entry_for(["relay", "comms"] as Array[String])).is_equal("ops")
