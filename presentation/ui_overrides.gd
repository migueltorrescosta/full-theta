class_name UiOverrides
extends RefCounted
## Puts every process-wide test seam of the UI back to its default: the forced layout, the
## simulated safe area, the forced fullscreen buttons, the dismissed rotate banner, the
## registered sheet covers and the held touch fingers. tests/ui_overrides_hook.gd calls it
## before each test, so a test sets a seam and never has to reset it.


static func reset() -> void:
	LayoutMode.forced = -1
	SafeArea.simulate([])
	FullscreenButton.forced = -1
	FullscreenToggle.forced_on = -1
	RotateBanner.dismissed_here = false
	SheetCover.reset()
	TouchInput.reset()
