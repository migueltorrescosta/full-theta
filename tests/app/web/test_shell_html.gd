extends GdUnitTestSuite
## app/web/shell.html: the loading overlay and the tip ticker, checked on the source (no
## browser here; the L6 tier loads the real export).

const SHELL: String = "res://app/web/shell.html"


func _source() -> String:
	return FileAccess.get_file_as_string(SHELL)


# FT: FT-NET-030
# The full-screen loading overlay sat over the canvas for good, so a tap never reached
# the join field (no focus, no keyboard on an iPad, #22): it has to go once the engine
# runs.
func test_the_overlay_is_removed_when_the_engine_starts() -> void:
	var src: String = _source()
	assert_str(src).contains("const statusEl = document.getElementById('status');")
	var started: int = src.find(".then(() => {")
	assert_int(started).is_greater(0)
	assert_str(src.substr(started, src.find("}, (err)", started) - started)).contains(
		"statusEl.remove();"
	)


# FT: FT-NET-030
# The tips scroll as a ticker of a doubled strip in a shuffled order, and rotate only
# for reduced motion.
func test_tips_scroll_as_a_shuffled_doubled_strip_with_a_reduced_motion_fallback() -> void:
	var src: String = _source()
	assert_str(src).contains("@keyframes ticker")
	assert_str(src).contains("const tips = shuffled(LOADING_TIPS);")
	assert_str(src).contains("strip.textContent = line + line;")
	assert_str(src).contains("prefers-reduced-motion: reduce")
	assert_str(src).contains("setInterval(showNextTip, 4000)")
