extends GdUnitTestSuite
## app/web/shell.html: the loading overlay and the tip ticker, checked on the source (no
## browser here; the L6 tier loads the real export).

const SHELL: String = "res://app/web/shell.html"


func _source() -> String:
	return FileAccess.get_file_as_string(SHELL)


# FT: FT-NET-030
# The full-screen loading overlay sat over the canvas for good, so a tap never reached
# the join field (no focus, no keyboard on an iPad, #22): it has to go once the game says
# its lobby (or, when joining failed, its menu) is up, and at the latest 30 s after the
# engine started (#11, DC2).
func test_the_overlay_is_removed_when_the_game_is_ready() -> void:
	var src: String = _source()
	assert_str(src).contains("const statusEl = document.getElementById('status');")
	var ready: int = src.find("if (name === 'ready') {")
	assert_int(ready).is_greater(0)
	assert_str(src.substr(ready, src.find("return;", ready) - ready)).contains("statusEl.remove();")
	var started: int = src.find(".then(() => {")
	assert_int(started).is_greater(0)
	assert_str(src.substr(started, src.find("}, (err)", started) - started)).contains(
		"setTimeout(function () { setStage('ready'); }, 30000)"
	)


# FT: FT-NET-030
# #11 DC2: after the download the page shows the stages the game reports, never goes back
# to an earlier one, and draws "Starting the game" before the engine's long start task.
func test_the_page_shows_the_start_up_stages_in_order() -> void:
	var src: String = _source()
	assert_str(src).contains("const STAGES = ['download', 'start', 'connect', 'lobby', 'ready'];")
	assert_str(src).contains("window.ft.loadStage = setStage;")
	assert_str(src).contains("STAGES.indexOf(name) <= STAGES.indexOf(stage)")
	assert_str(src).contains("engine.start = function ()")
	assert_str(src).contains("return afterPaint().then(")
	for word: String in ["Starting the game", "Connecting", "Opening the lobby"]:
		assert_str(src).contains(word)
	# The fill and the sweep move by transform, which the browser animates off the main thread.
	assert_str(src).contains("fillEl.style.transform = 'scaleX('")
	assert_str(src).contains("#bar.busy::after")


# FT: FT-NET-030
# The stages the game reports (WebLoadStage) are the ones the page knows, in its order.
func test_the_games_stages_are_the_pages_stages() -> void:
	var src: String = _source()
	var order: Array[String] = ["connect", "lobby", "ready"]
	assert_array(WebLoadStage.STAGES).is_equal(order)
	var last: int = src.find("const STAGES = ")
	for stage: String in WebLoadStage.STAGES:
		var at: int = src.find("'%s'" % stage, last)
		assert_int(at).is_greater(last)
		last = at


# FT: FT-NET-030, FT-M1-019
# The loading screen (P28-Tips, P28-LoadBar): the tips are shuffled, each shows
# max(5 s, characters / 15 + 1 s), a tap on either half goes back or forward, and the
# bar under the tip follows the engine's real download progress.
func test_tips_rotate_with_the_owners_timing_over_a_real_progress_bar() -> void:
	var src: String = _source()
	assert_str(src).contains("const tips = shuffled(FT_TIPS.tips);")
	assert_str(src).contains("Math.max(5, text.length / 15 + 1)")
	assert_str(src).contains("e.clientX < box.left + box.width / 2 ? -1 : 1")
	assert_str(src).contains("engine.startGame({ onProgress: setProgress })")
	assert_str(src).contains("setBar(STAGE_BAR.download * pct / 100, false);")
	assert_str(src).contains("env(safe-area-inset-bottom")
	assert_str(src).not_contains("@keyframes ticker")


# FT: FT-NET-030, FT-M1-019
# The shell's copy of the tips is content/tips/tips.json, every tip in each language
# (tools/tips_shell.py writes it; its --check runs in l0).
func test_the_shells_tips_are_the_tips_file() -> void:
	var src: String = _source()
	var start: int = src.find("const FT_TIPS = ")
	assert_int(start).is_greater(0)
	var line: String = src.substr(start, src.find("\n", start) - start)
	var copy: Dictionary = JSON.parse_string(line.trim_prefix("const FT_TIPS = ").trim_suffix(";"))
	var data: Dictionary = TipsView.read()
	assert_int((copy["tips"] as Array).size()).is_equal((data["tips"] as Array).size())
	for i: int in (data["tips"] as Array).size():
		var tip: Dictionary = data["tips"][i]
		for lang: String in I18n.LANGUAGES:
			assert_str(str(copy["tips"][i][lang])).is_equal(str(tip[lang]))
