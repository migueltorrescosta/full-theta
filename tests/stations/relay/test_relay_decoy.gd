extends GdUnitTestSuite
## gp-13: Relay's decoy button on the desktop HUD and the phone rail: shown only while the
## RELAY block says a decoy can go (a probe in stock and a hostile in play), sending
## launch_decoy like the U key; a decoy's row counts its seconds down.

const SETTINGS: String = "user://test_relay_decoy.cfg"


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func _block(decoy: bool, probes: Array = []) -> Dictionary:
	return {"stock": 2, "fab_left": 0.0, "lanes": false, "decoy": decoy, "probes": probes}


func _screen(size: Vector2i) -> StationScreen:
	var vp: SubViewport = auto_free(SubViewport.new())
	vp.size = size
	add_child(vp)
	var ctx: StationContext = StationFixture.context("relay", SETTINGS)
	ctx.snap.blocks[StationCatalogue.Section.RELAY] = _block(false)
	var s: StationScreen = StationScreen.new()
	s.setup(ctx)
	vp.add_child(s)
	for i: int in 4:
		await get_tree().process_frame
	return s


func _relay(s: StationScreen) -> RelayPanel:
	return s.panels[s.stations.find("relay")] as RelayPanel


# FT: FT-RLY-013, FT-STN-005
func test_decoy_shows_only_while_it_can_go_and_sends_launch_decoy() -> void:
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(844, 390)]:
		var s: StationScreen = await _screen(size)
		var p: RelayPanel = _relay(s)
		p.refresh()
		var button: Control = p.phone.buttons["decoy"] if p.phone != null else p.hud.decoy
		assert_bool(button.visible).override_failure_message("%s calm" % size).is_false()
		# The key does nothing while it can't act.
		p.handle_intent(IntentEvent.of("decoy_launch"))
		assert_int(StationFixture.sent(s.ctx).of("command").size()).is_equal(0)
		s.ctx.snap.blocks[StationCatalogue.Section.RELAY] = _block(true)
		p.refresh()
		assert_bool(button.visible).override_failure_message("%s fight" % size).is_true()
		(button as BaseButton).pressed.emit()
		p.handle_intent(IntentEvent.of("decoy_launch"))
		var cmds: Array = StationFixture.sent(s.ctx).of("command")
		assert_int(cmds.size()).is_equal(2)
		for c: Array in cmds:
			assert_dict(c[1][0]).is_equal({"kind": "launch_decoy"})
		s.get_parent().remove_child(s)
		s.free()


# FT: FT-RLY-013, FT-RLY-006
func test_a_decoy_row_counts_down() -> void:
	var s: StationScreen = await _screen(Vector2i(1280, 720))
	var p: RelayPanel = _relay(s)
	var decoy: Dictionary = {
		"serial": 2, "deployed": true, "pos": Vector3(3000, 0, 0), "range": 8000.0, "decoy": 12.4
	}
	s.ctx.snap.blocks[StationCatalogue.Section.RELAY] = _block(true, [decoy])
	p.refresh()
	assert_str((p.hud._probe_rows.get_child(0) as Label).text).is_equal("P3 decoy, 13 s")
	s.get_parent().remove_child(s)
	s.free()
