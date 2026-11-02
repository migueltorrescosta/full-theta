extends GdUnitTestSuite
## The Controls page warns Linux players on Helm that the touchpad may pause while a key is
## held (#35 A12, owner playtest 2026-11-02).


# FT: FT-STN-012
func test_the_touchpad_hint_shows_for_helm_on_linux_only() -> void:
	assert_bool(ControlsPane.touchpad_hint(["helm"], "Linux")).is_true()
	assert_bool(ControlsPane.touchpad_hint(["helm", "weapons"], "Linux")).is_true()
	assert_bool(ControlsPane.touchpad_hint(["engineering"], "Linux")).is_false()
	assert_bool(ControlsPane.touchpad_hint(["helm"], "Windows")).is_false()
	assert_bool(ControlsPane.touchpad_hint(["helm"], "macOS")).is_false()
