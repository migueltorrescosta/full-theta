class_name UiOverridesHook
extends GdUnitTestSessionHook
## A gdUnit4 session hook (registered in project.godot) that calls UiOverrides.reset() before
## every test case, so no test inherits a layout, safe area or held finger from the one before.
## gdUnit4 fires TESTCASE_BEFORE before the suite's before_test, so a seam set there survives.
## A seam set in a suite's before() or in the test itself still works; set in before(), it
## would be reset after the first test, so set it in before_test().


func _init() -> void:
	super("UiOverrides", "Resets the UI test seams (UiOverrides.reset) before each test.")


func startup(session: GdUnitTestSession) -> GdUnitResult:
	session.test_event.connect(_on_event)
	return GdUnitResult.success()


func shutdown(_session: GdUnitTestSession) -> GdUnitResult:
	return GdUnitResult.success()


func _on_event(event: GdUnitEvent) -> void:
	if event.type() == GdUnitEvent.TESTCASE_BEFORE:
		UiOverrides.reset()
