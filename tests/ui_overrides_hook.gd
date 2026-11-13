class_name UiOverridesHook
extends GdUnitTestSessionHook
## A gdUnit4 session hook (registered in project.godot) that puts every process-wide UI test
## seam back to its default before each test case (R13-18): the forced layout, the simulated
## safe area, the forced fullscreen buttons, the dismissed rotate banner, the registered sheet
## covers, the held touch fingers, the --dev flag and the handovers already shown. A test sets
## a seam and never has to reset it.
## gdUnit4 fires TESTCASE_BEFORE before the suite's before_test, so a seam set there survives.
## A seam set in a suite's before() or in the test itself still works; set in before(), it
## would be reset after the first test, so set it in before_test().


func _init() -> void:
	super("UiOverrides", "Resets the UI test seams before each test.")


func startup(session: GdUnitTestSession) -> GdUnitResult:
	session.test_event.connect(_on_event)
	return GdUnitResult.success()


func shutdown(_session: GdUnitTestSession) -> GdUnitResult:
	return GdUnitResult.success()


func _on_event(event: GdUnitEvent) -> void:
	if event.type() == GdUnitEvent.TESTCASE_BEFORE:
		LayoutMode.forced = -1
		SafeArea.simulate([])
		FullscreenButton.forced = -1
		FullscreenToggle.forced_on = -1
		RotateBanner.dismissed_here = false
		SheetCover.reset()
		TouchInput.reset()
		ClientSettings.dev_flag = OS.get_cmdline_user_args().has("--dev")
		HandoverNotice.seen.clear()
