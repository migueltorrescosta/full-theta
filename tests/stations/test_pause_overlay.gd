extends GdUnitTestSuite
## The host pause in PauseOverlay and the menu's Pause control (FT-MIS-040).

const HOST_PAUSE: Dictionary = {"host": true, "ship": -1, "uncovered": [], "crew": 0}


func _heading(o: PauseOverlay) -> String:
	return ((o.get_child(0) as VBoxContainer).get_child(0) as Label).text


func _overlay(host: bool) -> Array:
	var ctx: StationContext = StationFixture.context("tactical")
	var o: PauseOverlay = auto_free(PauseOverlay.new())
	o.setup(ctx)
	add_child(o)
	ctx.crew.host = host
	return [ctx, o]


# FT: FT-MIS-040
func test_host_pause_text_and_resume_only_on_the_host() -> void:
	for host: bool in [true, false]:
		var made: Array = _overlay(host)
		var ctx: StationContext = made[0]
		var o: PauseOverlay = made[1]
		assert_bool(o.visible).is_false()
		ctx.crew.handle_event({"type": "pause", "payload": HOST_PAUSE}, 0)
		assert_bool(o.visible).is_true()
		assert_bool(ctx.crew.paused.is_empty()).is_true()
		assert_str(_heading(o)).is_equal(TranslationServer.translate("pause.host"))
		assert_object(o.find_child("Abandon", true, false)).is_null()
		assert_object(o.find_child("Vote", true, false)).is_null()
		var resume: Button = o.find_child("Resume", true, false)
		assert_bool(resume != null).is_equal(host)
		if host:
			resume.pressed.emit()
			var rec: StationFixture.RecordingClient = StationFixture.sent(ctx)
			assert_array(rec.of("host_pause")[0][1]).is_equal([false])
		ctx.crew.handle_event({"type": "resume", "payload": {"tick": 1, "host": true}}, 0)
		assert_bool(o.visible).is_false()


# FT: FT-MIS-040
# A host resume leaves a coverage pause (and its votes) in place.
func test_host_resume_keeps_the_coverage_pause() -> void:
	var made: Array = _overlay(true)
	var ctx: StationContext = made[0]
	var o: PauseOverlay = made[1]
	var pause: Dictionary = {"ship": 0, "uncovered": ["relay"], "crew": 2, "min_crew": 3}
	ctx.crew.handle_event({"type": "pause", "payload": pause}, 0)
	ctx.crew.handle_event({"type": "pause", "payload": HOST_PAUSE}, 0)
	assert_object(o.find_child("Resume", true, false)).is_not_null()
	ctx.crew.handle_event({"type": "resume", "payload": {"tick": 1, "host": true}}, 0)
	assert_bool(ctx.crew.paused.has(0)).is_true()
	assert_bool(o.visible).is_true()
	assert_object(o.find_child("Resume", true, false)).is_null()


# FT: FT-MIS-040
# The menu offers Pause to the co-op host only: not to a guest, not in PvP.
func test_pause_control_is_host_and_coop_only() -> void:
	var ctx: StationContext = StationFixture.context("tactical")
	var coop: Dictionary = {"ships": [{"id": 0, "faction": 0}, {"id": 1, "faction": 0}]}
	var pvp: Dictionary = {"ships": [{"id": 0, "faction": 0}, {"id": 1, "faction": 1}]}
	ctx.crew.catalogue = coop
	ctx.crew.host = true
	assert_bool(ctx.crew.can_host_pause()).is_true()
	ctx.crew.host = false
	assert_bool(ctx.crew.can_host_pause()).is_false()
	ctx.crew.host = true
	ctx.crew.catalogue = pvp
	assert_bool(ctx.crew.can_host_pause()).is_false()
	var menu: SettingsScreen = auto_free(SettingsScreen.new())
	menu.setup(ClientSettings.new("user://test_pause_overlay.cfg"), true)
	add_child(menu)
	assert_object(menu.find_child("HostPause", true, false)).is_null()
	menu.set_pause_control(true)
	var button: Button = menu.find_child("HostPause", true, false)
	assert_object(button).is_not_null()
	var fired: Array[bool] = [false]
	menu.host_pause_requested.connect(func() -> void: fired[0] = true)
	button.pressed.emit()
	assert_bool(fired[0]).is_true()
	menu.set_pause_control(false)
	assert_object(menu.find_child("HostPause", true, false)).is_null()
