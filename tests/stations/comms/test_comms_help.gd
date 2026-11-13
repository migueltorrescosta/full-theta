extends GdUnitTestSuite
## gp-14: Comms' Call for help: hidden while the COMMS block says Comms can't call, a button
## that sends comms_call_help like Shift+H while it can, and a countdown that takes no press
## while the patrol is on its way; the same on a phone's rail.

const SETTINGS: String = "user://test_comms_help.cfg"


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func _screen(size: Vector2i, help: int, eta: float = 0.0) -> StationScreen:
	var vp: SubViewport = auto_free(SubViewport.new())
	vp.size = size
	add_child(vp)
	var ctx: StationContext = StationFixture.context("comms", SETTINGS)
	var blk: Dictionary = CommsFixture.block()
	blk.merge({"help": help, "help_eta": eta}, true)
	CommsFixture.install(ctx, blk)
	var s: StationScreen = StationScreen.new()
	s.setup(ctx)
	vp.add_child(s)
	for i: int in 4:
		await get_tree().process_frame
	return s


func _drop(s: StationScreen) -> void:
	s.get_parent().remove_child(s)
	s.free()


# FT: FT-COM-010, FT-STN-005
func test_call_for_help_shows_only_when_it_acts_then_counts_down() -> void:
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(844, 390)]:
		var none: StationScreen = await _screen(size, BlockSchema.HELP_NONE)
		var p: CommsPanel = none.focused_panel()
		assert_bool(p._buttons["help"].visible).is_false()
		p.handle_intent(IntentEvent.of("comms_call_help"))
		assert_int(StationFixture.sent(none.ctx).of("command").size()).is_equal(0)
		_drop(none)
		var ready: StationScreen = await _screen(size, BlockSchema.HELP_READY)
		p = ready.focused_panel()
		var b: Button = p._buttons["help"]
		assert_bool(b.is_visible_in_tree()).override_failure_message(str(size)).is_true()
		assert_str(b.text).is_equal("Call for help")
		assert_bool(b.disabled).is_false()
		b.pressed.emit()
		p.handle_intent(IntentEvent.of("comms_call_help"))
		var cmds: Array = StationFixture.sent(ready.ctx).of("command")
		assert_int(cmds.size()).is_equal(2)
		for c: Array in cmds:
			assert_dict(c[1][0]).is_equal({"kind": "comms_call_help"})
		_drop(ready)
		var coming: StationScreen = await _screen(size, BlockSchema.HELP_COMING, 41.2)
		p = coming.focused_panel()
		b = p._buttons["help"]
		assert_bool(b.is_visible_in_tree()).is_true()
		assert_str(b.text).is_equal("Help in 42 s")
		assert_bool(b.disabled).is_true()
		assert_int(b.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
		p.handle_intent(IntentEvent.of("comms_call_help"))
		assert_int(StationFixture.sent(coming.ctx).of("command").size()).is_equal(0)
		_drop(coming)
